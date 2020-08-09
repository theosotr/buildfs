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
open Domains
open Util
open Syntax


let add_dir_when_mkdir sdesc pathname q =
  match sdesc with
  | { syscall = "mkdir"; _ } -> pathname ++ q
  | _                        -> q


let get_target_pathname state pathname =
  match Domains.find_from_symtable pathname state.s with
  | None -> pathname
  | Some target -> target


let handle_path_effect pathname effect state sdesc =
  let state = { state with q = (Core.Filename.dirname pathname) ++ state.q } in
  let update_state =
    match state.o with
    (* The operation is done outside an execution block. *)
    | [] -> fun state _ -> state
    | _  -> fun state x -> { state with c = Domains.add_effect state.c x }
  in
    match effect with
    | Syntax.Cons ->
      let pathname = get_target_pathname state pathname in
      update_state state (Touch pathname, sdesc)
    | Syntax.Prod ->
      let state' = update_state state (Create pathname, sdesc) in
      { state' with
        (* They system call 'mkdir' operates on a directory. *)
        q = add_dir_when_mkdir sdesc pathname state'.q }
    | Syntax.Expunge ->
      update_state state (Remove pathname, sdesc)


let eval_expr pid state e =
  match e with
  | Syntax.P p       -> Some p
  | Syntax.At (v, p) -> Domains.get_pathname pid state v p
  | Syntax.V v       ->
    match Domains.get_parent_dir pid state v with
    | None   -> None
    | Some p -> Some (Syntax.Path p)


let copy_fd pid state f1 f2 =
  try
    { state with r = Domains.copy_fd pid f1 f2 state.k state.r }
  with Not_found -> state


let chcwd pid state p =
  match Domains.get_pathname pid state Syntax.CWD p with
  | None                                 -> state
  | Some (Path cwd) | Some (Unknown cwd) ->
    { state with d = Domains.add_to_cwdtable pid cwd state.k state.d; }


let interpret_let pid state v e =
  match (v, e) with
  | (Syntax.Fd f1, Syntax.V (Fd f2)) -> copy_fd pid state f1 f2
  | (Syntax.CWD, Syntax.P p)         -> chcwd pid state p
  | _ ->
    match eval_expr pid state e with
    | None | Some (Syntax.Unknown _) -> state
    | Some (Syntax.Path p) ->
      match v with
      | Syntax.CWD  -> chcwd pid state (Syntax.Path p)
      | Syntax.Fd f ->
        let dir = Core.Filename.dirname p in
        { state with
          r = Domains.add_to_fdtable pid f (Some p) state.k state.r;
          q = dir ++ state.q; (* This is for tracking directories. *)
        }


let del_fd pid state fd =
  try
    { state with r = Domains.remove_from_fdtable pid fd state.k state.r }
  with Not_found -> state


let interpret_del pid state sdesc e =
  match e with
  | Syntax.V (Syntax.Fd f) -> del_fd pid state f
  | Syntax.V Syntax.CWD    -> state
  | _ ->
    match eval_expr pid state e with
    | None | Some (Syntax.Unknown _) -> state
    | Some (Syntax.Path p) -> handle_path_effect p Syntax.Expunge state sdesc


let interpret_consume pid state sdesc e =
  match eval_expr pid state e with
  | None | Some (Syntax.Unknown _) -> state
  | Some (Syntax.Path p) -> handle_path_effect p Syntax.Cons state sdesc


let interpret_produce pid state sdesc e =
  match eval_expr pid state e with
  | None | Some (Syntax.Unknown _) -> state
  | Some (Syntax.Path p) ->
    match sdesc.syscall with
    | "symlink" | "symlinkat" -> (
      match Util.extract_pathname 0 sdesc.args with
      | None | Some (Syntax.Unknown _) ->
        handle_path_effect p Syntax.Prod state sdesc
      | Some (Syntax.Path link) ->
        let state = handle_path_effect p Syntax.Prod state sdesc in
        { state with s = Domains.add_to_symtable p link state.s })
    | _ -> handle_path_effect p Syntax.Prod state sdesc


let process_clone_none pid new_pid state =
  let addr = Domains.gen_addr state in
  let k' = Domains.add_to_proctable new_pid addr addr state.k in
  (* Get the working directory of the parent process
     and use the same for the child process. *)
  { state with k = k';
               d = Domains.copy_cwdtable pid addr k' state.d;
               r = Domains.copy_fdtable pid addr k' state.r;}


let interpret_newproc pid state f =
  try
    process_clone_none pid f state
  with Not_found ->
    let addr = Domains.gen_addr state in
    { state with k = Domains.add_to_proctable f addr addr state.k }


let interpret_input _ state t p =
  { state with f = Graph.add_edge t p Graph.In state.f }


let interpret_dependson _ state t1 t2 =
  { state with f = Graph.add_edge t2 t1 Graph.Before state.f }


let interpret_output _ state t p =
  { state with f = Graph.add_edge t p Graph.Out state.f }


let interpret_begin pid state _ b =
  match state.b, state.e with
  (* FIXME: Handle it in a better way. *)
  | [], _         -> { state with b = b::state.b; z = Some pid; o = [b]; }
  | b' :: l, None ->
    {state with
     b = b :: (b' :: l);
     o = b :: state.o;
     z = Some pid;
     f = state.f
       |> Graph.add_edge b b' Graph.Contain
       |> Graph.add_edge b' b Graph.Before;
     }
  | b' :: l, Some e ->
    (* Nested blocks are executed in a FIFO order. *)
    {state with
     b = b :: (b' :: l);
     o = b :: state.o;
     z = Some pid;
     f = state.f
       |> Graph.add_edge b b' Graph.Contain
       |> Graph.add_edge e b Graph.Before
       |> Graph.add_edge b' b Graph.Before;
     }


let interpret_end _ state _ _ =
  match state.b with
  | []     -> state
  | t :: b -> { state with b = b; o = []; e = Some t; }


let interpret (pid, (statement, sdesc)) state =
  match sdesc with
  (* We do not handle system calls that failed. *)
  | {err = Some _; _ } -> state
  | _ ->
    let state =
      match sdesc.line with
      | 1 ->
          let addr = gen_addr state in
          { state with k = Domains.add_to_proctable pid addr addr state.k;
                       d = Domains.init_proc_cwdtable addr state.d;
                       r = Domains.init_proc_fdtable addr state.r;
          }
      | _ -> state
    in
    try
      match statement with
      | Let (v, e)              -> interpret_let pid state v e
      | Del e                   -> interpret_del pid state sdesc e
      | Consume e               -> interpret_consume pid state sdesc e
      | Produce e               -> interpret_produce pid state sdesc e
      | Input (t, p)            -> interpret_input pid state t p
      | Output (t, p)           -> interpret_output pid state t p
      | DependsOn (t1, t2)      -> interpret_dependson pid state t1 t2
      | Newproc f               -> interpret_newproc pid state f
      | Begin_task t            -> interpret_begin pid state sdesc t
      | End_task t              -> interpret_end pid state sdesc t
      | Nop                     -> state (* Nop  does not affect the state. *)
    with
    | DomainError msg ->
      let msg = String.concat "" [
        msg;
        "on ";
        "model: ";
        Syntax.string_of_trace (statement, sdesc);
      ] in
      let err = (InterpretationError sdesc) in
      raise (Error (err, Some msg))
