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


type error_kind =
  | ParserError of (string * int) (* An error that occurs during the parsing of traces. *)
  | InterpretationError of Syntax.syscall_desc (* An error that occurs during the interpretation of traces. *)
  | ToolError (* An error that occurs and it is tool-specific (e.g., Gradle-specific) *)
  | ExecutorError (* An error that occurs in the executor component. *)
  | InternalError (* An unexpected error. *)
  | GenericError  (* A generic and expected error. *)
(** Different kinds of errors that can appear in BuildFS. *)


exception Error of (error_kind * string option)


val string_of_error : error_kind -> string
(** This function converts an error type to a string. *)
