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
-compile(export_all).
-export([ start4neurons/0, start4neurons/3]).

  %% record for neuron init.
-record(neuron_statem_state, {etsTid, actTypePar=identity,weightPar,biasPar=0,leakageFactorPar=5,leakagePeriodPar=73,pidIn=[],pidOut=[]}).

%%%===================================================================
%%%  4 Neurons Launcher
%%%===================================================================

%% Semp = pcm_handler:create_wave_list(100,115,1).
%% neuron_supervisor:start4neurons(Semp,100, nonode).
%% neuron_supervisor:start4neurons(Samp, 0, fournodes)

%% List=pcm_handler:create_wave_list(0, 2, 1).
%% neuron_supervisor:start4neurons(List, 0, fournodes).
start4neurons(Semp,Start_freq, Resonator_options) ->
  %pcm_handler:create_wave(Start_freq, End_freq, 1),
  io:format("here1~n"),
  PidTiming = spawn(fun()->pcm_handler:timing_process(self())end),
  PidSender = spawn_link(pcm_handler,pdm_process,[Semp, 40]),
  put(pid_data_sender,PidSender),
  PidPlotGraph = spawn_link(python_comm,plot_graph_process,[append_acc_vs_freq,plot_acc_vs_freq_global,[Start_freq]]),
  PidAcc = spawn(fun()->pcm_handler:acc_process_appendData(PidTiming,PidSender,PidPlotGraph)end),
  io:format("here2~n"),
  put(pid_acc_getter,PidAcc),
  NeuronName2Pid_map=  start_resonator_4stage(Resonator_options, nonode),
  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),maps:get(afi23,NeuronName2Pid_map),<<1>>,x),
  PidSender ! maps:get(afi1,NeuronName2Pid_map).
%python_comm:plot_graph(plot_acc_vs_freq,["output_wave.pcm",Start_freq]).

start4neurons() ->
  %pcm_handler:create_wave(Start_freq, End_freq, 1),
  io:format("here1~n"),
  PidTiming = spawn(fun()->pcm_handler:timing_process(self())end),
  PidSender = spawn_link(pcm_handler,pdm_process,["input_wave_erl.pcm", 40]),
  put(pid_data_sender,PidSender),
  PidAcc = spawn(fun()->pcm_handler:acc_process("output_wave", PidTiming,PidSender)end),
  io:format("here2~n"),
  put(pid_acc_getter,PidAcc),
  Tid = ets:new(neurons_data,[set,public]),%% todo:change to ets_statem!!!!!!!!
  NeuronName2Pid_map=  start_resonator_4stage(nonode, nonode, Tid),
  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),maps:get(afi23,NeuronName2Pid_map),<<1>>,x),
  PidSender ! maps:get(afi1,NeuronName2Pid_map).
  %python_comm:plot_graph(plot_acc_vs_freq,["output_wave.pcm",Start_freq]).


start_resonator_4stage(nonode, _) ->
  Tid = ets:new(neurons_data,[set,public]),%% todo:change to ets_statem!!!!!!!!
  Neurons = [{afi1, #neuron_statem_state{etsTid=Tid,weightPar=[11,-9], biasPar=-1}},
    {afi21, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi22, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi23, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}}], % afi24, afi25, afi26, afi27,
  % afb1, afb2, afb3, afb4,
  % afi31, afi32, afi33, afi34],

  NeuronName2Pid=lists:map(fun({Name, Record}) -> {ok,Pid}=neuron_statem:start_link(Name, Tid, Record), {Name, Pid} end, Neurons),
  %list neuron name -> pid
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  neuron_statem:pidConfig(maps:get(afi1,NeuronName2Pid_map), [enable,get(pid_data_sender),maps:get(afi23,NeuronName2Pid_map)],
    [maps:get(afi21, NeuronName2Pid_map),{finalAcc,get(pid_acc_getter)}]),
  neuron_statem:pidConfig(maps:get(afi21,NeuronName2Pid_map), [enable,maps:get(afi1,NeuronName2Pid_map)],
    [maps:get(afi22, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi22,NeuronName2Pid_map), [enable,maps:get(afi21,NeuronName2Pid_map)],
    [maps:get(afi23, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi23,NeuronName2Pid_map), [enable,maps:get(afi22,NeuronName2Pid_map)],
    [maps:get(afi1, NeuronName2Pid_map)]),
  NeuronName2Pid_map;
start_resonator_4stage(onenode, Node) ->
  do;

%% neuron_supervisor:start_resonator_4stage(fournodes, hi, bye).
start_resonator_4stage(fournodes, _) ->
  register(supervisor, self()),
  Nodes = ['adi@adisolo','eran@adisolo','emm@adisolo','yuda@adisolo'],
  Node1 = 'adi@adisolo',
  Node2 = 'eran@adisolo',
  Node3 = 'emm@adisolo',
  Node4 = 'yuda@adisolo',

  %%% Open 4 ets
  %%% tables on each node.
  lists:foreach(fun(Node)->rpc:call(Node, neuron_supervisor, spawn_ets, [node()])end, Nodes),
  erlang:display("gather"),
  [Tid1, Tid2, Tid3, Tid4] = gatherTid_4nodes(Nodes, []),
  erlang:display("ended gather"),

  %%% Start 4
  %%% statem neurons
  Neurons = [{afi1, #neuron_statem_state{etsTid=Tid1,weightPar=[11,-9], biasPar=-1}, Node1, Tid1},
    {afi21, #neuron_statem_state{etsTid=Tid2,weightPar=[10], biasPar=-5}, Node2, Tid2},
    {afi22, #neuron_statem_state{etsTid=Tid3,weightPar=[10], biasPar=-5}, Node3, Tid3},
    {afi23, #neuron_statem_state{etsTid=Tid4,weightPar=[10], biasPar=-5}, Node4, Tid4}],

  NeuronName2Pid=lists:map(fun({Name, Record, Node, Tid}) ->
    {ok,Pid}=rpc:call(Node, neuron_statem, start_link_global, [Name,Tid, Record]), {Name, Pid} end, Neurons),
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),

  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  neuron_statem:pidConfig(maps:get(afi1,NeuronName2Pid_map), [enable,get(pid_data_sender),maps:get(afi23,NeuronName2Pid_map)],
    [maps:get(afi21, NeuronName2Pid_map),{finalAcc,get(pid_acc_getter)}]),
  neuron_statem:pidConfig(maps:get(afi21,NeuronName2Pid_map), [enable,maps:get(afi1,NeuronName2Pid_map)],
    [maps:get(afi22, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi22,NeuronName2Pid_map), [enable,maps:get(afi21,NeuronName2Pid_map)],
    [maps:get(afi23, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi23,NeuronName2Pid_map), [enable,maps:get(afi22,NeuronName2Pid_map)],
    [maps:get(afi1, NeuronName2Pid_map)]),
  NeuronName2Pid_map.


gatherTid_4nodes(All=[Node|Nodes], List)->
  receive
    {Tid, Node} -> gatherTid_4nodes(Nodes, List++[Tid])
  end;
gatherTid_4nodes([], List) -> List.

spawn_ets(Node)->
  spawn(fun()-> ets(Node) end).

ets(Node)->
  Tid = ets:new(neurons_data,[set,public]),
  erlang:display("ets opened"),
  rpc:call(Node, neuron_supervisor, send_message_to_supervisor, [{Tid, node()}]),
  receive
    die -> nothing
  end.

send_message_to_supervisor(Message)->
  supervisor!Message.


get_new_atom(Node, Num) -> list_to_atom(lists:flatten(io_lib:format("~p~p", [Node, Num]))).



%%%===================================================================
%%% Old functions - adi
%%%===================================================================


start(Nodes)->nothing.
%  % Set as a system process
%  process_flag(trap_exit, true),
%
%  %% Open an ets heir and holders process in every Node
%  % Save as {Node, Pid} in a EtsProcessHeir, EtsHolders.
%  EtsProcessHeir = lists:map(fun(Node)->{Node, spawn_link(Node, ets_statem, start_link/3, [self(), backup, none])} end, Nodes),
%   EtsHolders = lists:map(fun({Node, PidHeir})->{Node, spawn_link(Node, ets_statem, start_link/3, [self(), ets_owner, PidHeir])} end, EtsProcessHeir),
%
%  %% Get messages with the Tid from ets processes.
%  EtsTid = gatherTid(EtsHolders, []),
%
%  % uses zip: [{Node, LayerSize, Tid},...]
%  % list of {Node, [{Pid,{Node, Tid}},....]}
%  NeuronListPerNode = lists:map(fun createLayerNeurons/1, lists:zip3(NodeNames, ListLayerSize, EtsTid)),
%  net_connect(remove_info(NeuronListPerNode)),
%  %% create two maps of pids.
%  %% One by nodes and pids, and one by pids
%  % Returns #{Node->#{Pid->{Node,Tid}}}
%  MapsPerNode = maps:from_list(lists:map(fun({Node, List}) ->{Node, maps:from_list(List)} end, NeuronListPerNode)),
%  put(pid_per_node, MapsPerNode),
%  MapsOfPid = maps:from_list(sum_all_pid(NeuronListPerNode)),
%  put(pid, MapsOfPid),
%  put(nodes, NodeNames),
%  supervisor().



supervisor()->
  receive
    {'EXIT',Pid, Reason} ->
      case get(is_fix_mode) of
        Bool when Bool==false -> rpc:pmap({'neuron_supervisor','fix_mode_node'}, [], maps:to_list(get(pid_per_node)));
        true -> already_in_fix_mode
      end,
      PidList = gatherPid([{Pid, Reason}]),
      lists:map(restoreNeuron/1, PidList)
  ;
    {nodedown, Node} -> need_restart
  %% Todo: add API of neuron_statem:fix_mode(Pid) ->gen_statem:cast(Pid, fixMessage)
  end.

%% Get all of the Pid that fell.
% Returns list of {Pid, Reason} that fell.
gatherPid(List) ->
  receive
    {'EXIT', Pid, Reason} -> gatherPid(List++[{Pid, Reason}])
      after
    100 -> done
  end.

restoreNeuron({Pid,_})->
  {Node, Tid}= maps:get(Pid, get(pid)).
%% Gets message with Tid of every ets process.
gatherTid([{Node, {Pid, _}}|EtsHolders], List)->
  receive
    Tuple={{Node, Pid}, Tid} -> put(Pid, Tuple), gatherTid(EtsHolders, List++[Tid])
  end;
gatherTid([], List) -> List.

%% start_link all of the neurons.
%% Returns a list of {Node, [{Pid,{Node,Tid}} ..]}
createLayerNeurons({Node, LayerSize, Tid})->
  NeuronParameters = lists:seq(1, LayerSize),
  % Todo: get the neuron parameters in a map/record and put in the list.
  % Todo: -record(neuron_statem_state, {etsTid,actTypePar,weightPar,biasPar,leakageFactorPar,leakagePeriodPar,pidIn,pidOut}).
  {Node, lists:map(fun(X)-> {spawn_link(Node, neuron_statem, start_link/3, [Tid, #{}]), {Node, Tid}}  end, NeuronParameters)}.

%% spawns and monitors a process at node NODE.
%% returns {Pid, Ref}.
%% no use.
spawn_monitor(Node, Module, Func, Args) ->
  {ok, MonitoredPid} = rpc:call(Node, Module, Func, Args),
  {MonitoredPid, monitor(process, MonitoredPid)}.

% lists of {Node1, [Pid, ....]}
% sends PrevLayer, NextLayer = {Node, List}.
net_connect(NeuronListPerNode)->
  net_connect({node(), [self()]},NeuronListPerNode++[{node(), [self()]}]).
net_connect(Prev,[Curr={Node, ListNeurons}, Next|NextNeuronListPerNode])->
  lists:foreach(fun(Pid) -> rpc:call(Node, neuron_statem, net_connect/1, [Pid, {Prev,Next}]) end, ListNeurons),
  net_connect(Curr, Next, NextNeuronListPerNode).
net_connect(_, _, [])-> done.

  % Todo: add net_connect API of a gen_statem:cast.
  % Todo: Something like - neuron_statem:net_connect(Pid, Pids)-> gen_statem:cast(Pid, Pids).
  % Todo: change receiving on neuron_statem:networking to {Node, ListPids}.

%% returns list of {Node, [Pid,...]}
remove_info(List) ->
  lists:map(fun({Node, ListNeurons}) -> {Node, lists:map(fun ({Pid, _})-> Pid end, ListNeurons)}end, List).

%% returns list of {Pid, {Node,Tid}}
sum_all_pid(NeuronListPerNode) ->
  sum_all_pid(NeuronListPerNode, []).
sum_all_pid([], List)-> List;
sum_all_pid([{_, PidTuple}|NeuronListPerNode], List)-> sum_all_pid(NeuronListPerNode, PidTuple++List).

% gets {Node ->#{Pid->{Node, Tid}}
fix_mode_node({_, Map}) ->
  ListNeuron = maps:to_list(Map),
  lists:foreach(fun({Pid, {Node, _}})-> rpc:call(Node,neuron_statem,fix_mode/1,Pid)end, ListNeuron),
  done.
  %% uses API of neuron_statem:fix_mode(Pid) ->gen_statem:cast(Pid, fixMessage)

%%%===================================================================
%%% Testing functions
%%%===================================================================

%%% tested the monitor - works.
test_monitor_spawn()->
  register(me, Pid=spawn(fun()->test_monitor() end)),
  {ok,Pid}.

test_monitor()->
  case erlang:whereis(self()) of
    S when S==undefined -> register(me, self());
    _ -> nothing
  end,
  receive
    exit -> exiting;
    Message -> whereis(shell)!Message, test_monitor()
  end.


debugResonator_4stage() ->
  Tid = ets:new(neurons_data,[set,public]),
  Self = self(),
  put(pid_data_sender,Self),
  NeuronName2Pid_map = start_resonator_4stage(nonode,nonode,Tid),
  receive
  after 10000 -> io:format("\n\nend wait ~p\n\n",[NeuronName2Pid_map])
  end,
  io:format("finish config!!!!!!!!!!!!!"),
  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),get(pid_data_sender),<<1>>,x),
  receive
    X -> io:format("1.got ------  ~p\n",[X])
  after 1000 -> io:format("1.not got\n")
  end,
  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),maps:get(afi23,NeuronName2Pid_map),<<1>>,x),
  receive
    Y -> io:format("2.got ------  ~p\n",[Y])
  after 1000 -> io:format("2.not got\n")
  end,
  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),get(pid_data_sender),<<1>>,x),
  receive
    Z -> io:format("3.got ------  ~p\n",[Z])
  after 1000 -> io:format("3.not got\n")
  end,
  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),get(pid_data_sender),<<0>>,x),
  receive
    K-> io:format("3.got ------  ~p\n",[K])
  after 1000 -> io:format("3.not got\n")
  end.