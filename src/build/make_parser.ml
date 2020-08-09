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


let make_msg = "##MAKE##[ ]\\(.*\\)"
let make_regex =  Str.regexp ("write[v]?(1,[ ]+\"" ^ make_msg ^ "\\\\n\".*")
let regex_group = 1

let stop_pattern = "##MAKE## BUILD ENDED"


let is_tool_debug_msg syscall_line =
  Util.check_prefix "writev(1," syscall_line ||
    Util.check_prefix "write(1," syscall_line


let model_syscall syscall_line =
  if Str.string_match make_regex syscall_line 0
  then
    try
      match
        syscall_line
        |> Str.matched_group regex_group
        |> Core.String.strip ~drop: (fun x -> x = '\n')
        |> Core.String.split_on_chars ~on: [ ' ' ]
      with
      | [ "End" ]       -> Syntax.End_task ""
      | [ "Begin"; t; ] -> (
        let len = String.length t in
        match String.get t (len - 1) with
        | ':' -> Syntax.Begin_task Syntax.main_block
        | _   -> Syntax.Begin_task t)
      | _               ->
        raise (Errors.Error (Errors.GenericError, Some "Unable to parse line"))
    with Not_found -> Syntax.Nop
  else Syntax.Nop


let stop_parser line =
  Util.string_contains line stop_pattern
