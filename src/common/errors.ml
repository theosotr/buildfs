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
  | ParserError of (string * int)
  | InterpretationError of Syntax.syscall_desc
  | ToolError
  | ExecutorError
  | InternalError
  | GenericError


let string_of_error = function
  | ParserError (syscall, line) ->
    "Parser Error: " ^ syscall ^ ": " ^ (string_of_int line)
  | InterpretationError sdesc ->
    "Interpretation Error: " ^ (Syntax.string_of_syscall_desc sdesc)
  | ToolError           -> "Tool Error"
  | ExecutorError       -> "Executor Error"
  | InternalError       -> "Internal Error"
  | GenericError        -> "Error"


exception Error of (error_kind * string option)
