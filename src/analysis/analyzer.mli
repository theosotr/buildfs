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


type file_acc_t = Domains.abstraction_effect * Syntax.syscall_desc
(** This type represents a a file access.
    A file access is a pair of effect and a syscall description.

    The effect denotes the effect of a particular task execution
    on this file, while the system call description is used for debugging
    purposes and indicates the actual system call that we stem this
    effect from. *)


type f_accesses = file_acc_t list Util.Strings.t
(** This type captures all file accesses performed
    during the task executions of the tool. 
 
  For example, it captures what kind of system resources,
  every task consumes or produces. *)


type analysis_out = {
  facc: f_accesses; (** File accesses. *)
  task_graph: Graph.graph; (** Task graph. *)
  dirs: Util.StringSet.t; (** Set of directories. *)
}
(** Record representing analysis output. *)


module type ToolType =
  sig
    val adapt_effect :
      string
      -> Domains.syscall_effect
      -> (string * Domains.abstraction_effect)
    (** Adapts the effect on a system resource based on the given
      resource name. *)
  end


module type S =
  sig
    val analyze_traces :
      Stats.t
      -> Syntax.trace Syntax.stream
      -> Stats.t * analysis_out
    (** Analyzes every trace and produces file accesses and task graph. *)
  end


module Make (T : ToolType) : S
(** A functor for building the implementation of an analyzer
    that computes file accesses and infers task graph
    through examining execution trace of tool script. *)
