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


let gradle_msg = "##GRADLE##[ ]\\(.*\\)"
let gradle_regex =  Str.regexp ("write[v]?([12][0-9][0-9],[ ]+\"" ^ gradle_msg ^ "\".*")
let regex_group = 1


let stop_pattern = "##GRADLE## BUILD ENDED"


let is_tool_debug_msg syscall_line =
  Util.check_prefix "writev(" syscall_line ||
    Util.check_prefix "write(" syscall_line


let regex = Str.regexp "@@"


let replace_spaces str =
  Str.global_replace regex " " str


let model_syscall syscall_line =
  if Str.string_match gradle_regex syscall_line 0
  then
    try
      let gradle_line = Str.matched_group regex_group syscall_line in
      match Core.String.split_on_chars ~on: [ ' ' ] gradle_line with
      | "newTask" :: _           -> Syntax.Nop
      | [ "Begin"; t; ]          -> Syntax.Begin_task t
      | [ "End"; t; ]            -> Syntax.End_task t
      | [ "dependsOn"; t1; t2; ] -> Syntax.DependsOn (t1, t2)
      | [ "consumes"; t; p; ]    -> Syntax.Input (t, p |> replace_spaces)
      | [ "produces"; t; p; ]    -> Syntax.Output (t, p |> replace_spaces)
      | _                        ->
        raise (Errors.Error (Errors.GenericError, Some "Unable to parse line"))
    with Not_found -> Syntax.Nop
  else Syntax.Nop


let stop_parser line =
  Util.string_contains line stop_pattern
