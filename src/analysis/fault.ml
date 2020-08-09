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


open Domains
open Syntax


type fault_kind =
  | Facc of Analyzer.file_acc_t
  | Conflict of (Analyzer.file_acc_t * Analyzer.file_acc_t)


type fault_t =
  {name: string;
   desc: string;
   resource: string;
   kind: fault_kind;
  }


module StrPair = Map.Make(
  struct
    type t = string * string
    let compare = Core.compare
  end    
)


type fault_collection =
  {conflicts: fault_t list StrPair.t;
   other: fault_t list Util.Strings.t;}


let empty_faults () =
  {other = Util.Strings.empty;
   conflicts = StrPair.empty;
  }


let construct_fault name desc resource file_acc =
  {name = name;
   desc = desc;
   resource = resource;
   kind = Facc file_acc;
  }


let construct_conflict_fault name desc resource conflict =
  {name = name;
   desc = desc;
   resource = resource;
   kind = Conflict conflict;
  }


let add_fault fault_name fault_desc resource file_acc faults =
  let t = extract_task file_acc in
  let fault = construct_fault fault_name fault_desc resource file_acc in
  match Util.Strings.find_opt t faults.other with
  | None       ->
    { faults with other = Util.Strings.add t [fault] faults.other }
  | Some flist ->
    { faults with other = Util.Strings.add t (fault :: flist) faults.other }


let add_conflict_fault fault_name fault_desc resource (facc1, facc2) faults =
  let t1, t2 = extract_task facc1, extract_task facc2 in
  let fault =
    (facc1, facc2)
    |> construct_conflict_fault fault_name fault_desc resource
  in
  match
    StrPair.find_opt (t1, t2) faults.conflicts,
    StrPair.find_opt (t2, t1) faults.conflicts
  with
  | None, None   ->
    { faults with conflicts = StrPair.add (t1, t2) [fault] faults.conflicts }
  | Some f, None ->
    { faults with conflicts = StrPair.add (t1, t2) (fault :: f) faults.conflicts }
  | None, Some f ->
    { faults with conflicts = StrPair.add (t2, t1) (fault :: f) faults.conflicts }
  | _ -> faults


let task_print_format task_name =
  [
    "[Task: ";
    task_name;
    "]"
  ]
  |> String.concat ""


let task_print_details tinfo task_name =
  match Task_info.get_task_desc task_name tinfo with
  | None       -> ""
  | Some tdesc -> Task_info.string_of_task_desc tdesc ^ "\n"


let string_of_file_acc x =
  let msg, sdesc = (
    match x with
    | Consumed x, d -> "Consumed by " ^ x, d
    | Modified x, d -> "Modified by " ^ x, d
    | Produced x, d -> "Produced by " ^ x, d
    | Expunged x, d -> "Expunged by " ^ x, d
  ) in
  String.concat " " [
    msg;
    "(";
    sdesc.syscall;
    "at line";
    (string_of_int sdesc.line);
    ")";
  ]


let string_of_faults faults =
  List.fold_left (fun str {kind = kind; resource = resource; _; } ->
    match kind with
    | Conflict (x, y) ->
      String.concat "" [
        str;
        "      - ";
        resource;
        ": ";
        string_of_file_acc x;
        " and ";
        string_of_file_acc y;
        "\n";
      ]
    | Facc x -> 
      String.concat "" [
        str;
        "      - ";
        resource;
        ": ";
        string_of_file_acc x;
        "\n";
      ]
  ) "" faults


let group_task_faults task_faults =
  (* Groups faults by their kind (aka name). *)
  List.fold_left (fun acc fault ->
    match Util.Strings.find_opt fault.name acc with
    | None        -> Util.Strings.add fault.name [fault] acc
    | Some faults -> Util.Strings.add fault.name (fault :: faults) acc
  ) Util.Strings.empty task_faults


let report_fault_2 tinfo faults =
  Util.Strings.iter (fun task task_faults ->
    [
      "  \x1b[0;31m==> ";
      (task_print_format task);
      "\n";
      "    \x1b[0;36m";
      (task_print_details tinfo task);
      "\x1b[0m";
    ]
    |> String.concat ""
    |> print_endline;
    let grouped_faults = group_task_faults task_faults in
    Util.Strings.iter (fun fault_name task_faults ->
      print_endline ( "    Fault Type: " ^ fault_name);
      print_endline (string_of_faults task_faults)
    ) grouped_faults
  ) faults.other


let report_fault_details tinfo faults =
  StrPair.iter (fun (t1, t2) task_faults ->
    [
      "  \x1b[0;31m==> ";
      (task_print_format t1);
      " | ";
      (task_print_format t2);
      "\n";
      "    \x1b[0;36m";
      (task_print_details tinfo t1);
      "    ";
      (task_print_details tinfo t2);
      "\x1b[0m";
    ]
    |> String.concat ""
    |> print_endline;
    let grouped_faults = group_task_faults task_faults in
    Util.Strings.iter (fun fault_name task_faults ->
      print_endline ( "    Fault Type: " ^ fault_name);
      print_endline (string_of_faults task_faults)
    ) grouped_faults
  ) faults.conflicts


let compute_fault_occ acc faults =
  List.fold_left (fun occ fault_name ->
    match Util.Strings.find_opt fault_name occ with
    | None   -> Util.Strings.add fault_name 1 occ
    | Some i -> Util.Strings.add fault_name (i + 1) occ
  ) acc faults


let get_occ_conflict_faults faults =
  StrPair.fold (fun _ task_faults acc ->
    task_faults
    |> List.map (fun { name = f; desc = d; _ } ->
      [d; "s"; " ("; f; ")"] |> String.concat "")
    |> Util.StringSet.of_list
    |> Util.StringSet.elements
    |> compute_fault_occ acc) faults Util.Strings.empty


let get_occ_faults faults =
  Util.Strings.fold (fun _ task_faults acc ->
    task_faults
    |> List.map (fun { name = f; desc = d; _ } ->
      [d; "s"; " ("; f; ")"] |> String.concat "")
    |> Util.StringSet.of_list
    |> Util.StringSet.elements
    |> compute_fault_occ acc) faults Util.Strings.empty


let print_occ_faults fault_occ =
  Util.Strings.iter (fun fault_name occ ->
    [
      "Number of ";
      fault_name;
      ": ";
      (string_of_int occ);
    ]
    |> String.concat ""
    |> print_endline
  ) fault_occ


let report_faults tinf faults =
  print_endline "------------------------------------------------------------";
  if StrPair.cardinal faults.conflicts <> 0 ||
    (Util.Strings.cardinal faults.other <> 0)
  then
    begin
      faults.other
      |> get_occ_faults
      |> print_occ_faults;
      faults.conflicts
      |> get_occ_conflict_faults
      |> print_occ_faults;
      print_endline "\nDetailed Bug Report:";
      report_fault_2 tinf faults;
      report_fault_details tinf faults;
    end
  else print_endline "No faults found..."
