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


module Strings : Map.S with type key = string
(** A module that implements a map of strings. *)


module Ints : Map.S with type key = int
(** A module that implements a map of integers. *)


module StringPair : Map.S with type key = (string * string)
(** A module that implements a map of pairs of strings. *)


module StringSet : Set.S with type elt = string
(** A module that implements a set of strings. *)


val check_prefix : string -> string -> bool
(** Check whether the second string starts with the second one. *)


val is_absolute : string -> bool
(** Checks if the given path is absolute. *)


val to_quotes : string -> string
(* Surround a string with double quotes. *)


val has_elem : 'a list -> 'a -> bool
(** Checks if a list contains the given element. *)


val string_contains : string -> string -> bool
(** Checks if the first string contains the second one. *)


val int_stream : int -> int Stream.t 
(** This function initializes a stream of integers. *)


val (~+) : string -> StringSet.t
(** An prefix operator that creates a singleton set of strings. *)


val (~@) : StringSet.t -> string list
(** An prefix operator that converts a set of strings into a list of strings. *)


val (++) : string -> StringSet.t -> StringSet.t
(** An infix operator that adds a string into a set. *)


val (+-) : string -> StringSet.t -> StringSet.t
(** An infix operator that removes a string from a set. *)


val extract_arg: string -> int -> string


val extract_pathname: int -> string -> Syntax.path option
