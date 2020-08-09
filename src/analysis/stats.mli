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


type t
(** Type for representing statistics. *)


val begin_counter : t -> t
(** Start counting time. *)


val add_analysis_time : t -> t
(** Consider elapsed time (from the last `begin_counter()` call)
    as the analysis time. *)


val add_bug_detection_time : t -> t
(** Consider elapsed time (from the last `begin_counter()` call)
    as the bug detection time. *)


val add_trace_entry : t -> t
(** Increment the trace entry counter. *)


val add_task : string -> t -> t
(** Add the given task. *)


val add_files : int -> t -> t
(** Add the number of files. *)


val add_conflict : t -> t
(** Increment the conflict counter. *)


val add_dfs_taversal : t -> t
(** Increment the DFS traversal counter. *)


val init_stats : unit -> t
(** Initializes stats. *)


val print_stats : t -> unit
(** Print stats to standard output. *)
