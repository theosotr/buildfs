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


open Errors
open Util


let make_internal_error msg =
  raise (Error (InternalError, msg))


type node = string


type edge_label =
  | Contain
  | Before
  | Include
  | In
  | In_task
  | Out


type graph_format =
  | Dot
  | Csv


module EdgeSet = Set.Make(
  struct
    type t = (string * edge_label)
    let compare = Core.compare
  end
)


module LabelSet = Set.Make(
  struct
    type t = edge_label
    let compare = Core.compare
  end
)


type edge_t = EdgeSet.t


type graph_scan = string list list


type graph = EdgeSet.t Strings.t


let empty_graph () =
  Strings.empty


let add_node node graph =
  match Strings.find_opt node graph with
  | None -> Strings.add node EdgeSet.empty graph
  | _    -> graph


let add_edge source target label graph =
  if String.equal source target
  then graph
  else
    (* Adds target node if it does not exist. *)
    let graph = add_node target graph in
    match Strings.find_opt source graph, label with
    | Some edges, _ ->
      Strings.add source (EdgeSet.add (target, label) edges) graph
    | None, _ ->
      Strings.add source (EdgeSet.singleton (target, label)) graph


let get_edges graph node =
  match Strings.find_opt node graph with
  | None       -> None
  | Some edges ->
    if EdgeSet.is_empty edges
    then None
    else Some edges


let exist_edges f edges =
  EdgeSet.exists f edges


let fold_edges f edges acc =
  EdgeSet.fold f edges acc


let string_of_label = function
  | Contain -> "contain"
  | Before  -> "before"
  | Include -> "include"
  | Out     -> "out"
  | In | In_task -> "in"


let save_to_file file str =
  begin
    let out = open_out file in
    output_string out str;
    close_out out;
  end


let to_dot graph file =
  let regex = Str.regexp "\"" in
  let add_brace str =
    str ^ "}"
  in
  "digraph {"
  |> Strings.fold (fun source edges acc ->
    EdgeSet.fold (fun (target, label) acc' ->
      String.concat "" [
        acc';
        to_quotes (Str.global_replace regex "\\\"" source);
        " -> ";
        to_quotes (Str.global_replace regex "\\\"" target);
        "[label=";
        string_of_label label;
        "];\n"
      ]
    ) edges (acc ^ ((to_quotes (Str.global_replace regex "\\\"" source)) ^ ";\n"))
  ) graph
  |> add_brace
  |> save_to_file file


let to_csv graph file =
  ""
  |> Strings.fold (fun source edges acc ->
    EdgeSet.fold (fun (target, label) acc' ->
      String.concat "" [
        acc';
        source;
        ",";
        target;
        ",";
        string_of_label label;
        "\n";
      ]
    ) edges acc) graph
  |> save_to_file file


let reachable ?(labels=[Contain]) graph source =
  let rec _dfs visited stack =
    match stack with
    | []            -> visited
    | node :: stack ->
      match Strings.find_opt node graph with
      | None       -> _dfs visited stack
      | Some edges ->
        match StringSet.find_opt node visited with
        | None ->
          edges
            |> EdgeSet.elements
            |> List.filter (fun (_, label) -> List.exists (fun x -> x = label) labels)
            |> List.fold_left (fun acc (node, _) -> node :: acc) stack
            |> _dfs (node ++ visited)
        | Some _ -> _dfs visited stack
  in
  _dfs StringSet.empty [source]


(* A generic function that implements a DFS algorith.

 The output of this function is the list of paths from

 If the parameter `enum_paths` is None, the algorithm becomes `lightweight`
 and simply returns a single path.

 The function is tail-recursive.
*)
let dfs_generic graph source target enum_paths =
  let rec _dfs paths visited stack =
    match stack with
    | [] -> paths
    | (node, prev) :: stack ->
      let path = node :: prev in
      if node = target
      then
        (* If `enum_paths` is true, we need to find all
           paths that reach target. *)
        if enum_paths
        then _dfs (path :: paths) visited stack
        else path :: paths
      else
        let edges = Strings.find node graph in
        match StringSet.mem node visited with
        | false ->
          edges
            |> EdgeSet.elements
            |> List.fold_left (fun acc (node, _) -> (node, path) :: acc) stack
            |> _dfs paths (node ++ visited)
        | true ->
          if enum_paths
          then
            (* If `enum_paths` is true, we need to revisit nodes
               in order to compute new paths. *)
            edges
              |> EdgeSet.elements
              |> List.filter (fun (_, x) -> not (x = Include) && not (x = Before))
              |> List.fold_left (fun acc (node, _) ->
                if Util.has_elem acc (node, path)
                then acc
                else (node, path) :: acc
              ) stack
              |> _dfs paths visited
          else _dfs paths visited stack
  in
  _dfs [] StringSet.empty [(source, [])]


let dfs graph source target enum_paths =
  try
    let paths = dfs_generic graph source target enum_paths in
    Some paths
  with Not_found -> None


let exists graph abstraction =
  Strings.mem abstraction graph


let compute_dfs_out graph dfs_out source target enum_paths =
  match dfs_out with
  | None         -> dfs graph source target enum_paths
  | dfs_out      -> dfs_out


let happens_before graph source target dfs_out =
  match compute_dfs_out graph dfs_out source target false with
  | None    -> true
  (* There is not any path from the source to the target*)
  | Some [] -> false
  | _       -> true


let is_contain x =
  x = Contain


(* A helper function that converts a list to a list of pairs as follows:

  [1, 2, 3, 4] -> [(1, 2), (2, 3), (3, 4)]. *)
let to_pairs path =
  let rec _to_pairs acc path =
    match path with
    | []
    | [_]           -> acc
    | x :: (y :: t) ->
      let acc' = (y, x) :: acc in
      _to_pairs acc' (y :: t)
  in
  _to_pairs [] path


let is_path f graph path =
  let edges = to_pairs path in
  List.for_all (fun (x, y) ->
    match Strings.find_opt x graph with
    | None       -> make_internal_error (Some ("Unreachable case."))
    | Some edges ->
      EdgeSet.exists (fun (node, label) -> f node label y) edges
  ) edges
