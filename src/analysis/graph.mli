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


type graph
(** Type for task graph. *)


type node = string
(** The type of nodes. *)


type edge_t
(** The type of edges. *)


type edge_label =
  | Contain
  | Before
  | Include
  | In
  | In_task
  | Out
(** This type specifies the edge labels of the graph. *)


type graph_format =
  | Dot
  | Csv
(** A type that represents different formats for storing task graphs. *)


type graph_scan = string list list
(** Type that represents the output of the DFS algorithm.
 
 In particular, this type contains all nodes that are visited by the
 given source node. *)


val string_of_label : edge_label -> string
(** Converts an edge label to a string. *)


val empty_graph : unit -> graph
(** Creates an empty graph. *)


val add_node : node -> graph -> graph
(** Adds the specified node to the task graph. *)


val add_edge : node -> node -> edge_label -> graph -> graph
(** Adds the specified edge to the task graph. *)


val get_edges : graph -> node -> edge_t option
(** Gets the edges of the graph.
    Returns None if graph does not contain the given node. *)


val exist_edges : (node * edge_label -> bool) -> edge_t -> bool
(** Iterate the given edges and checks whether there is any function
    that satisfies the given predicate. *)


val fold_edges : ((node * edge_label) -> 'a -> 'a) -> edge_t -> 'a -> 'a
(** Performs folding on the edges of the graph. *)


val reachable :
  ?labels: edge_label list
  -> graph -> string  -> Util.StringSet.t
(** Finds the set of nodes that are reachable from the given source. *)


val dfs : graph -> string -> string -> bool -> graph_scan option
(** This function implements a DFS algorithm.
 
 Given a source node on a graph, this function computes
 all nodes that are visited by the source node.

 This function returns the all the paths from the source node to
 the target. *)


val happens_before : graph -> string -> string -> graph_scan option -> bool
(** Check the first build task `happens-before` the second one
   with regards to the given task graph. *)

val is_path :
  (string -> edge_label -> string -> bool)
  -> graph
  -> string list
  -> bool


val exists : graph -> string -> bool
(** Check whether the given abstraction exists in the provided
  task graph. *)


val to_dot : graph -> string -> unit
(** Output the given task graph to a .dot file. *)


val to_csv : graph -> string -> unit
(** Output the given task graph to a csv file. *)
