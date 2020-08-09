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
(** The statements of BuildFS used to model all the system calls. *)


type syscall_desc =
  {syscall: string; (** The name of the system call. *)
   args: string; (** The string corresponding to the arguments of the system call. *)
   ret: string; (** The return value of the system call. *)
   err: string option; (** The error type and message of a failed system call. *)
   line: int; (** The line where the system call appears in traces. *)
  }
(** A record that stores all the information of a certain system
  call trace. *)


type trace = (string * (statement * syscall_desc))
(** The type representing a statement in BuildFS.
  Every entry consists of a string value corresponding to PID,
  the BuildFS statement and the system call description. *)


type 'a stream =
  | Stream of 'a * (unit -> 'a stream)
  | Empty
(** A polymorphic type representing a stream. *)


val main_block : string
(** String representing the main execution block. *)


val is_main : string -> bool
(** Checks whether the given block is the main block. *)


val dummy_statement : statement -> int -> trace
(** Generates a dummy statement for the given statement*)


val string_of_syscall : syscall_desc -> string
(** This function converts a system call description into a string
  without including the number of the line where the system call appears. *)

val string_of_syscall_desc : syscall_desc -> string
(** This function converts a system call description into a string. *)


val string_of_trace : (statement * syscall_desc) -> string
(** This function converts an BuildFS statement along with
  its system call description into a string. *)


val next_trace : trace stream -> trace stream
(** This function expects a stream of traces and returns
  the next stream (if any). *)


val peek_trace : trace stream -> trace option
(** This function expects a stream of traces and
 and returns the current trace (if any). *)
