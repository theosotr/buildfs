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


open Build_options


type tool_options = Build_options.tool_options


let validate_options mode tool_options =
  match mode, tool_options with
  | Executor.Offline, { build_task = Some _; _ } ->
    Executor.Err "Option `-build-task` is only compatible with the mode 'online'"
  | _ -> Executor.Ok


let construct_command _ =
  [|
    "fsmake-make";
  |]


module SysParser = Sys_parser.Make(Make_parser)
module TraceAnalyzer = Analyzer.Make(Build_analyzer)
module FaultDetector = Fault_detection.Make(Make_fault)
