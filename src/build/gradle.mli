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


type tool_options = Build_options.tool_options


val validate_options : Executor.mode -> tool_options -> Executor.option_status 


val construct_command : tool_options -> string array


module SysParser : Sys_parser.S


module TraceAnalyzer : Analyzer.S


module FaultDetector : Fault_detection.S with type tool_options = tool_options
