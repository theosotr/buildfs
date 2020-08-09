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


let cache = Hashtbl.create 5000


type tool_options = Build_options.tool_options


type tool_info = unit


let ignore_dirs = true


let min = "MIN", "Missing Input"
let mout = "MOUT", "Missing Output"


let filter_conflict (x, y) =

  let t1, t2 = extract_task x, extract_task y in
  [
    ":lint";
    ":violations";
    ":validatePlugin";
    ":violations";
    ":codenarcMain";
    ":codenarcTest";
    ":kapt";
  ]
  |> List.exists (fun x -> Util.string_contains t1 x || Util.string_contains t2 x) ||
  (Util.string_contains t1 "jar" && Util.string_contains t2 "compile") ||
  (Util.string_contains t1 "jar" && Util.string_contains t2 "Compile") ||
  (Util.string_contains t1 "jar" && Util.string_contains t2 "Debug") ||
  (Util.string_contains t1 "jar" && Util.string_contains t2 "Release") ||
  (Util.string_contains t1 "Debug" && Util.string_contains t2 "Release") ||
  (Util.string_contains t1 "Release" && Util.string_contains t2 "Debug")


let adapt_tasks x y _ =
  x, y


let patterns = [
  Str.regexp (".*/\\.transforms/.*$");
  Str.regexp (".*/build/cache.*$");
  Str.regexp (".*/intermediates/.*");
  Str.regexp (".*/docs?$");
  Str.regexp (".*build/generated/res/resValues/debug");
  Str.regexp (".*LICENSE$");
  Str.regexp (".*HEADER$");
  Str.regexp (".*READMΕ\\(.md\\)?$");
  Str.regexp (".*README.md$");
  Str.regexp (".*NOTICE.*$");
  Str.regexp (".*.git[a-z]*$");
  Str.regexp (".*.git/.*$");
  Str.regexp (".*/\\.gradle/.*$");
  Str.regexp (".*/gradlew\\(.bat\\)?$");
  Str.regexp (".*/publish.sh$");
  Str.regexp (".*/Jenkinsfile$");
  Str.regexp (".*\\.travis.yml$");
  Str.regexp (".*plugin/build.gradle$");
  Str.regexp (".*/gradle\\.properties$");
  Str.regexp (".*/gradle/wrapper/.*");
  Str.regexp (".*/build/tmp/.*");
  Str.regexp (".*/settings.gradle$");
  Str.regexp (".*/\\.sandbox/.*$");
  Str.regexp (".*build/pluginDescriptors$");
  Str.regexp (".*.AndroidManifest.xml$");
  Str.regexp (".*/main/res/.*$");
  Str.regexp (".*/generated/res/.*$");
  Str.regexp (".*/main/assets/.*$");
  Str.regexp (".*/\\.gitattributes$");
  Str.regexp (".*/build$");
  Str.regexp (".*/\\.jks$");
  Str.regexp (".*\\.keystore$");
  Str.regexp (".*\\.log$");
  Str.regexp (".*\\.github$");
  Str.regexp (".*\\.dependabot$");
  Str.regexp (".*/subprojects$");
  Str.regexp (".*/images$");
]


let filter_resource { build_dir = dir; _ } resource =
  not (Util.check_prefix dir resource) ||
  List.exists (fun x -> Str.string_match x resource 0) patterns



let add_fault resource (f_name, f_desc) file_acc faults =
  Fault.add_fault f_name f_desc resource file_acc faults


let is_output resource faccs graph =
  faccs
  |> List.filter (fun (x, _) ->
    match x with
    | Produced _ -> true
    | _          -> false)
  |> List.map (fun x -> x |> extract_task |> Graph.get_edges graph) 
  |> List.exists (fun x ->
    match x with
    | None       -> false
    | Some edges -> Graph.exist_edges (fun (node, label) ->
      Util.check_prefix node resource && (label = Graph.Out)) edges)


let detect_build_fault resource task task_graph add_fault f faults =
  match Graph.get_edges task_graph task with
  | None       -> add_fault faults
  | Some edges ->
    if not (
      Graph.exist_edges (fun (node, label) ->
        Util.check_prefix node resource && (f label)) edges)
    then add_fault faults
    else faults


let cache_out = Hashtbl.create 15000


(* This function is needed to identify indirect inputs
   for a a particular task. *)
let is_indirect_input faccs target graph =
  faccs
  |> List.filter (fun (x, _) ->
    match x with
    | Consumed _ -> true
    | _          -> false)
  |> List.map (fun x -> x |> extract_task)
  |> List.exists (fun x ->
    if String.equal x target
    then false
    else
      let dfs_out =
        match Hashtbl.find_opt cache_out (x, target) with
        | Some dfs_out -> dfs_out
        | None         ->
          let dfs_out = Graph.dfs graph x target false in
          Hashtbl.add cache_out (x, target) dfs_out;
          dfs_out
      in
      match dfs_out with
      | None | Some [] -> false
      | _              -> true
  )


let is_direct_input task resource graph =
  match Graph.get_edges graph task with
  | None -> false
  | Some edges -> Graph.exist_edges (fun (node, label) ->
    Util.check_prefix node resource && (label = Graph.In)) edges


let detect_min resource faccs (aout, _) { build_dir = dir; _ } bout =
  if not (Util.check_prefix dir resource)
  then bout
  else
    if is_output resource faccs aout.Analyzer.task_graph
    then bout
    else
      faccs
      |> List.fold_left (fun bout (facc, sdesc as t) ->
        match facc with
        | Consumed task when Syntax.is_main task                          -> bout
        | Consumed task when Util.string_contains task "Release"          -> bout 
        | Consumed task when Util.string_contains task "Debug"            -> bout 
        | Consumed task when Util.string_contains task ":lint"            -> bout
        | Consumed task when is_direct_input task resource aout.task_graph -> bout
        | Consumed task when is_indirect_input faccs task aout.task_graph  -> bout
        | Consumed task ->
          { bout with
            faults = add_fault resource min t bout.faults }
        | _ -> bout
      ) bout


let process_file_access resource options faccs state bout =
  detect_min resource faccs state options bout


let process_access_conflict resource { ignore_mout = ignore_mout; _; }
    conflict (aout, _) bout =
  if ignore_mout
  then bout
  else
    match conflict with
    | (Produced x, d), (Consumed y, _)
    | (Consumed y, _), (Produced x, d) -> (
      if String.equal x y ||
       (Util.string_contains x "Release") || (Util.string_contains x "Debug")
      then bout
      else
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


let refine_analysis_out _ analysis_out =
  analysis_out, Task_info.empty_task_info (), ()
