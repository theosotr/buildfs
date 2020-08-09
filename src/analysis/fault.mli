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


type fault_collection
(** A type representing faults. *)


val empty_faults : unit -> fault_collection
(** Creates an empty fault collection. *)


val report_faults : Task_info.task_info -> fault_collection -> unit
(** Reports the given faults to standard output. *)


val add_fault :
  string
  -> string
  -> string
  -> Analyzer.file_acc_t
  -> fault_collection
  -> fault_collection
(** Adds a fault related to a single file access performed by the given task. *)


val add_conflict_fault :
  string
  -> string
  -> string
  -> Analyzer.file_acc_t * Analyzer.file_acc_t
  -> fault_collection
  -> fault_collection
(** Adds a fault related to a conlict between the file accesses of two
    tasks. *)
