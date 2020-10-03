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
-export([]).

  %% record for neuron init.
-record(neuron_statem_state, {etsTid, actTypePar=identity,weightPar,biasPar=0,leakageFactorPar=5,leakagePeriodPar=73,pidIn=[],pidOut=[]}).

%%%===================================================================
%%%  Supervisor
%%%===================================================================
%% neuron_supervisor:start_shell().
start_shell()->
  register(shell, self()),
  spawn(fun()->neuron_supervisor:start()end).

start()->
  %Set as a system process
  process_flag(trap_exit, true),
  %% Open an ets heir and holders process in every Node
  %% Get messages with the Tid from ets processes.
  Samp = pcm_handler:create_wave_list(100,115,1),
  Map = neuron_supervisor:start4neurons(Samp, 0, fournodes),
  supervisor(Map).

supervisor(Map)->
  receive
    Message={'EXIT',_, _} -> %% from linked pid (linked to all)
      shell!Message,
      exit(die_bitch)
  end.

%% pdm to sleep.
%% 17 process destroy.
%% Reset Msg queue.

%%%===================================================================
%%%  4 Neurons Launcher
%%%===================================================================

%% Samp = pcm_handler:create_wave_list(100,115,1).
%% neuron_supervisor:start4neurons(Samp,100, nonode).
%% neuron_supervisor:start4neurons(Samp, 0, fournodes).

%% List=pcm_handler:create_wave_list(0, 2, 1).
%% neuron_supervisor:start4neurons(List, 0, fournodes).
start4neurons(Samp,Start_freq, Resonator_options) ->
  %pcm_handler:create_wave(Start_freq, End_freq, 1),
  io:format("here1~n"),
  PidTiming = spawn(fun()->pcm_handler:timing_process(self())end),
  PidSender = spawn_link(pcm_handler,pdm_process,[Samp, 40]),
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
  NeuronName2Pid_map=  start_resonator_4stage(nonode, nonode),
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

  NeuronName2Pid=lists:map(fun({Name, Record}) -> {ok,Pid}=neuron_statem:start_link(Name, Record), {Name, Pid} end, Neurons),
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
start_resonator_4stage(onenode, _) ->
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
  [Tid1, Tid2, Tid3, Tid4] = gatherTid_4nodes(Nodes, []),

  %%% Start 4
  %%% statem neurons
  Neurons = [{afi1, #neuron_statem_state{etsTid=Tid1,weightPar=[11,-9], biasPar=-1}, Node1},
    {afi21, #neuron_statem_state{etsTid=Tid2,weightPar=[10], biasPar=-5}, Node2},
    {afi22, #neuron_statem_state{etsTid=Tid3,weightPar=[10], biasPar=-5}, Node3},
    {afi23, #neuron_statem_state{etsTid=Tid4,weightPar=[10], biasPar=-5}, Node4}],

  NeuronName2Pid=lists:map(fun({Name, Record, Node}) ->
    {ok,Pid}=rpc:call(Node, neuron_statem, start, [Record]), link(Pid), {Name, Pid} end, Neurons),
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),

  %%%% using global name {global, 'afi1'}.
  %%%% rpc:call - start_link_global
  %neuron_statem:pidConfig({global,'afi1'}, [enable,get(pid_data_sender),maps:get(afi23,NeuronName2Pid_map)],
  %  [maps:get(afi21, NeuronName2Pid_map),{finalAcc,get(pid_acc_getter)}]),
  %neuron_statem:pidConfig({global, 'afi21'}, [enable,maps:get(afi1,NeuronName2Pid_map)],
  %  [maps:get(afi22, NeuronName2Pid_map)]),
  %neuron_statem:pidConfig({global, 'afi22'}, [enable,maps:get(afi21,NeuronName2Pid_map)],
  %  [maps:get(afi23, NeuronName2Pid_map)]),
  %neuron_statem:pidConfig({global, 'afi23'}, [enable,maps:get(afi22,NeuronName2Pid_map)],
  %  [maps:get(afi1, NeuronName2Pid_map)]),

  %%%% using pid only, link
  %%%% rpc:call - start, link
  neuron_statem:pidConfig(maps:get(afi1,NeuronName2Pid_map), [enable,get(pid_data_sender),maps:get(afi23,NeuronName2Pid_map)],
    [maps:get(afi21, NeuronName2Pid_map),{finalAcc,get(pid_acc_getter)}]),
  neuron_statem:pidConfig(maps:get(afi21,NeuronName2Pid_map), [enable,maps:get(afi1,NeuronName2Pid_map)],
    [maps:get(afi22, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi22,NeuronName2Pid_map), [enable,maps:get(afi21,NeuronName2Pid_map)],
    [maps:get(afi23, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi23,NeuronName2Pid_map), [enable,maps:get(afi22,NeuronName2Pid_map)],
    [maps:get(afi1, NeuronName2Pid_map)]),

  %%%% using local name and node name
  %%%% HAVE to USE NAME from start_link   ****
  %%%% rpc:call - start_link
  %%neuron_statem:pidConfig({afi1, Node1}, [enable,get(pid_data_sender),maps:get(afi23,NeuronName2Pid_map)],
  %%  [maps:get(afi21, NeuronName2Pid_map),{finalAcc,get(pid_acc_getter)}]),
  %%neuron_statem:pidConfig({maps:get(afi21,NeuronName2Pid_map), Node2}, [enable,maps:get(afi1,NeuronName2Pid_map)],
  %%  [maps:get(afi22, NeuronName2Pid_map)]),
  %%neuron_statem:pidConfig({maps:get(afi22,NeuronName2Pid_map), Node3}, [enable,maps:get(afi21,NeuronName2Pid_map)],
  %%  [maps:get(afi23, NeuronName2Pid_map)]),
  %%neuron_statem:pidConfig({maps:get(afi23,NeuronName2Pid_map), Node4}, [enable,maps:get(afi22,NeuronName2Pid_map)],
  %%  [maps:get(afi1, NeuronName2Pid_map)]),

  NeuronName2Pid_map.


gatherTid_4nodes([Node|Nodes], List)->
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



%supervisor()->
%  receive
%    {'EXIT',FromPid, Reason} ->
%      case get(is_fix_mode) of
%        Bool when Bool==false -> rpc:pmap({'neuron_supervisor','fix_mode_node'}, [], maps:to_list(get(pid_per_node)));
%        true -> already_in_fix_mode
%      end,
%      PidList = gatherPid([{FromPid, Reason}]),
%      lists:map(restoreNeuron/1, PidList)
%  ;
%    {nodedown, Node} -> need_restart
%
%  end.

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
  {Node, lists:map(fun(X)-> {spawn_link(Node, neuron_statem, start_link/2, [Tid, #{}]), {Node, Tid}}  end, NeuronParameters)}.

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
  NeuronName2Pid_map = start_resonator_4stage(nonode,nonode),
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