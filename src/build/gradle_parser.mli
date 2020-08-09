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


val is_tool_debug_msg : string -> bool
(** Checks if the given system call corresponds to a debug message
    produced by Gradle. *)


val model_syscall : string -> Syntax.statement
(** This function identifies and model the points where
  the application of a certain Gradle task begins or ends.

  In the context of Gradle, those points correspond to writes
  a file descriptor greater than 100. *)

val stop_parser : string -> bool
(** This function checks whether the execution of a Gradle script ends.
  
  This function is used by the parser to ignore any subsequent system calls. *)
