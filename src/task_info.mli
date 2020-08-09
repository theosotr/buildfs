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


type task_desc =
  {
    name:  string; (** The name of task. *) 
    file:  string option; (** The file where this task is declared. *)
    line:  string option; (** The line where this task is declared. *)
  }


type task_info


type ignored_tasks_t


val empty_task_info : unit -> task_info


val empty_ignored_tasks : unit -> ignored_tasks_t


val add_ignored_task : string -> ignored_tasks_t -> ignored_tasks_t


val is_ignored : string -> ignored_tasks_t -> bool


val add_task_desc : string -> task_desc -> task_info -> task_info


val get_task_desc:  string -> task_info -> task_desc option


val string_of_task_desc: task_desc -> string
