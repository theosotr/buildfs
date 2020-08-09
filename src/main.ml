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


open Buildfs


let handle_error err msg =
  match msg with
  | None ->
    begin
      Printf.eprintf "Error: %s" (Errors.string_of_error err);
      exit 1;
    end
  | Some msg ->
    begin
      Printf.eprintf "Error: %s: %s" (Errors.string_of_error err) msg;
      exit 1;
    end


let format_of_string = function
  | "dot" -> Graph.Dot
  | "csv" -> Graph.Csv
  | _     ->
    begin
      Printf.eprintf "Format must be either 'dot' or 'csv'";
      exit 1;
    end


let mode_of_string = function
  | "online"  -> Executor.Online
  | "offline" -> Executor.Offline
  | _         ->
    begin
      Printf.eprintf "Mode must be either 'online' or 'offline'";
      exit 1;
    end


let gradle_tool =
  let open Core.Command.Let_syntax in
  Core.Command.basic
    ~summary:"This is the sub-command for analyzing and detecting faults in Gradle scripts"
    [%map_open
    let build_task =
      flag "build-task" (optional string)
      ~doc:"Build task to execute"
    and build_dir =
      flag "build-dir" (required string)
      ~doc:"Build directory"
    and mode =
      flag "mode" (required (Arg_type.create mode_of_string))
      ~doc: "Analysis mode; either online or offline"
    and trace_file =
      flag "trace-file" (optional string)
      ~doc:"Path to trace file produced by the 'strace' tool."
    and dump_tool_out =
      flag "dump-tool-out" (optional string)
      ~doc: "File to store output from Gradle execution (for debugging only)"
    and graph_format =
      flag "graph-format" (optional_with_default Graph.Dot (Arg_type.create format_of_string))
      ~doc: "Format for storing the task graph of the BuildFS program."
    and graph_file =
      flag "graph-file" (optional string)
      ~doc: "File to store the task graph inferred by BuildFS."
    and print_stats =
      flag "print-stats" (no_arg)
      ~doc: "Print stats about execution and analysis"
    in
    fun () ->
      let module GradleExecutor = Executor.Make(Gradle) in
      let open GradleExecutor in
      let gradle_options =
        {Build_options.build_task = build_task;
         Build_options.build_dir = build_dir;
         Build_options.ignore_mout = false;
         Build_options.build_db = None;
        }
      in
      let generic_options =
        {GradleExecutor.trace_file = trace_file;
         GradleExecutor.dump_tool_out = dump_tool_out;
         GradleExecutor.mode = mode;
         GradleExecutor.graph_file = graph_file;
         GradleExecutor.graph_format = graph_format;
         GradleExecutor.print_stats = print_stats;}
      in
      match Gradle.validate_options generic_options.mode gradle_options with
      | Executor.Err err ->
        Printf.eprintf "Error: %s. Run command with -help" err;
        exit 1
      | Executor.Ok ->
        try
          match generic_options with
          | { mode = Online; _; } ->
            online_analysis generic_options gradle_options
          | { mode = Offline; _; } ->
            offline_analysis generic_options gradle_options
        with Errors.Error (err, msg) -> handle_error err msg
    ]


let make_tool =
  let open Core.Command.Let_syntax in
  Core.Command.basic
    ~summary:"This is the sub-command for analyzing and detecting faults in Make scripts"
    [%map_open
    let build_dir =
      flag "build-dir" (required string)
      ~doc:"Build directory"
    and build_db =
      flag "build-db" (optional string)
      ~doc: "Path to Make database"
    and mode =
      flag "mode" (required (Arg_type.create mode_of_string))
      ~doc: "Analysis mode; either online or offline"
    and trace_file =
      flag "trace-file" (optional string)
      ~doc:"Path to trace file produced by the 'strace' tool."
    and dump_tool_out =
      flag "dump-tool-out" (optional string)
      ~doc: "File to store output from Make execution (for debugging only)"
    and graph_format =
      flag "graph-format" (optional_with_default Graph.Dot (Arg_type.create format_of_string))
      ~doc: "Format for storing the task graph of the BuildFS program."
    and graph_file =
      flag "graph-file" (optional string)
      ~doc: "File to store the task graph inferred by BuildFS."
    and print_stats =
      flag "print-stats" (no_arg)
      ~doc: "Print stats about execution and analysis"
    in
    fun () ->
      let module MakeExecutor = Executor.Make(Make) in
      let open MakeExecutor in
      let make_options =
        {Build_options.build_task = None;
         Build_options.build_dir = build_dir;
         Build_options.ignore_mout = true;
         Build_options.build_db = build_db;
        }
      in
      let generic_options =
        {MakeExecutor.trace_file = trace_file;
         MakeExecutor.dump_tool_out = dump_tool_out;
         MakeExecutor.mode = mode;
         MakeExecutor.graph_file = graph_file;
         MakeExecutor.graph_format = graph_format;
         MakeExecutor.print_stats = print_stats;}
      in
      match Make.validate_options generic_options.mode make_options with
      | Executor.Err err ->
        Printf.eprintf "Error: %s. Run command with -help" err;
        exit 1
      | Executor.Ok ->
        try
          match generic_options with
          | { mode = Online; _; } ->
            online_analysis generic_options make_options
          | { mode = Offline; _; } ->
            offline_analysis generic_options make_options
        with Errors.Error (err, msg) -> handle_error err msg
    ]

let () =
  Core.Command.group
    ~summary:"Detecting faults in Parallel and Incremental Builds."
    [
      "gradle-build", gradle_tool;
      "make-build",   make_tool;
                              
    ] |> Core.Command.run
