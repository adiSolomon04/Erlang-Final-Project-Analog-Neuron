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

-export([start/3, fix_mode_node/1, start4neurons/0, start4neurons/3, open_ets_satatem/4, supervisorEran/ 1,fix4neurons/6]).

  %% record for neuron init.
-record(neuron_statem_state, {etsTid, actTypePar=identity,weightPar,biasPar=0,leakageFactorPar=5,leakagePeriodPar=73,pidIn=[],pidOut=[]}).

%%%===================================================================
%%% API
%%%===================================================================


%% not use very old
start(ListLayerSize, NumEts, InputFile)->
  % Set as a system process
  process_flag(trap_exit, true),

  %% todo: will get the nodes from user
  NodeNames = [node1, node2, node3, node4],

  %% Open an ets heir and holders process in every Node
  % Save as {Node, Pid} in a EtsProcessHeir, EtsHolders.
  EtsProcessHeir = lists:map(fun(Node)->{Node, spawn_link(Node, ets_statem, start_link/3, [self(), backup, none])} end, NodeNames),
  EtsHolders = lists:map(fun({Node, PidHeir})->{Node, spawn_link(Node, ets_statem, start_link/3, [self(), ets_owner, PidHeir])} end, EtsProcessHeir),

  %% Get messages with the Tid from ets processes.
  EtsTid = gatherTid(EtsHolders, []),

  % uses zip: [{Node, LayerSize, Tid},...]
  % list of {Node, [{Pid,{Node, Tid}},....]}
  NeuronListPerNode = lists:map(fun createLayerNeurons/1, lists:zip3(NodeNames, ListLayerSize, EtsTid)),
  net_connect(remove_info(NeuronListPerNode)),
  %% create two maps of pids.
  %% One by nodes and pids, and one by pids
  % Returns #{Node->#{Pid->{Node,Tid}}}
  MapsPerNode = maps:from_list(lists:map(fun({Node, List}) ->{Node, maps:from_list(List)} end, NeuronListPerNode)),
  put(pid_per_node, MapsPerNode),
  MapsOfPid = maps:from_list(sum_all_pid(NeuronListPerNode)),
  put(pid, MapsOfPid),
  put(nodes, NodeNames),
  supervisor().


%% Semp = pcm_handler:create_wave_list(100,115,1).
%% neuron_supervisor:start4neurons(Semp,100).
start4neurons(Semp,Start_freq,Tid) ->
  %pcm_handler:create_wave(Start_freq, End_freq, 1),
  io:format("here1~n"),
  PidTiming = spawn(fun()->pcm_handler:timing_process(self())end),
  PidSender = spawn_link(pcm_handler,pdm_process,[Semp, 40]),
  put(pid_data_sender,PidSender),
  PidPlotGraph = spawn_link(python_comm,plot_graph_process,[append_acc_vs_freq,plot_acc_vs_freq_global,[Start_freq]]),
  PidAcc = spawn(fun()->pcm_handler:acc_process_appendData(PidTiming,PidSender,PidPlotGraph)end),
  io:format("here2~n"),
  put(pid_data_getter,PidAcc),
  NeuronName2Pid_map=  start_resonator_4stage(nonode, nonode, Tid),
  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),maps:get(afi23,NeuronName2Pid_map),<<1>>,x),
  PidSender ! maps:get(afi1,NeuronName2Pid_map),
  {PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map}.
%python_comm:plot_graph(plot_acc_vs_freq,["output_wave.pcm",Start_freq]).

  start4neurons() ->

  %pcm_handler:create_wave(Start_freq, End_freq, 1),
  io:format("here1~n"),
  PidTiming = spawn(fun()->pcm_handler:timing_process(self())end),
  PidSender = spawn_link(pcm_handler,pdm_process,["input_wave_erl.pcm", 40]),
  put(pid_data_sender,PidSender),
  PidAcc = spawn(fun()->pcm_handler:acc_process("output_wave", PidTiming,PidSender)end),
  io:format("here2~n"),
  put(pid_data_getter,PidAcc),
  Tid = ets:new(neurons_data,[set,public]),%% todo:change to ets_statem!!!!!!!!
  NeuronName2Pid_map=  start_resonator_4stage(nonode, nonode, Tid),
  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),maps:get(afi23,NeuronName2Pid_map),<<1>>,x),
  PidSender ! maps:get(afi1,NeuronName2Pid_map).
  %python_comm:plot_graph(plot_acc_vs_freq,["output_wave.pcm",Start_freq]).


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
  end
.

start_resonator_4stage(nonode, _, Tid) ->
  Neurons = [{afi1, #neuron_statem_state{etsTid=Tid,weightPar=[11,-9], biasPar=-1}},
    {afi21, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi22, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi23, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}}], % afi24, afi25, afi26, afi27,
  % afb1, afb2, afb3, afb4,
  % afi31, afi32, afi33, afi34],
  io:format("~p",[Neurons]),
  NeuronName2Pid=lists:map(fun({Name, Record}) -> {ok,Pid}=neuron_statem:start_link(Name, Tid, Record), {Name, Pid} end, Neurons),
  %list neuron name -> pid
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  %todo:neuron_statem:pid_config(prev, next).
  neuron_statem:pidConfig(maps:get(afi1,NeuronName2Pid_map), [enable,get(pid_data_sender),maps:get(afi23,NeuronName2Pid_map)],
    [maps:get(afi21, NeuronName2Pid_map),{finalAcc,get(pid_data_getter)}]),
  neuron_statem:pidConfig(maps:get(afi21,NeuronName2Pid_map), [enable,maps:get(afi1,NeuronName2Pid_map)],
    [maps:get(afi22, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi22,NeuronName2Pid_map), [enable,maps:get(afi21,NeuronName2Pid_map)],
    [maps:get(afi23, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi23,NeuronName2Pid_map), [enable,maps:get(afi22,NeuronName2Pid_map)],
    [maps:get(afi1, NeuronName2Pid_map)]),
  NeuronName2Pid_map;
start_resonator_4stage(onenode, Node, Tid) ->
  do;
start_resonator_4stage(fournodes, Nodes, Tid) ->
  do.



tryTwoNodes(Node1,Node2,Tid)->
  Record1 = #neuron_statem_state{etsTid=Tid,weightPar=[11]},
  Record2 = #neuron_statem_state{etsTid=Tid,weightPar=[11]},
  {ok,Pid1}= rpc:call(Node1,neuron_statem,start_link,[afi1, Tid, Record1]),
  {ok,Pid2} = rpc:call(Node2,neuron_statem,start_link,[n2, Tid, Record2]),
  neuron_statem:pidConfig(afi1, [enable,get(pid_data_sender)], [n2]),
  neuron_statem:pidConfig(n2, [enable,Pid1], [maps:get(afi22, {finalAcc,get(pid_data_getter)})]).



open_ets_satatem(Pid_Server,NodeName,EtsBackupName,EtsOwnerName)->
  {ok,PidBackup} = rpc:call(NodeName,ets_statem,start_link,[EtsBackupName,Pid_Server,backup,none]),
  erlang:monitor(process,PidBackup),
  {ok,PidEtsOwner} =  rpc:call(NodeName,ets_statem,start_link,[EtsOwnerName,Pid_Server,etsOwner,PidBackup]),
  erlang:monitor(process,PidEtsOwner),
  receive
    {{Node,PidEtsOwner},Tid} ->io:format("open~n"),{{Node,PidEtsOwner,PidBackup},Tid}
  end
  .





%%%===================================================================
%%% eran try to supervise
%%%===================================================================
supervisorEran(NodeName)->
  process_flag(trap_exit, true),
  Start_freq= 100,
  End_freq= 110,
  Semp=pcm_handler:create_wave_list(Start_freq, End_freq, 1),
  Pid_Server = self(),
  %NodeName = erlang:node(),
  EtsBackupName = backup,
  EtsOwnerName = etsOwner,
  {{NodeName,PidEtsOwner,PidBackup},Tid}= open_ets_satatem(Pid_Server,NodeName,EtsBackupName,EtsOwnerName),
  {PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map} = rpc:call(NodeName,neuron_supervisor,start4neurons,[Semp,Start_freq,Tid]),
  erlang:monitor(process,PidSender),
  erlang:monitor(process,PidPlotGraph),
  erlang:monitor(process,PidAcc),
  ListPid = maps:values(NeuronName2Pid_map),
  {LinkedPid,LinkedRef} = spawn_monitor(fun()->lists:foreach(fun(X)->link(X)end,ListPid), receive Y->Y end end),
  %2
  %[FirstPid|RestListofPid] = ListPid,
  %StartLIstofPid=lists:sublist(ListPid,lists:flatlength(RestListofPid)),
  %erlang:monitor(process,FirstPid),
  %lists:foreach(fun({X,Y})->
    %1
  %lists:foreach(fun(X)->monitor(process,X)end,maps:values(NeuronName2Pid_map)),
  io:format("@@@@@@@@@@@@@@@@@@@@~p~n",[{PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map}]),
  supervisorEranLoop(NodeName,Pid_Server,EtsOwnerName,PidEtsOwner,EtsBackupName,PidBackup,PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Tid).

supervisorEranLoop(NodeName,Pid_Server,EtsOwnerName,PidEtsOwner,EtsBackupName,PidBackup,PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Tid)->

  receive
    {'DOWN', Ref, process, Pid, Why}->
      io:format("~p~n",[{'DOWN', Ref, process, Pid, Why}]),
      if Pid == PidBackup -> {ok,PidBackNew} = rpc:call(NodeName,ets_statem,start_link,[EtsBackupName,Pid_Server,backup,none]),
                             rpc:call(NodeName,ets_statem,callChangeHeir,[PidEtsOwner,PidBackNew]),
                              erlang:monitor(process,PidBackNew),
                            supervisorEranLoop(NodeName,Pid_Server,EtsOwnerName,PidEtsOwner,EtsBackupName,PidBackNew,PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Tid);
        Pid == PidEtsOwner -> {ok,PidBackNew} = rpc:call(NodeName,ets_statem,start_link,[EtsBackupName,Pid_Server,backup,none]),
                              rpc:call(NodeName,ets_statem,callChangeHeir,[PidBackup,PidBackNew]),
                              erlang:monitor(process,PidBackNew),
                            supervisorEranLoop(NodeName,Pid_Server,EtsOwnerName,PidBackup,EtsBackupName,PidBackNew,PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Tid);
        Pid == LinkedPid ->
                    NewNeuronName2Pid_map = rpc:call(NodeName,neuron_supervisor,fix4neurons,[NodeName,PidSender,PidAcc,PidEtsOwner,Tid,NeuronName2Pid_map]),
          io:format("~p~n",[NewNeuronName2Pid_map]),
                            ListPid = maps:values(NewNeuronName2Pid_map),
                            {NewLinkedPid,LinkedRef} = spawn_monitor(fun()->lists:foreach(fun(X)->link(X)end,ListPid), receive Y->Y end end),
                            supervisorEranLoop(NodeName,Pid_Server,EtsOwnerName,PidEtsOwner,EtsBackupName,PidBackup,PidTiming,PidSender,PidPlotGraph,PidAcc,NewNeuronName2Pid_map,NewLinkedPid,Tid);

        true -> fix
      end
  %PidPlotGraph = spawn_link(python_comm,plot_graph_process,[append_acc_vs_freq,plot_acc_vs_freq_global,[Start_freq]])
  end.

fix4neurons(NodeName,PidSender,PidAcc,PidEtsOwner,Tid,NeuronName2Pid_map) ->
  put(pid_data_sender,PidSender),
  put(pid_data_getter,PidAcc),
  PidAcc !zeroCounter,
  PidSender!wait,
  io:format("1~n"),
  {NewNeuronName2Pid_map,PidOldPidNewTuples}=fix_resonator_4stage(nonode, nonode, Tid,NeuronName2Pid_map),
  io:format("2~n"),
  lists:foreach(fun({Old,New})->rpc:call(NodeName,ets_statem,callChangePid,[PidEtsOwner,Old,New]) end,PidOldPidNewTuples),
  io:format("3~n"),
  neuron_statem:sendMessage(maps:get(afi1,NewNeuronName2Pid_map),maps:get(afi23,NewNeuronName2Pid_map),<<1>>,x),
  io:format("4~n"),
  PidSender!{stopWait,maps:get(afi1,NewNeuronName2Pid_map)}, %%dead lock???,
  io:format("5~n"),

  NewNeuronName2Pid_map.


fix_resonator_4stage(nonode, _, Tid,NeuronName2Pid_mapOLD) ->
  Neurons = [{afi1, #neuron_statem_state{etsTid=Tid,weightPar=[11,-9], biasPar=-1}},
    {afi21, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi22, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi23, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}}], % afi24, afi25, afi26, afi27,
  % afb1, afb2, afb3, afb4,
  % afi31, afi32, afi33, afi34],
  io:format("~p",[Neurons]),
  io:format("1.1~n"),

  NeuronName2Pid=lists:map(fun({Name, Record}) -> {ok,Pid}=neuron_statem:start_link(Name, Tid, {restore,Record,maps:get(Name,NeuronName2Pid_mapOLD)}), {Name, Pid} end, Neurons),
  %list neuron name -> pid
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  PidOldPidNewTuples = [{maps:get(X,NeuronName2Pid_mapOLD),maps:get(X,NeuronName2Pid_map)}||X <-maps:keys(NeuronName2Pid_map)],
  %todo:neuron_statem:pid_config(prev, next).
  io:format("1.2~n"),

  neuron_statem:pidConfig(maps:get(afi1,NeuronName2Pid_map), [enable,get(pid_data_sender),maps:get(afi23,NeuronName2Pid_map)],
    [maps:get(afi21, NeuronName2Pid_map),{finalAcc,get(pid_data_getter)}]),
  neuron_statem:pidConfig(maps:get(afi21,NeuronName2Pid_map), [enable,maps:get(afi1,NeuronName2Pid_map)],
    [maps:get(afi22, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi22,NeuronName2Pid_map), [enable,maps:get(afi21,NeuronName2Pid_map)],
    [maps:get(afi23, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi23,NeuronName2Pid_map), [enable,maps:get(afi22,NeuronName2Pid_map)],
    [maps:get(afi1, NeuronName2Pid_map)]),
  {NeuronName2Pid_map,PidOldPidNewTuples}.

%%%%%fix_resonator_4stage(nonode, _, Tid,Pid,NeuronName2Pid_map) ->
%%%%%  Pid2NeuronName_map=maps:from_list([{Y,X}||{X,Y}<-maps:to_list(NeuronName2Pid_map)]),
%%%%%  %%%% get the pid of the falling process
%%%%% Name = maps:get(Pid,Pid2NeuronName_map),
%%%%%  Neurons = [{afi1, #neuron_statem_state{etsTid=Tid,weightPar=[11,-9], biasPar=-1}},
%%%%%    {afi21, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
%%%%%    {afi22, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
%%%%%    {afi23, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}}], % afi24, afi25, afi26, afi27,
%%%%%  NeuronOldMap = maps:from_list(Neurons),
%%%%%  %%%% send other neurons to hold
%%%%%  lists:foreach(fun(X,Name) -> if X == Name ->doNothing; true-> neuron_statem:holdState(X) end end, maps:keys(NeuronOldMap)),
%%%%%  %%%% get neuron Record
%%%%%    Record = maps:get(Name,NeuronOldMap),
%%%%%  {ok,PidNew}=neuron_statem:start_link(Name, Tid, {restore,Record,Pid}), {Name, PidNew}
%%%%%
%%%%%  NeuronName2Pid=lists:map(fun({Name, Record}) -> {ok,Pid}=neuron_statem:start_link(Name, Tid, Record), {Name, Pid} end, Neurons),
%%%%%  %list neuron name -> pid
%%%%%  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
%%%%%  %todo:neuron_statem:pid_config(prev, next).
%%%%%  neuron_statem:pidConfig(maps:get(afi1,NeuronName2Pid_map), [enable,get(pid_data_sender),maps:get(afi23,NeuronName2Pid_map)],
%%%%%    [maps:get(afi21, NeuronName2Pid_map),{finalAcc,get(pid_data_getter)}]),
%%%%%  neuron_statem:pidConfig(maps:get(afi21,NeuronName2Pid_map), [enable,maps:get(afi1,NeuronName2Pid_map)],
%%%%%    [maps:get(afi22, NeuronName2Pid_map)]),
%%%%%  neuron_statem:pidConfig(maps:get(afi22,NeuronName2Pid_map), [enable,maps:get(afi21,NeuronName2Pid_map)],
%%%%%    [maps:get(afi23, NeuronName2Pid_map)]),
%%%%%  neuron_statem:pidConfig(maps:get(afi23,NeuronName2Pid_map), [enable,maps:get(afi22,NeuronName2Pid_map)],
%%%%%    [maps:get(afi1, NeuronName2Pid_map)]),
%%%%%  NeuronName2Pid_map;



%%spawn_neuron(Name) -> Pid = spawn_link(Node, neuron_statem, start_link/3, [Tid, #{}]), {Node, Tid})

%%%===================================================================
%%% Internal functions
%%%===================================================================
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
