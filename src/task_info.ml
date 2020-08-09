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


type task_desc =
  {
    name:  string; (** The name of task. *) 
    file:  string option; (** The file where this task is declared. *)
    line:  string option; (** The line where this task is declared. *)
  }


type task_info = task_desc Util.Strings.t


type ignored_tasks_t = Util.StringSet.t


let empty_task_info () =
  Util.Strings.empty


let empty_ignored_tasks () =
  Util.StringSet.empty


let add_ignored_task task ignored_tasks =
  task ++ ignored_tasks


let is_ignored task ignored_tasks =
  Util.StringSet.exists (fun elem -> task = elem) ignored_tasks


let add_task_desc task task_desc task_info =
  Util.Strings.add task task_desc task_info


let get_task_desc task task_info =
  Util.Strings.find_opt task task_info


let string_of_task_desc task_desc =
  match task_desc with
  | { file = Some file; line = Some line; _ } ->
    task_desc.name ^ ": " ^ file ^ ": " ^ line
  | _ -> task_desc.name
