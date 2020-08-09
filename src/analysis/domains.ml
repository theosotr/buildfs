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


open Util


exception DomainError of string


module RelSet = Set.Make(
  struct
    type t = Syntax.eff
    let compare = Core.compare
  end
)


type syscall_effect =
  | Create of string
  | Read of string
  | Remove of string
  | Touch of string
  | Write of string


type abstraction_effect =
  | Consumed of string
  | Modified of string
  | Produced of string
  | Expunged of string


type effect = (syscall_effect * Syntax.syscall_desc)


type addr_t = int


type process = string


type fd = string


type filename = string


type proc_store = (int * int) Strings.t


type proc_fd_store = filename option Strings.t


type fd_store = proc_fd_store Ints.t


type cwd_store = filename Ints.t


type symlink_store = filename Strings.t


type effect_cache = RelSet.t Strings.t


type effect_store = (effect list * effect_cache)


type task_block = string list


type parent_process = string option


type state = 
  {
   k:  proc_store;
   r:  fd_store;
   c:  effect_store;
   d:  cwd_store;
   s:  symlink_store;
   g:  int Stream.t;
   b:  task_block;
   o:  task_block;
   z:  parent_process;
   f:  Graph.graph;
   q:  StringSet.t;
   e:  string option;
  }


let cache_size = 1000


let gen_addr state =
  Stream.next state.g


(* Functions that perform queries to the structures of the state. *)
let find_from_cwdtable pid proc_table cwd_table =
  match Strings.find_opt pid proc_table with
  | None           -> None
  | Some (addr, _) -> Ints.find_opt addr cwd_table


let find_proc_fdtable pid proc_table fd_table =
  match Strings.find_opt pid proc_table with
  | None           -> None
  | Some (_, addr) -> Ints.find_opt addr fd_table


let find_from_fdtable pid fd proc_table fd_table =
  match Strings.find_opt pid proc_table with
  | None           -> None
  | Some (_, addr) -> Strings.find fd (Ints.find addr fd_table)


let find_from_symtable path sym_table =
  Strings.find_opt path sym_table


let find_from_proctable pid proc_table =
  Strings.find_opt pid proc_table


(* Functions that perform additions to the structures of the state. *)
let add_to_cwdtable pid inode proc_table cwd_table =
  match Strings.find_opt pid proc_table with
  | None           -> cwd_table
  | Some (addr, _) -> Ints.add addr inode cwd_table


let add_to_fdtable pid fd inode proc_table fd_table =
  match Strings.find_opt pid proc_table with
  | None           -> fd_table
  | Some (_, addr) ->
    match Ints.find_opt addr fd_table with
    | None   ->  Ints.add addr (Strings.singleton fd inode) fd_table
    | Some f ->  Ints.add addr (Strings.add fd inode f) fd_table


let add_to_symtable source target sym_table =
  Strings.add source target sym_table


let strip_trailing_slash path =
  let len = String.length path in
  if len > 0 && path.[len - 1] = '/'
  then String.sub path 0 (len - 1)
  else path


(* Functions that perform deletions to the structures of the state. *)
let remove_from_fdtable pid fd proc_table fd_table =
  match Strings.find_opt pid proc_table with
  | None           -> fd_table
  | Some (_, addr) -> Ints.add addr (
    Strings.remove fd (Ints.find addr fd_table)) fd_table


(* Removes a path that points to a particular inode.

  That path must be placed inside the directory given as an argument. *)
let remove_from_rev_it inode path rev_inode_table =
  match Ints.find_opt inode rev_inode_table with
  | None -> rev_inode_table
  | Some paths ->
    let paths = path +- paths in
    if StringSet.is_empty paths
    then 
      (* The inode is not pointed by any file, so we remove it. *)
      Ints.remove inode rev_inode_table
    else Ints.add inode paths rev_inode_table


let init_proc_fdtable addr fd_table =
  Ints.add addr Strings.empty fd_table


let init_proc_cwdtable addr cwd_table =
  Ints.add addr "/" cwd_table


let add_to_proctable pid cwd_addr fd_addr proc_table =
  Strings.add pid (cwd_addr, fd_addr) proc_table


let copy_cwdtable pid addr proc_table cwd_table =
  match Strings.find_opt pid proc_table with
  | None               -> cwd_table
  | Some (old_addr, _) ->
    Ints.add addr (Ints.find old_addr cwd_table) cwd_table


let copy_fdtable pid addr proc_table fd_table =
  match Strings.find_opt pid proc_table with
  | None               -> fd_table
  | Some (_, old_addr) -> Ints.add addr (Ints.find old_addr fd_table) fd_table


let copy_fd pid f1 f2 proc_table fd_table =
  add_to_fdtable pid f2 (find_from_fdtable pid f1 proc_table fd_table)
    proc_table fd_table


(* Functions that operate on the effect store. *)
let add_effect_to_cache cache x effect =
  match Strings.find_opt x cache with
  | None     -> Strings.add x (RelSet.add effect RelSet.empty) cache 
  | Some set when effect = Syntax.Expunge ->
    let set' = RelSet.empty in
    Strings.add x (RelSet.add effect set') cache
  | Some set -> Strings.add x (RelSet.add effect set) cache


let add_effect (lst, cache) (elem, sdesc) =
  match elem with
  | Create x ->
    (elem, sdesc) :: lst, add_effect_to_cache cache x Syntax.Prod
  | Read x | Touch x | Write x ->
    (elem, sdesc) :: lst, add_effect_to_cache cache x Syntax.Cons
  | Remove x ->
    (elem, sdesc) :: lst, add_effect_to_cache cache x Syntax.Expunge 


let init_proc_store () = Strings.empty


let init_fd_store () = Ints.empty


let init_cwd_store () = Ints.empty


let init_effect_store () = ([], Strings.empty)


let init_int_stream () =
  (* Initialize a stream of integers to be used as inodes.
     We start from 3 because 2 is alreasy reseved by the root
     directory. *)
  Util.int_stream 3


let reset_effect_store state =
  { state with c = init_effect_store () }


let init_symlink_store () = Strings.empty


let init_state () =
  {
    k = init_proc_store ();
    r = init_fd_store ();
    c = init_effect_store ();
    d = init_cwd_store ();
    s = init_symlink_store ();
    g = init_int_stream ();
    b = [];
    o = [];
    z = None;
    f = Graph.empty_graph ();
    q = StringSet.empty;
    e = None;
  }


let get_effects state =
  match state.c with
  | x, _ -> x


let strip_con x =
  match x with
  | Create v | Read v | Touch v | Remove v | Write v -> v


let unique_effects effects =
  (* Adds a cache that remembers paths that
     have been processed previously. *)
  let cache = Hashtbl.create cache_size in
  List.fold_left (fun acc (x, d) ->
    match x, Hashtbl.find_opt cache (strip_con x) with
    | _, None ->
      Hashtbl.add cache (strip_con x) (x, d);
      (x, d) :: acc
    | Create u, Some _ ->
      Hashtbl.replace cache u (Create u, d);
      (Create u, d) :: acc
    | Read _,  Some _
    | Touch _, Some _
    | (Write _, Some (Write _, _))
    | (Write _, Some (Create _, _)) -> acc
    | Write u, Some _ ->
      Hashtbl.replace cache u (Write u, d);
      (Write u, d) :: acc
    | Remove u, Some _ ->
      (* If we expunge the resource, all the previous
         effects on that resource have not meaning.
         So we remove them.

         Also, we remove all the resources which start with
         the name of the removed resource.

         This captures the case when we remove a directory.

         rmdir("/foo/bar")

         Apparently, in this case, we also need to remove all the
         resources included in that directory.
         *)
      Hashtbl.remove cache u;
      List.filter (fun (x, _) ->
        match x with
        | Create v | Read v | Touch v | Write v | Remove v ->
          not (Core.String.equal u v)) acc
  ) [] (List.rev effects)


(* Helper functions used during interpretation. *)
let get_cwd pid state =
  match find_from_cwdtable pid state.k state.d with
  (* Perphaps, it's the case when early take place
     and we don't have the information about the current working
     directory of the process. *)
  | None     -> "/CWD"
  | Some cwd -> cwd


let get_parent_dir pid state d =
  match d with
  (* It's not an *at call, so we get the current working directory. *)
  | Syntax.CWD                                    -> Some (get_cwd pid state)
  | Syntax.Fd "0" | Syntax.Fd "1" | Syntax.Fd "2" -> None
  | Syntax.Fd dirfd                               ->
    match find_from_fdtable pid dirfd state.k state.r with
    | Some p              -> Some p
    | None                -> None
    | exception Not_found -> None


(**
 * Extract and generate the absolute path name from the arguments
 * of system call.
 *
 * If the given path name is absolute, then this function returns it verbatim.
 * Otherwise, it extracts the dirfd argument:
   - If it is AT_FDCWD constant, then we interpret the given path name relative
     to the current working directory.
   - Otherwise, we inspect the directory corresponding to the given dirfd.
 *)
let get_pathname pid state d p =
  match p with
  | Syntax.Unknown _     -> Some p
  | Syntax.Path pathname ->
    if is_absolute pathname then Some p
    else
      match (
        pathname,
        get_parent_dir pid state d
      ) with
      | _, None -> None
      (* Get the current directory, e.g. /foo/. -> /foo *)
      | ".", Some cwd -> Some (Syntax.Path cwd)
      (* Get the parent directory, e.g. /foo/bar/.. -> /foo/bar *)
      | "..", Some cwd -> Some (Syntax.Path (Core.Filename.dirname cwd))
      (* Join paths, e.g. /foo/bar and /bar/x -> /foo/bar/bar/x *)
      | _, Some cwd -> Some (Syntax.Path (
        pathname
        |> Core.Filename.concat cwd
        |> Fpath.v
        |> Fpath.normalize
        |> Fpath.to_string))


let extract_task = function
  | Consumed v, _
  | Modified v, _
  | Produced v, _
  | Expunged v, _ -> v
