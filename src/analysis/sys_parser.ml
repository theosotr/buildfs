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

open Errors
open Syntax



(* Some helper functions to raise Parser errors. *)
let make_error error_kind msg =
  raise (Error (error_kind, msg))


let make_parser_error syscall line msg =
  make_error (ParserError (syscall, line)) msg


module type ToolParserType =
  sig
  val is_tool_debug_msg : string -> bool

  val model_syscall : string -> Syntax.statement

  val stop_parser : string -> bool
  end


module type S =
  sig
    val parse_trace_fd :
      string option
      -> Unix.file_descr
      -> Syntax.trace Syntax.stream

    val parse_trace_file : string option -> string -> Syntax.trace Syntax.stream
  end


module Make (T : ToolParserType) = struct

  type syscall_type =
    | Completed
    | Unfinished
    | Resumed

  type syscall_l =
    | CoSyscall of (string * string * string option * string option)
    | UnSyscall of (string * string)
    | ResSyscall of (string * string * string option * string option)


  let regex_pid = regexp "^[0-9]+[ ]+"

  (* Regex for system calls *)
  let ret_value_pattern = "\\([ ]*=[ ]*\\(-?[0-9\\?]+\\)[ ]*\\(.*\\)?\\)?"
  let regex_syscall = regexp ("\\([a-z0-9_]+\\)(\\(.*\\))" ^ ret_value_pattern)
  let regex_syscall_unfin = regexp "\\([a-z0-9_?]+\\)(\\(.*\\)[ ]+<unfinished ...>"
  let regex_syscall_resum = regexp ("<...[ ]+\\([a-z0-9_?]+\\)[ ]+resumed>[ ]*\\(.*\\))" ^ ret_value_pattern)

  let syscall_group = 1
  let args_group = 2
  let ret_group = 3
  let retv_group = 4
  let err_msg_group = 5


  let has_dupfd args =
    Util.string_contains args "F_DUPFD"


  let has_rdonly args =
    Util.string_contains args "O_RDONLY"


  let has_wronly args =
    Util.string_contains args "O_WRONLY"


  let has_rdwrd args =
    Util.string_contains args "O_RDWR"


  let has_trunc args =
    Util.string_contains args "O_TRUNC"


  let has_creat args =
    Util.string_contains args "O_CREAT"


  let has_clone_fs args =
    Util.string_contains args "CLONE_FS"


  let has_clone_files args =
    Util.string_contains args "CLONE_FILES"


  let to_path_expr p_index args =
    match Util.extract_pathname p_index args with
    | None   -> None
    | Some p -> Some (Syntax.P p)


  let to_fdvar fd =
    match fd with
    (* When fd is None or AT_FDCWD, then we model the working directory of
       the process. *)
    | None
    | Some "AT_FDCWD" -> Syntax.CWD
    | Some f          -> Syntax.Fd f


  let to_fdvar_expr fd =
    Syntax.V (to_fdvar fd)


  let to_at_expr fd p_index args =
    match Util.extract_pathname p_index args with
    | None   -> None
    | Some p -> Some (Syntax.At (to_fdvar fd, p))


  let is_open_consumed args =
    match (
      has_rdonly args,
      has_wronly args,
      has_rdwrd  args,
      has_trunc  args,
      has_creat  args)
    with
    | true, _, _, _, _         -> true (* O_RDONLY *)
    | _, true, _, true, _      -> false  (* O_WRONLY|O_TRUNC *)
    | _, _, true, false, false -> true  (* O_RDWRD *)
    | _, _, true, _, true      -> false  (* O_RDWRD|O_CREAT *)
    | _, true, _, _, true      -> false  (* O_WRONLY|O_CREAT *)
    | _, true, _, false, false -> true  (* O_WRONLY *)
    | _                        -> true


  let get_fd index args =
    match index with
    | None   -> None
    | Some i -> Some (Util.extract_arg args i)


  (* Functions to model system calls in BuildFS. *)
  let to_nop _ =
    Syntax.Nop


  let to_chdir sdesc =
    match to_path_expr 0 sdesc.args with
    | None   -> Syntax.Nop
    | Some e -> Syntax.Let (Syntax.CWD, e)


  let to_newproc sdesc =
    Syntax.Newproc sdesc.ret


  let to_delfd sdesc =
    Syntax.Del (to_fdvar_expr (Some sdesc.args))


  let to_dupfd_fcntl sdesc =
    if has_dupfd sdesc.args
    then
      Syntax.Let (
        to_fdvar (Some (Util.extract_arg sdesc.args 0)),
        to_fdvar_expr (Some sdesc.ret)
      )
    else Syntax.Nop


  let to_dupfd_dup sdesc =
    Syntax.Let(
      to_fdvar (Some (Util.extract_arg sdesc.args 0)),
      to_fdvar_expr (Some sdesc.ret)
    )


  let to_dupfd_dup2 sdesc =
    Syntax.Let(
      to_fdvar (Some (Util.extract_arg sdesc.args 0)),
      to_fdvar_expr (Some (Util.extract_arg sdesc.args 1))
    )


  let to_fchdir sdesc =
    Syntax.Let (
      Syntax.CWD,
      to_fdvar_expr (Some (Util.extract_arg sdesc.args 0))
    )


  let to_consume d_index p_index sdesc =
    let fd = get_fd d_index sdesc.args in
    match to_at_expr fd p_index sdesc.args with
    | None   -> Syntax.Nop
    | Some e -> Syntax.Consume e


  let to_produce d_index p_index sdesc =
    let fd = get_fd d_index sdesc.args in
    match to_at_expr fd p_index sdesc.args with
    | None   -> Syntax.Nop
    | Some e -> Syntax.Produce e


  let to_del_path d_index p_index sdesc =
    let fd = get_fd d_index sdesc.args in
    match to_at_expr fd p_index sdesc.args with
    | None   -> Syntax.Nop
    | Some e -> Syntax.Del e


  let model_open d_index p_index sdesc =
    let fd = get_fd d_index sdesc.args in
    match to_at_expr fd p_index sdesc.args with
    | None   -> Syntax.Nop
    | Some e ->
      if is_open_consumed sdesc.args
      then Syntax.Consume e
      else Syntax.Produce e


  let to_newfd d_index p_index sdesc =
    let fd = get_fd d_index sdesc.args in
    match to_at_expr fd p_index sdesc.args with
    | None   -> Syntax.Nop
    | Some e -> Syntax.Let (to_fdvar (Some sdesc.ret), e)


  let parsers = Util.Strings.empty
    |> Util.Strings.add "access"      [(to_consume None 0)]
    |> Util.Strings.add "chdir"       [to_chdir]
    |> Util.Strings.add "chmod"       [(to_consume None 0)]
    |> Util.Strings.add "chown"       [(to_consume None 0)]
    |> Util.Strings.add "clone"       [to_newproc]
    |> Util.Strings.add "close"       [to_delfd]
    |> Util.Strings.add "dup"         [to_dupfd_dup]
    |> Util.Strings.add "dup2"        [to_dupfd_dup2]
    |> Util.Strings.add "dup3"        [to_dupfd_dup2]
    |> Util.Strings.add "execve"      [(to_consume None 0)]
    |> Util.Strings.add "fchdir"      [to_fchdir]
    |> Util.Strings.add "fchmodat"    [(to_consume (Some 0) 1)]
    |> Util.Strings.add "fchownat"    [(to_consume (Some 0) 1)]
    |> Util.Strings.add "fcntl"       [to_dupfd_fcntl]
    |> Util.Strings.add "fork"        [to_newproc]
    |> Util.Strings.add "getxattr"    [(to_consume None 0)]
    |> Util.Strings.add "getcwd"      [to_chdir]
    |> Util.Strings.add "lchown"      [(to_consume None 0)]
    |> Util.Strings.add "lgetxattr"   [(to_consume None 0)]
    |> Util.Strings.add "lremovexattr"[(to_consume None 0)]
    |> Util.Strings.add "lsetxattr"   [(to_consume None 0)]
    |> Util.Strings.add "lstat"       [(to_consume None 0)]
    |> Util.Strings.add "link"        [
                                        (to_produce None 1);
                                        (to_consume None 0);
                                      ]
    |> Util.Strings.add "linkat"      [
                                        (to_produce (Some 2) 3);
                                        (to_consume (Some 0) 1);
                                      ]
    |> Util.Strings.add "mkdir"       [(to_produce None 0)]
    |> Util.Strings.add "mkdirat"     [(to_produce (Some 0) 1)]
    |> Util.Strings.add "mknod"       [(to_produce None 0)]
    |> Util.Strings.add "open"        [
                                        (to_newfd None 0);
                                        (model_open None 0);
                                      ]
    |> Util.Strings.add "openat"      [
                                        (to_newfd (Some 0) 1);
                                        (model_open (Some 0) 1);
                                      ]
    |> Util.Strings.add "pread"       [to_nop]
    |> Util.Strings.add "pwrite"      [to_nop]
    |> Util.Strings.add "read"        [to_nop]
    |> Util.Strings.add "readlink"    [(to_consume None 0)]
    |> Util.Strings.add "readlinkat"  [(to_consume (Some 0) 1)]
    |> Util.Strings.add "removexattr" [(to_consume None 0)]
    |> Util.Strings.add "rename"      [
                                        (to_del_path None 0);
                                        (to_produce None 1);
                                      ]
    |> Util.Strings.add "renameat"    [
                                        (to_del_path (Some 0) 1);
                                        (to_produce (Some 2) 3);
                                      ]
    |> Util.Strings.add "rmdir"       [(to_del_path None 0)]
    |> Util.Strings.add "symlink"     [
                                        (to_produce None 1);
                                      ]
    |> Util.Strings.add "symlinkat"   [
                                        (to_produce (Some 1) 2);
                                      ]
    |> Util.Strings.add "unlink"      [(to_del_path None 0)]
    |> Util.Strings.add "unlinkat"    [(to_del_path (Some 0) 1)]
    |> Util.Strings.add "utime"       [(to_consume None 0)]
    |> Util.Strings.add "utimensat"   [(to_consume (Some 0) 1)]
    |> Util.Strings.add "utimes"      [(to_consume None 0)]
    |> Util.Strings.add "vfork"       [to_newproc]
    |> Util.Strings.add "write"       [to_nop]
    |> Util.Strings.add "writev"      [to_nop]


  let should_ignore trace_line =
    Util.check_prefix "+++" trace_line


  let is_signal trace_line =
    Util.check_prefix "---" trace_line


  let is_resumed syscall_line =
    Util.check_prefix "<.." syscall_line


  let is_unfinished syscall_line =
    let str_len = String.length syscall_line in
    String.equal (String.sub syscall_line (str_len - 1) 1) ">"


  let get_syscall_type syscall_line =
    if is_resumed syscall_line
    then Resumed
    else if is_unfinished syscall_line
    then Unfinished
    else Completed


  let get_regex syscall_type =
    match syscall_type with
    | Completed -> regex_syscall
    | Resumed -> regex_syscall_resum
    | Unfinished -> regex_syscall_unfin


  let extract_syscall_name syscall_line =
    matched_group syscall_group syscall_line


  let extract_args syscall_line =
    matched_group args_group syscall_line


  let extract_ret_value ret =
    matched_group retv_group ret


  let get_err_msg syscall_line =
    match matched_group err_msg_group syscall_line with
    | "" -> None
    | v  -> Some v


  let extract_ret syscall_line =
    try
      match matched_group ret_group syscall_line with
      | "" -> None
      | _ -> Some (extract_ret_value syscall_line, get_err_msg syscall_line)
    with Not_found -> None


  let extract_syscall_desc syscall_line =
    match extract_ret syscall_line with
    | None ->
      extract_syscall_name syscall_line,
      extract_args syscall_line,
      None,
      None
    | Some (ret, err) ->
      extract_syscall_name syscall_line,
      extract_args syscall_line,
      Some ret,
      err


  let get_syscall_extractor syscall_type =
    fun syscall_line ->
      match syscall_type with
      | Completed ->
        Some ( CoSyscall (extract_syscall_desc syscall_line))
      | Unfinished ->
        Some ( UnSyscall (
          matched_group syscall_group syscall_line,
          matched_group args_group syscall_line))
      | Resumed ->
        Some ( ResSyscall (extract_syscall_desc syscall_line))


  let _parse_trace regex extract_value trace_line i =
    if should_ignore trace_line
    then None
    else
      if string_match regex trace_line 0
      then
        try extract_value trace_line
        with Invalid_argument _ ->
          make_parser_error trace_line i None
      else
          make_parser_error trace_line i None


  (* This function constructs a syscall given a description of a system call.
     Note that we need to identify if a system call stem from debug messages of the tool
     because we need to extract the name of the resource. *)
  let construct_syscall sdesc =
    let syscall_line = string_of_syscall sdesc in
    if T.is_tool_debug_msg syscall_line
    then [T.model_syscall syscall_line], sdesc
    else
      match Util.Strings.find_opt sdesc.syscall parsers with
      | Some parser_funs -> (List.fold_left (fun traces parser_fun -> (parser_fun sdesc) :: traces) [] parser_funs), sdesc
      | None            -> [Syntax.Nop], sdesc


  let parse_syscall syscall_line (pid, map) i =
    let syscall_type = get_syscall_type syscall_line in
    match _parse_trace
      (get_regex syscall_type)
      (get_syscall_extractor syscall_type)
      syscall_line 
      i
    with
    | Some (UnSyscall (v1, v2)) ->
      None, Util.StringPair.add (pid, v1) v2 map
    | Some (ResSyscall (v1, v2, Some v3, v4)) -> (
      try
        let args = Util.StringPair.find (pid, v1) map in
        let sdesc = {
          syscall = v1;
          args = (
            match args, v2 with
            | _, ""      -> args
            | "", v      -> v
            | arg1, arg2 -> arg1 ^ " " ^ arg2
          );
          ret = v3;
          err = v4;
          line = i;
        } in
        Some (construct_syscall sdesc),
        Util.StringPair.remove (pid, v1) map
      with Not_found -> None, map)
    | Some (CoSyscall (v1, v2, Some v3, v4)) ->
      Some (construct_syscall {
        syscall = v1;
        args = v2;
        ret = v3;
        err = v4;
        line = i;
      }),
      map
    | None
    | Some (ResSyscall (_, _, None, _))
    | Some (CoSyscall (_, _, None, _)) -> None, map


  let parse_trace trace_line (pid, map) i =
    if should_ignore trace_line
    then None, map
    else
      if is_signal trace_line
      then None, map (* We do not handle signals. *)
      else parse_syscall trace_line (pid, map) i


  let parse_traces line map i =
    try
      match full_split regex_pid line with
      | Delim pid :: Text trace_line :: [] -> (
        let pid = String.trim pid in
        match parse_trace trace_line (pid, map) i with 
        | None, map                 -> None, map
        | Some (traces, sdesc), map ->
          Some (List.map(fun trace -> (pid, (trace, sdesc))) traces), map)
      | _  -> make_parser_error line i None
    with _ -> make_parser_error line i None


  let write_trace_line out line =
    match out with
    | None     -> ()
    | Some out -> Printf.fprintf out "%s\n" line

  let close_trace_out out =
    match out with
    | None     -> ()
    | Some out -> close_out out

  let parse_lines lines debug_trace_file =
    (* i is just a counter of the current stream.
       Also it indicates the number of the line
       where every trace is located. *)
    let trace_out =
      match debug_trace_file with
      | Some trace_file -> Some (open_out trace_file)
      | None            -> None
    in
    let rec _next_trace traces m i () =
      match traces with
      | []               -> (
        match input_line lines with
        | line ->
          write_trace_line trace_out line;
          if T.stop_parser line
          then
            begin
              (* We don't need to analyze more traces *)
              close_in lines;
              close_trace_out trace_out;
              Stream (dummy_statement (Syntax.End_task "") i, fun () -> Empty)
          end
          else (
            match parse_traces line m i with
            | Some traces, map' -> _next_trace traces map' (i + 1) ()
            (* If None, we just ignore that trace,
               and we recursively search for another. *)
            | None, map'        -> _next_trace [] map' (i + 1) ())
        | exception End_of_file ->
          close_in lines;
          close_trace_out trace_out;
          Empty
        | exception Error v ->
          close_in lines;
          close_trace_out trace_out;
          raise (Error v)
        | exception v ->
          close_in lines;
          close_trace_out trace_out;
          let msg = Printexc.to_string v in
          raise (Error (InternalError, Some msg)))
      | trace :: traces' ->
        Stream (trace, _next_trace traces' m i)
    in _next_trace [] Util.StringPair.empty 1 ()


  let parse_trace_fd debug_trace_file fd =
    match parse_lines (Unix.in_channel_of_descr fd) debug_trace_file with
    | traces                  -> traces
    | exception Sys_error msg -> raise (Error (GenericError, Some msg))


  let parse_trace_file debug_trace_file filename =
    match parse_lines (open_in filename) debug_trace_file with
    | traces                  -> traces
    | exception Sys_error msg -> raise (Error (GenericError, Some msg))
end
