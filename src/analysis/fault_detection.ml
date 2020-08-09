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


open Domains
open Util


type t =
  {faults: Fault.fault_collection;
   stats: Stats.t;
  }


module type ToolType =
  sig
    type tool_options

    type tool_info

    val ignore_dirs : bool

    val filter_resource : tool_options -> string -> bool

    val filter_conflict : Analyzer.file_acc_t * Analyzer.file_acc_t -> bool

    val adapt_tasks : string -> string -> Graph.graph -> string * string

    val refine_analysis_out :
      tool_options
      -> Analyzer.analysis_out
      -> (Analyzer.analysis_out * Task_info.task_info * tool_info) 

    val process_file_access :
      string
      -> tool_options
      -> Analyzer.file_acc_t list
      -> (Analyzer.analysis_out * tool_info)
      -> t
      -> t

    val process_access_conflict :
      string
      -> tool_options
      -> Analyzer.file_acc_t * Analyzer.file_acc_t
      -> (Analyzer.analysis_out * tool_info)
      -> t
      -> t
  end


module type S =
  sig
    type tool_options

    val detect_faults :
      ?print_stats: bool
      -> ?graph_format: Graph.graph_format
      -> Stats.t
      -> string option
      -> tool_options
      -> Analyzer.analysis_out
      -> unit
  end


module Make(T: ToolType) = struct

  type tool_options = T.tool_options


  let cache_size = 5000
  (* A cache that store the result of the `Task_graph.dfs`
     functions. *)


  let dfs_cache = Hashtbl.create cache_size


  let ov = "OV", "Ordering Violation"


  let non_consumed x =
    match x with
    | Produced _, _ | Expunged _, _ -> true
    | _                             -> false


  let is_consumed x =
    match x with
    | Consumed _, _ | Modified _, _ -> true
    | _                             -> false


  let get_2combinations lst =
    let rec _get_2combinations l accum =
      match l with
      | [] -> accum
      | h :: t ->
        let accum' = accum @ (List.rev_map (fun x -> (h, x)) t) in
        _get_2combinations t accum'
    in _get_2combinations lst []


  let get_cartesian lst lst' = 
    List.concat (List.rev_map (fun x -> List.rev_map (fun y -> (x, y)) lst') lst)


  (**
   * Filters the case when a system resource is
   * consumed and produced by the same tool's unit.
   *)
  let get_cartesian_and_filter lst lst' =
    List.filter (fun (x, y) ->
      (extract_task x) <> (extract_task y)
    ) (get_cartesian lst lst')


  let visit_nodes stats graph task cache =
    match Hashtbl.find_opt dfs_cache task with
    | Some out -> stats, out
    | None     ->
      (* Find all nodes that are reachable from 'task' with respect
         to the given edge labels. *)
      let out = Graph.reachable
        ~labels: [Graph.Contain; Graph.Before; Graph.Include]
        graph task
      in
      Hashtbl.add dfs_cache task out;
      Stats.add_dfs_taversal stats, out


  let add_fault resource conflict (f_name, f_desc) faults =
    Fault.add_conflict_fault f_name f_desc resource conflict faults


  let create_bout faults stats =
    {stats = stats;
     faults = faults;
    }


  let process_access_conflict resource options (aout, _ as t) task facc
                              conflicts bout =
    let stats, out = visit_nodes bout.stats
                                 aout.Analyzer.task_graph task dfs_cache in
    let bout = { bout with stats = stats; } in
    List.fold_left (fun bout facc' ->
      let { faults = faults; stats = stats; } = bout in
      let conflict = facc, facc' in
      match conflict with
      | (Produced x, _), (Consumed y, _)
      | (Produced x, _), (Modified y, _)
      | (Produced x, _), (Produced y, _)
      | (Expunged x, _), (Modified y, _)
      | (Expunged x, _), (Consumed y, _) -> (
        (* Ignore conflicts involving the main execution block. *)
        if Syntax.is_main x || Syntax.is_main y
        then bout
        else
          let bout = { bout with stats = Stats.add_conflict stats } in
          if T.filter_conflict conflict
          then create_bout faults stats
          else
            let process_non_consumed { faults = faults; stats = stats; } =
              if non_consumed facc'
              then
                if StringSet.mem y out
                then create_bout faults stats
                else
                  let stats, out' = visit_nodes stats aout.task_graph y dfs_cache in
                  if StringSet.mem x out'
                  then create_bout faults stats
                  else
                    {stats = stats;
                     faults = add_fault resource conflict ov faults}
              else create_bout faults stats
            and process_consumed { faults = faults; stats = stats; } =
              if is_consumed facc'
              then
                if StringSet.mem y out
                then create_bout faults stats
                else
                  let stats, out' = visit_nodes stats aout.task_graph y dfs_cache in
                  if StringSet.mem x out'
                  then create_bout faults stats
                  else create_bout (add_fault resource conflict ov faults) stats
              else create_bout faults stats
            in
            bout
            |> process_non_consumed
            |> process_consumed
            |> T.process_access_conflict resource options conflict t)
      | _ -> bout
    ) bout conflicts


  let ignore_resource resource dirs =
    String.equal "/dev/null" resource ||
    Util.check_prefix "/proc" resource ||
    (T.ignore_dirs && StringSet.mem resource dirs)


  let process_conflicts state options resource effects bout =
    let conflicts =
      match
        List.filter non_consumed effects,
        List.filter is_consumed effects
      with
      | [], _                  -> Strings.empty
      | non_consumed, consumed ->
        let tasks = non_consumed @ consumed in
        List.fold_left (fun acc x ->
          let t1 = extract_task x in
          List.fold_left (fun acc y ->
            let t2 = extract_task y in
            if String.equal t1 t2
            then acc
            else
              match Strings.find_opt t1 acc, Strings.find_opt t2 acc with
              | None, None           -> Strings.add t1 (x, [y]) acc
              | None, Some (y, yv)   -> Strings.add t2 (y, (x :: yv)) acc
              | Some (x, xv), None
              | Some (x, xv), Some _ -> Strings.add t1 (x, (y :: xv)) acc
          ) acc tasks
        ) Strings.empty non_consumed
    in
    Strings.fold (fun task (facc, conflicts) bout ->
      process_access_conflict resource options state task facc conflicts bout
    ) conflicts bout


  let process_resource (aout, toolinf as t) options resource effects bout =
    if ignore_resource resource aout.Analyzer.dirs ||
       T.filter_resource options resource
    then bout
    else
      bout
      |> T.process_file_access resource options effects t
      |> process_conflicts t options resource effects


  let detect_faults ?(print_stats=true) ?(graph_format=Graph.Dot)
                    stats graph_file options analysis_out =
    let stats = Stats.begin_counter stats in
    let aout, tinfo, tool_info = T.refine_analysis_out options analysis_out in
    let _ =
      (* Stores task graph to a file in the specified format. *)
      match graph_format, graph_file with
      | _, None                    -> ()
      | Graph.Dot, Some graph_file -> Graph.to_dot aout.task_graph graph_file
      | Graph.Csv, Some graph_file -> Graph.to_csv aout.task_graph graph_file
    in
    let {stats = stats; faults = faults; } =
      { stats = stats; faults = Fault.empty_faults (); }
      |> Strings.fold (fun resource effects acc ->
        process_resource (aout, tool_info) options resource effects acc
      ) analysis_out.facc
    in
    let _ =
      stats
      |> Stats.add_bug_detection_time
      |> if print_stats then Stats.print_stats else fun _ -> ()
    in
    Fault.report_faults tinfo faults
end
