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


open Str


(** Implementation of a map using strings as keys *)
module Strings = Map.Make(String)
module Ints = Map.Make(struct type t = int let compare = Core.compare end)
module StringPair = Map.Make(
    struct
        type t = (string * string)
        let compare = Core.compare
    end
)
module StringSet = Set.Make(String)


let path_regex = "^\\(/[^/]*\\)+/?$"


let check_prefix (prefix : string) (str : string) =
    Core.String.is_prefix str ~prefix: prefix


let is_absolute pathname =
    string_match (regexp path_regex) pathname 0


let to_quotes str =
  Printf.sprintf "\"%s\"" str


let rec has_elem lst elem =
    match lst with
    | h :: t ->
        if h = elem then true
        else has_elem t elem
    | [] -> false


let string_contains s1 s2 =
    let re = regexp_string s2 in
    try
        let _ = search_forward re s1 0 in
        true
    with Not_found -> false


let int_stream i =
    Stream.from (fun j -> Some (i + j))


let (~+) x =
  StringSet.singleton x


let (~@) x =
  StringSet.elements x


let (++) x y =
  StringSet.add x y


let (+-) x y =
  StringSet.remove x y


let is_address x =
  check_prefix "0x" x


let is_null x =
  String.equal "NULL" x


let ignore_pathname pathname =
  is_null pathname


let extract_arg args index =
  List.nth (split (regexp ", ") args) index


let strip_quotes pathname =
  String.sub pathname 1 ((String.length pathname) - 2)


let dslash_regex = regexp "//"


let extract_pathname index args =
  let pathname_str = extract_arg args index in
  if ignore_pathname pathname_str
  then None (* We don't handle the case when the argument is an address,
         e.g. open(0x7f3bbdf504ff, O_RDONLY). *)
  else if is_address pathname_str
  then Some (Syntax.Unknown "/UNKNOWN")
  else Some (Syntax.Path (
    (* Revisit this for any performance issues. *)
    pathname_str
    |> strip_quotes
    |> Str.global_replace dslash_regex "/"
    |> Fpath.v
    |> Fpath.normalize
    |> Fpath.rem_empty_seg
    |> Fpath.to_string))
