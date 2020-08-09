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


type file_acc_t = Domains.abstraction_effect * Syntax.syscall_desc


type f_accesses = file_acc_t list Util.Strings.t


type analysis_out = {
  facc: f_accesses;
  task_graph: Graph.graph;
  dirs: Util.StringSet.t;
}


module type ToolType =
  sig
    val adapt_effect :
      string
      -> Domains.syscall_effect
      -> (string * Domains.abstraction_effect)
  end


module type S =
  sig
    val analyze_traces :
      Stats.t
      -> Syntax.trace Syntax.stream
      -> Stats.t * analysis_out
  end


module Make(T: ToolType) = struct

  let update_graph graph resource effects =
    match resource with
    | None          -> graph
    | Some resource ->
      List.fold_left (fun acc (effect, sdesc) ->
        let key, effect' = T.adapt_effect resource effect in
        match Strings.find_opt key acc with
        | None -> Strings.add key [effect', sdesc] acc
        | Some effects ->
          Strings.add key ((effect', sdesc) :: effects) acc
      ) graph (Domains.unique_effects effects)


  let rec _analyze_traces stats traces state acc =
    let trace = Syntax.peek_trace traces in
    match trace with
    | Some (pid, (Syntax.End_task v, sdesc) as trace)
    | Some (pid, (Syntax.Begin_task v, sdesc) as trace) ->
      let stats =
        match v with
        | ""                      -> stats
        | v when Syntax.is_main v -> stats
        | v                       -> Stats.add_task v  stats
      and resource =
        match state.Domains.o with
        | resource :: _ -> Some resource
        | []            -> None
      in
      let state = Interpreter.interpret trace state in
      _analyze_traces
        (Stats.add_trace_entry stats)
        (Syntax.next_trace traces)
        (Domains.reset_effect_store state)
        (update_graph acc resource (Domains.get_effects state))
    | Some (pid, trace) ->
      _analyze_traces
        (Stats.add_trace_entry stats)
        (Syntax.next_trace traces)
        (Interpreter.interpret (pid, trace) state)
        acc
    | None ->
        stats,
        {facc = acc;
         task_graph = state.f;
         dirs = state.q;}

  let analyze_traces stats traces =
    let stats, aout =
      _analyze_traces
        (Stats.begin_counter stats)
        traces
        (Domains.init_state ())
        Strings.empty
    in
    let stats =
      stats
      |> Stats.add_analysis_time
      |> Stats.add_files (Util.Strings.cardinal aout.facc)
    in
    stats, aout
end
