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


type option_status =
  | Ok (** Options are OK. *)
  | Err of string (** Options are invalid. It comes with an informative message. *)
(** A helper type that is useful for validating user-specified options. *)


type mode =
  | Online
  | Offline
(** Represents the mode of analysis.
    It's either online or offline. *)


module type ToolType =
  sig
    type tool_options
    (** Type representing tool-specific options specified by user. *)

    val validate_options : mode -> tool_options -> option_status
    (** A function used to validate tool-specific options
        that are provided by the user. *)

    val construct_command : tool_options -> string array
    (** Constructs the command to trace based on the options given by the
        user. *)

    module SysParser : Sys_parser.S
    (** This is the module responsible for parsing execution trace. *)

    module TraceAnalyzer : Analyzer.S
    (** This is the module responsible for analyzing generated trace. *)

    module FaultDetector : Fault_detection.S with type tool_options = tool_options
    (** This is the module responsible for detecting faults. *)

  end


module type S =
  sig
    type generic_options =
      {mode: mode; (** Mode of analysis. *)
       graph_file: string option; (** Output task graph to the specified file. *)
       graph_format: Graph.graph_format; (** Format of generated task graph. *)
       print_stats: bool; (** Print statistics about analysis. *)
       trace_file: string option; (** Path to system call trace file. *)
       dump_tool_out: string option; (** Dump tool output to this file. *)
      }


    type tool_options
    (** Type representing tool-specific options specified by user. *)


    val online_analysis : generic_options -> tool_options -> unit
    (** This function traces the execution of a script ,
      collects its system call trace.

      The analysis of traces is online and is done while the
      tool script is running. *)


    val offline_analysis : generic_options -> tool_options -> unit
    (** Performs an offline analysis of system call trace.
       This function expects a file where the system call trace
       stemming from tool execution. *)
  end


module Make (T : ToolType) : S with type tool_options = T.tool_options
(** A functor for building an implementation that is responsible for
    detecting faults regarding the processing of file system resources.

    The module is parameterised by a tool-specific module that customises
    analysis in various aspects, such as trace parsing, trace analysis,
    fault detection, etc. *)
