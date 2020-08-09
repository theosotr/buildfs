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


open Util


type t =
  {analysis_time: float;
   bug_detection_time: float;
   files: int;
   tasks: StringSet.t;
   conflicts: int;
   dfs_traversals: int;
   entries: int;
   time_counter: float option;
  }


let begin_counter stats =
  { stats with time_counter = Some (Unix.gettimeofday ()); }


let add_analysis_time stats =
  match stats with
  | { time_counter = None; _ }   -> stats
  | { time_counter = Some v; _ } ->
    let t = Unix.gettimeofday () in
    { stats with analysis_time =  t -. v}


let add_bug_detection_time stats =
  match stats with
  | { time_counter = None; _ }   -> stats
  | { time_counter = Some v; _ } ->
    let t = Unix.gettimeofday () in
    { stats with bug_detection_time =  t -. v}


let add_trace_entry stats =
  { stats with entries = 1 + stats.entries }


let add_task task stats =
  { stats with tasks = task ++ stats.tasks }


let add_files files stats =
  { stats with files = files }


let add_conflict stats =
  { stats with conflicts = 1 + stats.conflicts }


let add_dfs_taversal stats =
  { stats with dfs_traversals = 1 + stats.dfs_traversals }


let print_stats stats =
  let info_preamble, end_str = "\x1b[0;32m", "\x1b[0m" in
  let print_entry x y =
    print_endline (x ^ ": " ^ y)
  in
  begin
    print_endline (info_preamble ^ "Statistics");
    print_endline "----------";
    print_entry "Trace entries" (string_of_int stats.entries);
    print_entry "Tasks" (stats.tasks |> StringSet.cardinal |> string_of_int);
    print_entry "Files" (string_of_int stats.files);
    print_entry "Conflicts" (string_of_int stats.conflicts);
    print_entry "DFS traversals" (string_of_int stats.dfs_traversals);
    print_entry "Analysis time" (string_of_float stats.analysis_time);
    print_entry "Bug detection time" (string_of_float stats.bug_detection_time);
    print_string end_str;
  end


let init_stats () =
  {analysis_time = 0.0;
   bug_detection_time = 0.0;
   files = 0;
   entries = 0;
   dfs_traversals = 0;
   conflicts = 0;
   tasks = StringSet.empty;
   time_counter = None;
  }
