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


type tool_info


val ignore_dirs : bool


val filter_resource : tool_options -> string -> bool


val filter_conflict : Analyzer.file_acc_t * Analyzer.file_acc_t -> bool


val adapt_tasks : string -> string -> Graph.graph -> string * string


val refine_analysis_out :
  tool_options
  -> Analyzer.analysis_out
  -> (Analyzer.analysis_out * Task_info.task_info * tool_info) 


val process_file_access :
  string
  -> tool_options
  -> Analyzer.file_acc_t list
  -> (Analyzer.analysis_out * tool_info)
  -> Fault_detection.t
  -> Fault_detection.t


val process_access_conflict :
  string
  -> tool_options
  -> Analyzer.file_acc_t * Analyzer.file_acc_t
  -> (Analyzer.analysis_out * tool_info)
  -> Fault_detection.t
  -> Fault_detection.t
