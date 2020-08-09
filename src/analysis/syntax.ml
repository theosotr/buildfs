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


exception Empty_stream


type eff =
  | Cons
  | Expunge
  | Prod


type fd_var =
  | CWD
  | Fd of string


type path =
  | Unknown of string
  | Path of string


type expr =
  | P of path
  | V of fd_var
  | At of (fd_var * path)


type statement =
  | Let of (fd_var * expr)
  | Del of expr
  | Consume of expr
  | Produce of expr
  | Input of (string * string)
  | Output of (string * string)
  | DependsOn of (string * string)
  | Newproc of string
  | Begin_task of string
  | End_task of string
  | Nop


type 'a stream =
  | Stream of 'a * (unit -> 'a stream)
  | Empty


type syscall_desc =
  {syscall: string;
   args: string;
   ret: string;
   err: string option;
   line: int;
  }


type trace = (string * (statement * syscall_desc))


let main_block = "main"


let is_main block =
  String.equal block main_block


let dummy_statement statement line =
  "",
  (statement, {syscall = "dummy";
               args = "dumargs";
               ret = "0";
               err = None;
               line = line;})


let string_of_syscall sdesc =
  match sdesc with
  | {syscall = v1; args = v2; ret = v3; err = None; _ } ->
    v1 ^ "(" ^ v2 ^ ") = " ^ v3
  | {syscall = v1; args = v2; ret = v3; err = Some err; _ } ->
    v1 ^ "(" ^ v2 ^ ") = " ^ v3 ^ " " ^ err


let string_of_syscall_desc sdesc =
  match sdesc with
  | {syscall = v1; args = v2; ret = v3; err = None; line = v4 } ->
    "#" ^ (string_of_int v4) ^ " " ^ v1 ^ "(" ^ v2 ^ ") = " ^ v3
  | {syscall = v1; args = v2; ret = v3; err = Some err; line = v5} ->
    "#" ^ (string_of_int v5) ^ " " ^ v1 ^ "(" ^ v2 ^ ") = " ^ v3 ^ " " ^ err


let string_of_line line =
  "(" ^ (string_of_int line) ^ ")"


let string_of_path path =
  match path with
  | Path x | Unknown x -> x


let string_of_varfd d =
  match d with
  | CWD  -> "fd0"
  | Fd f -> "fd" ^ f


let string_of_expr e =
  match e with
  | P p -> string_of_path p
  | V v -> string_of_varfd v
  | At (v, p) -> (string_of_path p) ^ " at " ^ (string_of_varfd v)


let string_of_trace (trace, sdesc) =
  let line_str = string_of_line sdesc.line in
  let str_list = (
    match trace with
    | Begin_task t       -> ["task"; t; "{"; line_str;]
    | End_task _         -> ["}"; line_str;]
    | Nop                -> ["nop"]
    | Let (v, e)         -> ["let"; string_of_varfd v; "="; string_of_expr e; line_str;]
    | Del e              -> ["del(fd"; string_of_expr e; line_str; ]
    | Newproc f          -> ["newproc"; f; line_str;]
    | Consume e          -> ["consume"; string_of_expr e; line_str;]
    | Produce e          -> ["produce"; string_of_expr e; line_str;]
    | Input (t, p)       -> ["input"; t; p; line_str;]
    | Output (t, p)      -> ["output"; t; p; line_str;]
    | DependsOn (t1, t2) -> ["dependsOn"; t1; t2; line_str;]
  ) in
  String.concat " " str_list


let next_trace traces =
  match traces with
  | Stream (_, thunk) -> thunk ()
  | Empty -> raise Empty_stream


let peek_trace traces =
  match traces with
  | Stream (v, _) -> Some v
  | Empty -> None
