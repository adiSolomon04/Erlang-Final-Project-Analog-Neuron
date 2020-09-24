%%%-------------------------------------------------------------------
%%% @author adisolo
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 29. Jul 2020 16:42
%%%-------------------------------------------------------------------
-module(neuron_supervisor).
-author("adisolo").

%% API
-export([start/2]).

start(ListLayerSize, InputFile)->
  NodeNames = [node1, node2, node3, node4],
  %%Open an ets heir and holders process in every Node
  %%Save as {Node, {Pid, Ref}} in a EtsProcessHeir, EtsHolders.

  EtsProcessHeir = lists:map(fun(Node)->{Node, spawn_monitor(Node, ets_statem, start_link/3, [self(), backup, none])} end, NodeNames),
  EtsHolders = lists:map(fun({Node, PidHeir})->{Node, spawn_monitor(Node, ets_statem, start_link/3, [self(), ets_owner, PidHeir])} end, EtsProcessHeir),
  EtsTid = gatherTid(EtsHolders, []),
  % Returns [{Node, LayerSize, Tid}...]
  NodesLayerSize = lists:zip3(NodeNames, ListLayerSize, EtsTid),
  NeuronProcessLayer = lists:map(fun createLayerNeurons/1, NodesLayerSize).



%% start_link all of the neurons.
%% Returns a list of [{Node1, [N1Pid1, ....]}, {Node2, [N2Pid1, ....]},...]
createLayerNeurons({Node, LayerSize, Tid})->
  NeuronList = lists:seq(1, LayerSize),
  {Node, lists:map(fun(X)-> spawn_monitor(Node, neuron_statem, start_link/3, [Tid, X])  end, NeuronList)}.



gatherTid([{Node, {Pid, _}}|EtsHolders], List)->
  receive
    Tuple={{Node, Pid}, Tid} -> put(Pid, Tuple), gatherTid(EtsHolders, List++[Tid])
  end;
gatherTid([], List) -> List.


spawn_monitor(Node, Module, Func, Args) ->
  {ok, MonitoredPid} = rpc:call(Node, Module, Func, Args),
  {MonitoredPid, monitor(process, MonitoredPid)}.