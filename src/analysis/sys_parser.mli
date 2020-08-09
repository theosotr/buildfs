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


module type ToolParserType =
  sig
    val is_tool_debug_msg : string -> bool
    (** Checks if the given system call is a debug message
      produced by the tool. *)


    val model_syscall : string -> Syntax.statement
    (** This function identifies and model the points where
      the execution of a certain build task begins or ends. *)

    val stop_parser : string -> bool
    (** This function checks whether a certain build has terminated.

      This function is used by the parser to ignore any subsequent system calls. *)
  end


module type S =
  sig
      val parse_trace_fd :
        string option
        -> Unix.file_descr
        -> Syntax.trace Syntax.stream
      (** Reads strace output from a file descriptor and parses it
          to produce a stream of traces.

          This file descriptor can correspond to a pipe, so this enables
          to run the analysis while executing the build
          (online analysis). *)

      val parse_trace_file :
        string option
        -> string
        -> Syntax.trace Syntax.stream
      (** Parses a trace file (produced by the strace tool) and
        produces a stream of traces.

        For memory efficiency and in order to handle large files of
        execution traces, every line of the file is parsed only when it
        is needed (i.e. only when the resulting trace is used). *)
  end


module Make (T : ToolParserType) : S
(** Functor for building an implementation of parser given a
    a tool type that gives the rule for identifying tool-related
    debug messages which are useful for detecting what kind
    of tool-related resources are executed each time. *)
