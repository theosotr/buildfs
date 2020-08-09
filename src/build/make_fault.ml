(*
 * Copyright (c) 2018-2020 Thodoris Sotiropoulos
 *
 * This program is free software: you can redistribute it and/or modify  
 * it under the terms of the GNU General Public License as published by  
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but 
 * WITHOUT ANY WARRANTY; without even the implied warranty of 
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU 
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License 
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 *)


open Build_options
open Domains
open Fault_detection
open Util


type read_point =
  | FileDesc of Unix.file_descr
  | File of string


let make_executor_err msg =
  raise (Errors.Error (Errors.ExecutorError, Some msg))


let string_of_unix_err err call params =
  Printf.sprintf "%s: %s (%s)" (Unix.error_message err) call params


let cache = Hashtbl.create 5000
let min_cache = Hashtbl.create 10000


type tool_options = Build_options.tool_options


type tool_info = Util.StringSet.t


let ignore_dirs = true


let min = "MIN", "Missing Input"
let mout = "MOUT", "Missing Output"


let patterns = [
  Str.regexp (".*Makefile$");
  Str.regexp (".*Makefile\\.[^/]");
  Str.regexp (".*.git$");
  Str.regexp (".*.git/.*$");
  Str.regexp (".*libtool$");
  Str.regexp (".*/.*\\.d$");
  Str.regexp (".*/\\.gitmodules$");
]


let dep_target = Str.regexp (".*/deps/.*$")


let filter_resource { build_dir = dir; _ } resource =
  not (Util.check_prefix dir resource) ||
  List.exists (fun x -> Str.string_match x resource 0) patterns


let filter_conflict (_, _) =
  false


let adapt_tasks x y _ =
  x, y


let add_fault resource (f_name, f_desc) file_acc faults =
  Fault.add_fault f_name f_desc resource file_acc faults


let is_output resource faccs graph =
  faccs
  |> List.exists (fun (x, _) ->
    match x with
    | Produced _ -> true
    | _          -> false)


let detect_build_fault resource task task_graph add_fault f faults =
  match Graph.get_edges task_graph task with
  | None       -> add_fault faults
  | Some edges ->
    if not (
      Graph.exist_edges (fun (node, label) ->
        Util.check_prefix node resource && (f label)) edges)
    then add_fault faults
    else faults


let is_direct_input task resource graph =
  match Graph.get_edges graph task with
  | None -> false
  | Some edges -> Graph.exist_edges (fun (node, label) ->
    Util.check_prefix node resource && (label = Graph.In)) edges


let detect_min resource faccs (aout, phonys) { build_dir = dir; _ } bout =
  if not (Util.check_prefix dir resource)
  then bout
  else
    if is_output resource faccs aout.Analyzer.task_graph
    then bout
    else
      faccs
      |> List.fold_left (fun bout (facc, sdesc) ->
        let { faults = faults; stats = stats; } = bout in
        (* Ignore missing input when one of the following
           conditions hold:

          * Task is the main task.
          * Task represents a phony target.
          * Resource has been declared as direct input of this task.*)
        match facc with
        | Consumed task when Syntax.is_main task                          -> bout
        | Consumed task when Util.StringSet.mem task phonys               -> bout
        | Consumed task when is_direct_input resource task aout.task_graph -> bout
        | Consumed task when Str.string_match dep_target task  0          -> bout
        | Consumed task -> (
          let stats, out =
            match Hashtbl.find_opt min_cache (task, resource) with
            | None ->
                let out =
                  Graph.reachable
                    ~labels: [Graph.In_task]
                    aout.task_graph task
                in
              Hashtbl.add min_cache (task, resource) out;
              Stats.add_dfs_taversal stats, out
            | Some out -> stats, out
          in
          if (
            Util.StringSet.exists (fun task' ->
              match Graph.get_edges aout.task_graph task' with
              | None -> false
              | Some edges -> Graph.exist_edges (fun (node, label) ->
                  Util.check_prefix node resource && label = Graph.In)
                edges) out)
          then { bout with stats = stats; }
          else
            {stats = stats;
             faults = add_fault resource min (facc, sdesc) faults })
        | _ -> bout
      ) bout


let process_file_access resource options faccs state bout =
   bout |> detect_min resource faccs state options


let process_access_conflict resource { ignore_mout = ignore_mout; _; }
    conflict (aout, _) bout =
  if ignore_mout
  then bout
  else
    match conflict with
    | (Produced x, _), (Consumed y, _)
    | (Consumed y, _), (Produced x, _) when String.equal x y -> bout
    | (Produced x, d), (Consumed y, _)
    | (Consumed y, _), (Produced x, d) -> (
      let faults = detect_build_fault
        resource
        x aout.Analyzer.task_graph
        (fun y ->
          match Hashtbl.find_opt cache (resource, x) with
          | None    ->
            Hashtbl.add cache (resource, x) true;
            add_fault resource mout (Produced x, d) y
          | Some _ -> y)
        (fun y -> y = Graph.Out)
        bout.faults
      in { bout with faults = faults; })
    | _ -> bout


let curdir_regex = Str.regexp "CURDIR := \\(.*\\)"
let target_regex = Str.regexp "^\\([^=#%]+\\):[ ]*\\([^=#%]*\\)$"
let object_regex = Str.regexp "\\(.*\\)\\.o$"
let not_target_msg = "# Not a target:"


let process_phony target currdir prereqs phonys =
  match target with
  | ".PHONY" -> (
    match Core.String.split_on_chars ~on: [ ' ' ] prereqs with
    | [""]     -> phonys
    | ptargets ->
      List.fold_left (fun acc x -> (currdir ^ ":" ^ x) ++ acc) phonys ptargets)
  | _ -> phonys


let process_line (prev_target, currdir, targets, phonys) line =
  if String.equal line not_target_msg
  then false, currdir, targets, phonys
  else
    match Util.check_prefix "#" line with
    | true  -> true, currdir, targets, phonys
    | false ->
      if Str.string_match target_regex line 0
      then
        let target, prereqs =
          Str.matched_group 1 line,
          Str.matched_group 2 line
        in
        let prereqs =
          if Str.string_match object_regex target 0
          then prereqs ^ " " ^ ((Str.matched_group 1 target) ^ ".c")
          else prereqs
        in
        let phonys = process_phony target currdir prereqs phonys in
        let target_name = currdir ^ ":" ^ target in
        match Util.Strings.find_opt target_name targets with
        | None ->
          let spec = (prev_target, currdir, prereqs) in
          true, currdir, Util.Strings.add target_name spec targets, phonys
        | Some (is_target, _, prereqs') ->
          let spec = (prev_target || is_target, currdir, prereqs ^ " " ^ prereqs') in
          true, currdir, Util.Strings.add target_name spec targets, phonys
      else
        if Str.string_match curdir_regex line 0
        then true, Str.matched_group 1 line, targets, phonys
        else true, currdir, targets, phonys


let build_make_graph read_p graph =
  let in_channel =
    match read_p with
    | File file   -> open_in file
    | FileDesc fd -> Unix.in_channel_of_descr fd
  in
  let rec _build_graph channel state =
    match input_line channel with
    | line ->
      line
      |> process_line state
      |> _build_graph channel
    | exception End_of_file ->
      close_in channel; state
  in
  let _, _, targets, phonys =
    _build_graph in_channel (true, "", Util.Strings.empty, Util.StringSet.empty)
  in
  Util.Strings.fold (fun name (is_target, curdir, prereqs) graph ->
    if not is_target
    then graph
    else
      match Core.String.split_on_chars ~on: [ ' ' ] prereqs with
      | [ "" ]  -> graph
      | prereqs ->
        List.fold_left (fun graph x ->
          let target = curdir ^ ":" ^ x in
          let path =
            if Util.check_prefix "/" x
            then x
            else 
              (curdir ^ "/" ^ x)
              |> Fpath.v
              |> Fpath.normalize
              |> Fpath.to_string
          in
          match Util.Strings.find_opt target targets with
          | None               -> graph
          | Some (false, _, _) ->
            Graph.add_edge name path Graph.In graph
          | Some (true, _, _)  ->
            graph
            (* FIXME: Handle transitive inputs in a better way. *)
            |> Graph.add_edge name path Graph.In
            |> Graph.add_edge name target Graph.In_task
            |> Graph.add_edge target name Graph.Before
        ) graph prereqs
  ) targets graph, phonys


let build_make_graph_online graph =
  let output, input = Unix.pipe () in
  (* We create a child process that is responsible for invoking
   strace and run 'make -pn' in parallel. *)
  match Unix.fork () with
  | 0   ->
    Unix.close output;
    let fd = Unix.openfile "/dev/null" [
      Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o640
    in
    let _ = Unix.dup2 input Unix.stdout in
    let _ = Unix.dup2 fd Unix.stderr in
    let _ = Unix.close fd in
    let args = [| "make"; "-pn"; |] in
    ignore (Unix.execv "/usr/bin/make" args);
    exit 254
  | _ ->
    Unix.close input;
    build_make_graph (FileDesc output) graph
  | exception Unix.Unix_error (err, call, params) ->
    params |> string_of_unix_err err call |> make_executor_err


let build_make_graph_offline filename graph =
  build_make_graph (File filename) graph


let refine_analysis_out { build_db = build_db; _ } analysis_out =
  let graph, phonys =
    match build_db with
    | None    -> build_make_graph_online analysis_out.Analyzer.task_graph
    | Some db -> build_make_graph_offline db analysis_out.task_graph
  in
  { analysis_out with Analyzer.task_graph = graph; },
  Task_info.empty_task_info (), phonys
