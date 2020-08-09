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
  | Ok
  | Err of string


type mode =
  | Online
  | Offline


module type ToolType =
  sig
    type tool_options

    val validate_options : mode -> tool_options -> option_status

    val construct_command : tool_options -> string array

    module SysParser : Sys_parser.S

    module TraceAnalyzer : Analyzer.S

    module FaultDetector : Fault_detection.S with type tool_options = tool_options

  end


module type S =
  sig
    type generic_options =
      {mode: mode;
       graph_file: string option;
       graph_format: Graph.graph_format;
       print_stats: bool;
       trace_file: string option;
       dump_tool_out: string option;
      }

    type tool_options

    val online_analysis : generic_options -> tool_options -> unit

    val offline_analysis : generic_options -> tool_options -> unit
  end


module Make(T: ToolType) = struct

  let syscalls = [
    "access";
    "chdir";
    "chmod";
    "chown";
    "clone";
    "close";
    "dup";
    "dup2";
    "dup3";
    "execve";
    "fchdir";
    "fchmodat";
    "fchownat";
    "fcntl";
    "fork";
    "getxattr";
    "getcwd";
    "lchown";
    "lgetxattr";
    "lremovexattr";
    "lsetxattr";
    "lstat";
    "link";
    "linkat";
    "mkdir";
    "mkdirat";
    "mknod";
    "open";
    "openat";
    "readlink";
    "readlinkat";
    "removexattr";
    "rename";
    "renameat";
    "rmdir";
    "stat";
    "statfs";
    "symlink";
    "symlinkat";
    "unlink";
    "unlinkat";
    "utime";
    "utimensat";
    "utimes";
    "vfork";
    "write";
    "writev";
  ]

  type generic_options =
    {mode: mode;
     graph_file: string option;
     graph_format: Graph.graph_format;
     print_stats: bool;
     trace_file: string option;
     dump_tool_out: string option;
    }


  type tool_options = T.tool_options


  type read_point =
    | File of string
    | FileDesc of Unix.file_descr


  let child_failed_status_code = 255


  let make_executor_err msg =
    raise (Errors.Error (Errors.ExecutorError, Some msg))


  let string_of_unix_err err call params =
    Printf.sprintf "%s: %s (%s)" (Unix.error_message err) call params


  let trace_execution generic_options tool_options input =
    let tool_cmd = T.construct_command tool_options in
    let prog = "/usr/bin/strace" in
    let fd_out = input |> Fd_send_recv.int_of_fd |> string_of_int in
    let strace_cmd = [|
      "strace";
      "-s";
      "300";
      "-e";
      (String.concat "," syscalls);
      "-o";
      ("/dev/fd/" ^ fd_out);
      "-f"; |]
    in
    let cmd = Array.append strace_cmd tool_cmd in 
    try
      print_endline ("\x1b[0;32mInfo: Start tracing command: "
        ^ (String.concat " " (Array.to_list tool_cmd)) ^ " ...\x1b[0m");
      let out =
        match generic_options.dump_tool_out with
        | None          -> "/dev/null"
        | Some tool_out -> tool_out
      in
      let fd = Unix.openfile out [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o640 in
      let _ = Unix.dup2 fd Unix.stdout in
      let _ = Unix.dup2 fd Unix.stderr in
      let _ = Unix.close fd in
      ignore (Unix.execv prog cmd);
      exit 254; (* We should never reach here. *)
    with Unix.Unix_error (err, call, params) ->
      (* Maybe strace is not installed in the system.
        So, we pass the exception to err to the pipe
        so that it can be read by the parent process. *)
      let msg = string_of_unix_err err call params in
      begin
        ignore (Unix.write input (Bytes.of_string msg) 0 (String.length msg));
        Unix.close input;
        exit child_failed_status_code;
      end


  let analyze_trace_internal read_p debug_trace generic_options tool_options =
    let stats, aout =
      match read_p with
      | File p     ->
        p
        |> T.SysParser.parse_trace_file debug_trace
        |> T.TraceAnalyzer.analyze_traces (Stats.init_stats ())
      | FileDesc p ->
        p
        |> T.SysParser.parse_trace_fd debug_trace
        |> T.TraceAnalyzer.analyze_traces (Stats.init_stats ())
    in
    T.FaultDetector.detect_faults
      ~print_stats: generic_options.print_stats
      ~graph_format: generic_options.graph_format
      stats generic_options.graph_file tool_options aout


  let online_analysis generic_options tool_options =
    let output, input = Unix.pipe () in
    (* We create a child process that is responsible for invoking
     strace and run the build script in parallel. *)
    match Unix.fork () with
    | 0   ->
      Unix.close output;
      trace_execution generic_options tool_options input
    | pid -> (
      Unix.close input;
      analyze_trace_internal
        (FileDesc output) generic_options.trace_file generic_options tool_options;
      try
        Unix.kill pid Sys.sigkill;
        Unix.close output;
      with Unix.Unix_error _ -> ())
    | exception Unix.Unix_error (err, call, params) ->
      params |> string_of_unix_err err call |> make_executor_err


  let offline_analysis generic_options tool_options =
    match generic_options.trace_file with
    | None            -> make_executor_err "Offline analysis requires trace file"
    | Some trace_file ->
      analyze_trace_internal (File trace_file) None generic_options tool_options
end
