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
  case whereis(shell) of
    undefined -> register(shell, self())
  end,
  spawn(fun()->neuron_supervisor:start(single_node, 200)end). %%104.649


%%% Node_Conc is single_node / four_nodes
start(Node_Conc, Frequency_Detect)->
  %Set as a system process
  process_flag(trap_exit, true),
  %% Open an ets heir and holders process in every Node
  %% Get messages with the Tid from ets processes.

  %% ====================
  %% INPUTS
  %% ====================
  put(start_freq, StartFreq=190),
  put(stop_freq, StopFreq=205),
  Nodes = case Node_Conc of
            four_nodes -> [node(),'eran@10.100.102.35','emm@10.100.102.35','yuda@10.100.102.35'];
            single_node -> [node()]
          end,
  %% ====================
  %% ETS
  %% ====================
  EtsBackupName = backup,
  EtsOwnerName = etsOwner,
  Self = self(),
  OpenEts =[neuron_supervisor:open_ets_satatem(Self,NodeName,EtsBackupName,EtsOwnerName)||NodeName<-Nodes],
  Tids = [Tid||{{_,_,_},Tid} <- OpenEts],

  %% ====================
  %% Open Processes
  %% ====================
  %% sender
  PidSender = spawn(pcm_handler,pdm_process,[40]),
  erlang:monitor(process,PidSender),
  put(pid_data_sender, PidSender),
  %% plot
  PidPlotGraph = spawn(python_comm,plot_graph_process,[append_acc_vs_freq,plot_acc_vs_freq_global,[StartFreq]]),
  erlang:monitor(process,PidPlotGraph),
  put(pid_plot_graph, PidPlotGraph),
  %% timing
  PidTiming = spawn(fun()->pcm_handler:timing_process(self())end),
  %% acc
  PidAcc = spawn(fun()->pcm_handler:acc_process_appendData(PidTiming,PidSender,PidPlotGraph)end),
  erlang:monitor(process,PidAcc),
  put(pid_acc,PidAcc),

  %% ====================
  %% Build Net
  %% ====================
  put(freq, Frequency_Detect+4),
  NeuronName2Pid_map = neuron_supervisor:start4neurons(Node_Conc, Nodes, Tids), % todo: edit start4neurons
  Samp = pcm_handler:create_wave_list(StartFreq,StopFreq,1),
  PidSender!{test_network, Samp},

  %% ====================
  io:format("supervisor ~p~n", [self()]),
  put(pdm_msg_number,0),
  ListPid = maps:values(NeuronName2Pid_map),
  %% monitor a process that links all of the neurons.
  {LinkedPid,LinkedRef} = spawn_monitor(fun()->lists:foreach(fun(X)->link(X)end,ListPid), receive Y->Y end end),
  {HeirPid,_}=spawn_monitor(fun()->protectionPid() end),
  HeirEts=ets:new(heir_ets,[set,public,{heir,HeirPid,'SupervisorDown'}]),
  ets:insert(HeirEts,[{pidTiming,PidTiming},{pidSender,PidSender},{pidPlotGraph,PidPlotGraph},
    {pidAcc,PidAcc},{neuronName2Pid_map,NeuronName2Pid_map},{linkedPid,LinkedPid},
    {nodes,Nodes}, {tids,Tids},{etsOwnerName,EtsOwnerName},
    {etsBackupName,EtsBackupName},{openEts,OpenEts}]),
  supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Nodes,Tids,EtsOwnerName,EtsBackupName,OpenEts,HeirEts,HeirPid).

supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Nodes,Tids,EtsOwnerName,EtsBackupName,OpenEts,HeirEts,HeirPid)->
  receive
    MessageDown={'DOWN', _, process, _, normal}-> nothing;
    MessageDown={'DOWN', Ref, process, Pid, Why}->
      io:format("~p~n",[MessageDown]),
      ValuePidEtsOwner = lists:search(fun({{_,PidEtsOwner,_},_}) ->PidEtsOwner==Pid end,OpenEts),
      io:format("~p~n",[ValuePidEtsOwner]),
      ValuePidBackup = lists:search(fun({{_,_,PidBackup},_}) ->PidBackup==Pid end,OpenEts),
      io:format("~p~n",[ValuePidBackup]),

      if Pid==HeirPid ->
        {NewHeirPid,_}=spawn_monitor(fun()->protectionPid() end),
        ets:setopts(HeirEts,{heir, NewHeirPid, 'SupervisorDown'}),
        supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Nodes,Tids,EtsOwnerName,EtsBackupName,OpenEts,HeirEts,NewHeirPid);

        ValuePidEtsOwner =/= false -> {value,{{NodeName,PidEtsOwner,PidBackup},Tid}} = ValuePidEtsOwner,
          Self=self(),
          {ok,PidBackNew} = rpc:call(NodeName,ets_statem,start,[EtsBackupName,Self,backup,none]),
          rpc:call(NodeName,ets_statem,callChangeHeir,[PidBackup,PidBackNew]),
          erlang:monitor(process,PidBackNew),
          NewOpenEts = lists:keyreplace(Tid, 2, OpenEts, {{NodeName,PidBackup,PidBackNew},Tid}),
          ets:insert(HeirEts,{openEts,NewOpenEts}),
          supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Nodes,Tids,EtsOwnerName,EtsBackupName,NewOpenEts,HeirEts,HeirPid);

        ValuePidBackup =/= false -> {value,{{NodeName,PidEtsOwner,PidBackup},Tid}} = ValuePidBackup,
          Self=self(),
          {ok,PidBackNew} = rpc:call(NodeName,ets_statem,start,[EtsBackupName,Self,backup,none]),
          rpc:call(NodeName,ets_statem,callChangeHeir,[PidEtsOwner,PidBackNew]),
          erlang:monitor(process,PidBackNew),
          NewOpenEts = lists:keyreplace(Tid, 2, OpenEts, {{NodeName,PidEtsOwner,PidBackNew},Tid}),
          ets:insert(HeirEts,{openEts,NewOpenEts}),
          supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Nodes,Tids,EtsOwnerName,EtsBackupName,NewOpenEts,HeirEts,HeirPid);

        Pid == LinkedPid ->
         NewNeuronName2Pid_map = neuron_supervisor:fix4neurons(Nodes, Tids,PidSender,PidAcc,EtsOwnerName,NeuronName2Pid_map),
         ets:insert(HeirEts,{neuronName2Pid_map,NewNeuronName2Pid_map}),
         io:format("~p~n",[NewNeuronName2Pid_map]),
         ListPid = maps:values(NewNeuronName2Pid_map),
         {NewLinkedPid,LinkedRef} = spawn_monitor(fun()->lists:foreach(fun(X)->link(X)end,ListPid), receive Y->Y end end),
          ets:insert(HeirEts,{linkedPid,NewLinkedPid}),
          supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,NewNeuronName2Pid_map,NewLinkedPid,Nodes,Tids,EtsOwnerName,EtsBackupName,OpenEts,HeirEts,HeirPid);

        Pid == PidSender -> Samp = pcm_handler:create_wave_list(get(start_freq),get(stop_freq),1),
          {_, SampRemaining}=lists:split(get(pdm_msg_number), Samp),
          PidSenderNew = spawn(pcm_handler,pdm_process,[40]),
          erlang:monitor(process,PidSenderNew),
          PidSenderNew!{config, kill_and_recover, self()},
          PidSenderNew! kill_and_recover, %% Waits for a wait message, and than the Pid name
          PidSenderNew! {test_network, SampRemaining},
          put(pid_data_sender,PidSenderNew),
          PidAcc!{set_pid_sender, PidSenderNew},
          ets:insert(HeirEts,[{pidSender,PidSenderNew}]),
          exit(LinkedPid, kill_and_recover),
          supervisor(PidTiming,PidSenderNew,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Nodes,Tids,EtsOwnerName,EtsBackupName,OpenEts, HeirEts,HeirPid);

        true -> io:format("process down not fix~p~n",[{'DOWN', Ref, process, Pid, Why}]),
          supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Nodes,Tids,EtsOwnerName,EtsBackupName,OpenEts, HeirEts,HeirPid)
      end;

    {from_pdm, NumberOfMessages}->
      put(pdm_msg_number,get(pdm_msg_number)+NumberOfMessages),
      supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Nodes,Tids,EtsOwnerName,EtsBackupName,OpenEts, HeirEts,HeirPid);

    {test_network,{StartFreq, StopFreq}}->
      put(start_freq, StartFreq),
      put(stop_freq, StopFreq),
      PidSender!{test_network, pcm_handler:create_wave_list(StartFreq,StopFreq,1)},
      supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Nodes,Tids,EtsOwnerName,EtsBackupName,OpenEts, HeirEts,HeirPid)
  end.


    %%   if Pid == PidBackup -> {ok,PidBackNew} = rpc:call(NodeName,ets_statem,start_link,[EtsBackupName,Pid_Server,backup,none]),
    %%   rpc:call(NodeName,ets_statem,callChangeHeir,[PidEtsOwner,PidBackNew]),
    %%   erlang:monitor(process,PidBackNew),
    %%   supervisorEranLoop(NodeName,Pid_Server,EtsOwnerName,PidEtsOwner,EtsBackupName,PidBackNew,PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Tid);
    %%   Pid == PidEtsOwner -> {ok,PidBackNew} = rpc:call(NodeName,ets_statem,start_link,[EtsBackupName,Pid_Server,backup,none]),
    %%     rpc:call(NodeName,ets_statem,callChangeHeir,[PidBackup,PidBackNew]),
    %%     erlang:monitor(process,PidBackNew),
    %%     supervisorEranLoop(NodeName,Pid_Server,EtsOwnerName,PidBackup,EtsBackupName,PidBackNew,PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Tid);
    %%   Pid == LinkedPid ->
    %%     NewNeuronName2Pid_map = rpc:call(NodeName,neuron_supervisor,fix4neurons,[NodeName,PidSender,PidAcc,PidEtsOwner,Tid,NeuronName2Pid_map]),
    %%     io:format("~p~n",[NewNeuronName2Pid_map]),
    %%     ListPid = maps:values(NewNeuronName2Pid_map),
    %%     {NewLinkedPid,LinkedRef} = spawn_monitor(fun()->lists:foreach(fun(X)->link(X)end,ListPid), receive Y->Y end end),
    %%     supervisorEranLoop(NodeName,Pid_Server,EtsOwnerName,PidEtsOwner,EtsBackupName,PidBackup,PidTiming,PidSender,PidPlotGraph,PidAcc,NewNeuronName2Pid_map,NewLinkedPid,Tid);

    %%   true -> fix
    %% end
  %PidPlotGraph = spawn_link(python_comm,plot_graph_process,[append_acc_vs_freq,plot_acc_vs_freq_global,[Start_freq]])

protectionPid()->
  receive
    {'ETS-TRANSFER',HeirEts,_,_}->PidTiming=ets:lookup(HeirEts,pidTiming),PidSender=ets:lookup(HeirEts,pidSender),
      PidPlotGraph=ets:lookup(HeirEts,pidPlotGraph),PidAcc=ets:lookup(HeirEts,pidAcc),NeuronName2Pid_map=ets:lookup(HeirEts,neuronName2Pid_map),
      LinkedPid=ets:lookup(HeirEts,linkedPid),Nodes=ets:lookup(HeirEts,nodes),Tids=ets:lookup(HeirEts,tids),
      EtsOwnerName=ets:lookup(HeirEts,etsOwnerName),EtsBackupName=ets:lookup(HeirEts,etsBackupName),OpenEts=ets:lookup(HeirEts,openEts),
      {HeirPid,_}=spawn_monitor(fun()->protectionPid() end),
      %erlang:monitor(process,PidSender),
      PidSender!{supervisor, self()},
      erlang:monitor(process,PidPlotGraph),
      erlang:monitor(process,PidAcc),
      ListPid = maps:values(NeuronName2Pid_map),
      {NewLinkedPid,_} = spawn_monitor(fun()->lists:foreach(fun(X)->link(X)end,ListPid), receive Y->Y end end),
      io:format("4.~n"),
      ets:setopts(HeirEts,{heir, HeirPid, 'SupervisorDown'}),
      supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,NewLinkedPid,Nodes,Tids,EtsOwnerName,EtsBackupName,OpenEts,HeirEts,HeirPid)
  end.
  %%,receive
  %%  Message={'EXIT',_, _} -> %% from linked pid (linked to all)
  %%    shell!Message,
  %%    exit(die_bitch)
  %%end.

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
%%start4neurons(Samp,Start_freq, Resonator_options) ->
%%  %% Get messages with the Tid from ets processes.
%%  EtsTid = gatherTid(EtsHolders, []),
%%
%%  % uses zip: [{Node, LayerSize, Tid},...]
%%  % list of {Node, [{Pid,{Node, Tid}},....]}
%%  NeuronListPerNode = lists:map(fun createLayerNeurons/1, lists:zip3(NodeNames, ListLayerSize, EtsTid)),
%%  net_connect(remove_info(NeuronListPerNode)),
%%  %% create two maps of pids.
%%  %% One by nodes and pids, and one by pids
%%  % Returns #{Node->#{Pid->{Node,Tid}}}
%%  MapsPerNode = maps:from_list(lists:map(fun({Node, List}) ->{Node, maps:from_list(List)} end, NeuronListPerNode)),
%%  put(pid_per_node, MapsPerNode),
%%  MapsOfPid = maps:from_list(sum_all_pid(NeuronListPerNode)),
%%  put(pid, MapsOfPid),
%%  put(nodes, NodeNames),
%%  supervisor().


%% Semp = pcm_handler:create_wave_list(100,115,1).
%% neuron_supervisor:start4neurons(Semp,100).
start4neurons(Resonator_options,Nodes, Tids) ->
  %pcm_handler:create_wave(Start_freq, End_freq, 1),
  io:format("here1~n"),
  PidTiming = spawn(fun()->pcm_handler:timing_process(self())end),
  PidSender= get(pid_data_sender), %= spawn_link(pcm_handler,pdm_process,[Samp, 40]),
                              %put(pid_data_sender,PidSender),
  PidPlotGraph = get(pid_plot_graph),%%spawn_link(python_comm,plot_graph_process,[append_acc_vs_freq,plot_acc_vs_freq_global,[Start_freq]]),
  PidAcc = get(pid_acc),%%spawn(fun()->pcm_handler:acc_process_appendData(PidTiming,PidSender,PidPlotGraph)end),
  io:format("here2~n"),
  put(pid_acc,PidAcc),
  NeuronName2Pid_map=  start_resonator_4stage(Resonator_options, Nodes, Tids),
  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),maps:get(afi23,NeuronName2Pid_map),<<1>>,x),
  PidSender ! {config, maps:get(afi1,NeuronName2Pid_map), self()},
  NeuronName2Pid_map.
%python_comm:plot_graph(plot_acc_vs_freq,["output_wave.pcm",Start_freq]).


start17neurons(Semp,Start_freq,Resonator_options,Nodes, Tids) ->
  io:format("here117~n"),
  PidTiming = spawn(fun()->pcm_handler:timing_process(self())end),
  PidSender = spawn_link(pcm_handler,pdm_process,[Semp, 40]),
  put(pid_data_sender,PidSender),
  PidPlotGraph = spawn_link(python_comm,plot_graph_process,[append_acc_vs_freq,plot_acc_vs_freq_global,[Start_freq]]),
  PidMsg = spawn(fun()->pcm_handler:msg_process(PidSender)end),
  PidAccMsg = spawn(fun()->pcm_handler:msgAcc_process( PidTiming,PidPlotGraph)end),
  io:format("here217~n"),
  put(pid_acc_msg,PidMsg),
  put(pid_data_getter,PidAccMsg),
  Tid = ets:new(neurons_data,[set,public]),
  NeuronName2Pid_map=  start_resonator_17stage(nonode, nonode, Tid),
  neuron_statem:sendMessage(maps:get(afi11,NeuronName2Pid_map),maps:get(afi14,NeuronName2Pid_map),<<1>>,x),
  PidSender ! maps:get(afi11,NeuronName2Pid_map).

start4neurons() ->
  %pcm_handler:create_wave(Start_freq, End_freq, 1),
  io:format("here1~n"),
  PidTiming = spawn(fun()->pcm_handler:timing_process(self())end),
  PidSender = spawn_link(pcm_handler,pdm_process,["input_wave_erl.pcm", 40]),
  put(pid_data_sender,PidSender),
  PidAcc = spawn(fun()->pcm_handler:acc_process("output_wave", PidTiming,PidSender)end),
  io:format("here2~n"),
  put(pid_acc,PidAcc),
  NeuronName2Pid_map=  start_resonator_4stage(nonode, nonode, nonode),
  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),maps:get(afi23,NeuronName2Pid_map),<<1>>,x),
  PidSender ! maps:get(afi1,NeuronName2Pid_map).
  %python_comm:plot_graph(plot_acc_vs_freq,["output_wave.pcm",Start_freq]).


start_resonator_4stage(single_node, [Node],[Tid]) ->
  Frequency_Detect=get(freq),
  LF = 5,
  LP =round((1.0)*(1.536*math:pow(10,6))/(Frequency_Detect*math:pow(2,LF)*2*math:pi())),
  Gain=math:pow(2,(2*LF-3))*(1+LP),
  Factor_Gain=(1.0)*9472/Gain,
  io:format("FG ~p, LP ~p", [Factor_Gain, LP]),

  Neurons = [{afi1, #neuron_statem_state{etsTid=Tid,weightPar=[11*Factor_Gain,-9*Factor_Gain], biasPar=-1*Factor_Gain, leakagePeriodPar = LP}},
    {afi21, #neuron_statem_state{etsTid=Tid,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}},
    {afi22, #neuron_statem_state{etsTid=Tid,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}},
    {afi23, #neuron_statem_state{etsTid=Tid,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}}],

  NeuronName2Pid=lists:map(fun({Name, Record}) ->
    {ok,Pid}=rpc:call(Node, neuron_statem, start, [Record]), {Name, Pid} end, Neurons),
  %list neuron name -> pid
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  neuron_statem:pidConfig(maps:get(afi1,NeuronName2Pid_map), [enable,get(pid_data_sender),maps:get(afi23,NeuronName2Pid_map)],
    [maps:get(afi21, NeuronName2Pid_map),{finalAcc,get(pid_acc)}]),
  neuron_statem:pidConfig(maps:get(afi21,NeuronName2Pid_map), [enable,maps:get(afi1,NeuronName2Pid_map)],
    [maps:get(afi22, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi22,NeuronName2Pid_map), [enable,maps:get(afi21,NeuronName2Pid_map)],
    [maps:get(afi23, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi23,NeuronName2Pid_map), [enable,maps:get(afi22,NeuronName2Pid_map)],
    [maps:get(afi1, NeuronName2Pid_map)]),
  NeuronName2Pid_map;

%% neuron_supervisor:start_resonator_4stage(fournodes, hi, bye).
start_resonator_4stage(four_nodes, Nodes, Tids) ->
  register(supervisor, self()),
  [Node1, Node2, Node3, Node4] = Nodes,
  [Tid1, Tid2, Tid3, Tid4] = Tids,
  Frequency_Detect=get(freq),
  LF = 5,
  LP =round((1.0)*(1.536*math:pow(10,6))/(Frequency_Detect*math:pow(2,LF)*2*math:pi())),
  Gain=math:pow(2,(2*LF-3))*(1+LP),
  Factor_Gain=(1.0)*9472/Gain,
  io:format("FG ~p, LP ~p", [Factor_Gain, LP]),
  %%% Start 4
  %%% statem neurons
  Neurons = [{afi1, #neuron_statem_state{etsTid=Tid1,weightPar=[11*Factor_Gain,-9*Factor_Gain], biasPar=-1*Factor_Gain, leakagePeriodPar = LP}, Node1},
    {afi21, #neuron_statem_state{etsTid=Tid2,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}, Node2},
    {afi22, #neuron_statem_state{etsTid=Tid3,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}, Node3},
    {afi23, #neuron_statem_state{etsTid=Tid4,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}, Node4}],

  NeuronName2Pid=lists:map(fun({Name, Record, Node}) ->
    {ok,Pid}=rpc:call(Node, neuron_statem, start, [Record]), {Name, Pid} end, Neurons),
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),

  %%%% using pid only
  %%%% rpc:call - start,
  %%% later will be linked to center process
  neuron_statem:pidConfig(maps:get(afi1,NeuronName2Pid_map), [enable,get(pid_data_sender),maps:get(afi23,NeuronName2Pid_map)],
    [maps:get(afi21, NeuronName2Pid_map),{finalAcc,get(pid_acc)}]),
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

  NeuronName2Pid_map.


fix4neurons([Node], [Tid],PidSender,PidAcc,EtsOwnerName,NeuronName2Pid_map) ->
  %put(pid_data_sender,PidSender),
  put(pid_data_getter,PidAcc),
  PidAcc !zeroCounter,
  PidSender!wait,
  {NewNeuronName2Pid_map,PidOldPidNewTuples}=fix_resonator_4stage(onenode, Node, Tid,NeuronName2Pid_map),
  lists:foreach(fun({{Old,New},NodeName})->rpc:call(NodeName,ets_statem,callChangePid,[EtsOwnerName,Old,New]) end,lists:zip(PidOldPidNewTuples,[Node,Node,Node,Node])),
  neuron_statem:sendMessage(maps:get(afi1,NewNeuronName2Pid_map),maps:get(afi23,NewNeuronName2Pid_map),<<1>>,x),
  PidSender!{stopWait,maps:get(afi1,NewNeuronName2Pid_map)},
  NewNeuronName2Pid_map;

fix4neurons(Nodes, Tids,PidSender,PidAcc,EtsOwnerName,NeuronName2Pid_map) ->
  put(pid_data_sender,PidSender),
  put(pid_data_getter,PidAcc),
  PidAcc !zeroCounter,
  PidSender!wait,
  io:format("1~n"),
  {NewNeuronName2Pid_map,PidOldPidNewTuples}=fix_resonator_4stage(fournodes, Nodes, Tids,NeuronName2Pid_map),
  io:format("2~n"),
  lists:foreach(fun({{Old,New},NodeName})->rpc:call(NodeName,ets_statem,callChangePid,[EtsOwnerName,Old,New]) end,lists:zip(PidOldPidNewTuples,Nodes)),
  io:format("3~n"),
  neuron_statem:sendMessage(maps:get(afi1,NewNeuronName2Pid_map),maps:get(afi23,NewNeuronName2Pid_map),<<1>>,x),
  io:format("4~n"),
  PidSender!{stopWait,maps:get(afi1,NewNeuronName2Pid_map)},
  io:format("5~n"),

  NewNeuronName2Pid_map.

fix_resonator_4stage(onenode, Node, Tid,NeuronName2Pid_mapOLD) ->

  Neurons = [{afi1, #neuron_statem_state{etsTid=Tid,weightPar=[11,-9], biasPar=-1}, Node},
    {afi21, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}, Node},
    {afi22, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}, Node},
    {afi23, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}, Node}],
  % afb1, afb2, afb3, afb4,
  % afi31, afi32, afi33, afi34],
  io:format("~p",[Neurons]),
  io:format("1.1~n"),

  NeuronName2Pid=lists:map(fun({Name, Record,Node}) -> {ok,Pid}=rpc:call(Node, neuron_statem, start, [{restore,Record,maps:get(Name,NeuronName2Pid_mapOLD)}]), {Name, Pid} end, Neurons),
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
  {NeuronName2Pid_map,PidOldPidNewTuples};

fix_resonator_4stage(fournodes, Nodes, Tids,NeuronName2Pid_mapOLD) ->
  [Node1, Node2, Node3, Node4] = Nodes,
  [Tid1, Tid2, Tid3, Tid4] = Tids,

  Neurons = [{afi1, #neuron_statem_state{etsTid=Tid1,weightPar=[11,-9], biasPar=-1}, Node1},
    {afi21, #neuron_statem_state{etsTid=Tid2,weightPar=[10], biasPar=-5}, Node2},
    {afi22, #neuron_statem_state{etsTid=Tid3,weightPar=[10], biasPar=-5}, Node3},
    {afi23, #neuron_statem_state{etsTid=Tid4,weightPar=[10], biasPar=-5}, Node4}],
  % afb1, afb2, afb3, afb4,
  % afi31, afi32, afi33, afi34],
  io:format("~p",[Neurons]),
  io:format("1.1~n"),

  NeuronName2Pid=lists:map(fun({Name, Record,Node}) -> {ok,Pid}=rpc:call(Node, neuron_statem, start, [{restore,Record,maps:get(Name,NeuronName2Pid_mapOLD)}]), {Name, Pid} end, Neurons),
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




start_resonator_17stage(nonode, nonode, Tid) ->
  Neurons = [{afi11, #neuron_statem_state{etsTid=Tid,weightPar=[11,-9], biasPar=-1}},
    {afi12, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi13, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi14, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi21, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi22, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi23, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi24, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afb1, #neuron_statem_state{etsTid=Tid, actTypePar = binaryStep, weightPar=[10], biasPar=-5}},
    {afb2, #neuron_statem_state{etsTid=Tid, actTypePar = binaryStep, weightPar=[10], biasPar=-5}},
    {afb3, #neuron_statem_state{etsTid=Tid, actTypePar = binaryStep, weightPar=[10], biasPar=-5}},
    {afb4, #neuron_statem_state{etsTid=Tid, actTypePar = binaryStep, weightPar=[10], biasPar=-5}},
    {afi31, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi32, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi33, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi34, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {sum, #neuron_statem_state{etsTid=Tid,weightPar=[6,6,6,6], biasPar=-12, leakagePeriodPar = 500}}],
  io:format("~p",[Neurons]),
  NeuronName2Pid=lists:map(fun({Name, Record}) -> {ok,Pid}=neuron_statem:start(Record), {Name, Pid} end, Neurons),
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  io:format("name to pid~p",[NeuronName2Pid_map]),
  neuron_statem:pidConfig(maps:get(afi11,NeuronName2Pid_map), [enable,get(pid_data_sender),maps:get(afi14,NeuronName2Pid_map)],
    [maps:get(afi12,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi12,NeuronName2Pid_map), [enable,maps:get(afi11,NeuronName2Pid_map)],
    [maps:get(afi13,NeuronName2Pid_map),maps:get(afi32,NeuronName2Pid_map),maps:get(afb2,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi13,NeuronName2Pid_map), [enable,maps:get(afi12,NeuronName2Pid_map)],
    [maps:get(afi14,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi14,NeuronName2Pid_map), [enable,maps:get(afi13,NeuronName2Pid_map)],
    [maps:get(afi11,NeuronName2Pid_map),maps:get(afi21,NeuronName2Pid_map),maps:get(afi33,NeuronName2Pid_map),maps:get(afb3,NeuronName2Pid_map)]),
        %%% , {msgControl,get(pid_acc_msg)}
  neuron_statem:pidConfig(maps:get(afi21,NeuronName2Pid_map), [enable,maps:get(afi14,NeuronName2Pid_map)],
    [maps:get(afi22,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi22,NeuronName2Pid_map), [enable,maps:get(afi21,NeuronName2Pid_map)],
    [maps:get(afi23,NeuronName2Pid_map),maps:get(afb4,NeuronName2Pid_map),maps:get(afi34,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi23,NeuronName2Pid_map), [enable,maps:get(afi22,NeuronName2Pid_map)],
    [maps:get(afi24,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi24,NeuronName2Pid_map), [enable,maps:get(afi23,NeuronName2Pid_map)],
    [maps:get(afb1,NeuronName2Pid_map),maps:get(afi31,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afb1,NeuronName2Pid_map), [enable,maps:get(afi24,NeuronName2Pid_map)],
    [maps:get(afi31,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afb2,NeuronName2Pid_map), [enable,maps:get(afi12,NeuronName2Pid_map)],
    [maps:get(afi32,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afb3,NeuronName2Pid_map), [enable,maps:get(afi14,NeuronName2Pid_map)],
    [maps:get(afi33,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afb4,NeuronName2Pid_map), [enable,maps:get(afi22,NeuronName2Pid_map)],
    [maps:get(afi34,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi31,NeuronName2Pid_map), [maps:get(afb1,NeuronName2Pid_map),maps:get(afi24,NeuronName2Pid_map)],
    [maps:get(sum,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi32,NeuronName2Pid_map), [maps:get(afb2,NeuronName2Pid_map),maps:get(afi12,NeuronName2Pid_map)],
    [maps:get(sum,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi33,NeuronName2Pid_map), [maps:get(afb3,NeuronName2Pid_map),maps:get(afi14,NeuronName2Pid_map)],
    [maps:get(sum,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi34,NeuronName2Pid_map), [maps:get(afb4,NeuronName2Pid_map),maps:get(afi22,NeuronName2Pid_map)],
    [maps:get(sum,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(sum,NeuronName2Pid_map), [enable,maps:get(afi31,NeuronName2Pid_map),maps:get(afi32,NeuronName2Pid_map),maps:get(afi33,NeuronName2Pid_map),maps:get(afi34,NeuronName2Pid_map)],
    [{finalAcc,get(pid_data_getter)},{msgControl,get(pid_acc_msg)}]),

  NeuronName2Pid_map.










        
tryTwoNodes(Node1,Node2,Tid)->
  Record1 = #neuron_statem_state{etsTid=Tid,weightPar=[11]},
  Record2 = #neuron_statem_state{etsTid=Tid,weightPar=[11]},
  {ok,Pid1}= rpc:call(Node1,neuron_statem,start_link,[afi1, Tid, Record1]),
  {ok,Pid2} = rpc:call(Node2,neuron_statem,start_link,[n2, Tid, Record2]),
  neuron_statem:pidConfig(afi1, [enable,get(pid_data_sender)], [n2]),
  neuron_statem:pidConfig(n2, [enable,Pid1], [maps:get(afi22, {finalAcc,get(pid_data_getter)})]).


open_ets_satatem(Pid_Server,NodeName,EtsBackupName,EtsOwnerName)->
  {ok,PidBackup} = rpc:call(NodeName,ets_statem,start,[EtsBackupName,Pid_Server,backup,none]),
  erlang:monitor(process,PidBackup),
  {ok,PidEtsOwner} =  rpc:call(NodeName,ets_statem,start,[EtsOwnerName,Pid_Server,etsOwner,PidBackup]),
  erlang:monitor(process,PidEtsOwner),
  receive
    {{Node,PidEtsOwner},Tid} ->io:format("open~n"),
      {{Node,PidEtsOwner,PidBackup},Tid}
  end.

%%%% Debugging adi
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
      if Pid == PidBackup -> {ok,PidBackNew} = rpc:call(NodeName,ets_statem,start,[EtsBackupName,Pid_Server,backup,none]),
                             rpc:call(NodeName,ets_statem,callChangeHeir,[PidEtsOwner,PidBackNew]),
                              erlang:monitor(process,PidBackNew),
                            supervisorEranLoop(NodeName,Pid_Server,EtsOwnerName,PidEtsOwner,EtsBackupName,PidBackNew,PidTiming,PidSender,PidPlotGraph,PidAcc,NeuronName2Pid_map,LinkedPid,Tid);
        Pid == PidEtsOwner -> {ok,PidBackNew} = rpc:call(NodeName,ets_statem,start,[EtsBackupName,Pid_Server,backup,none]),
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


%%fix4neurons(NodeName,PidSender,PidAcc,PidEtsOwner,Tid,NeuronName2Pid_map) ->
%%  put(pid_data_sender,PidSender),
%%  put(pid_data_getter,PidAcc),
%%  PidAcc !zeroCounter,
%%  PidSender!wait,
%%  io:format("1~n"),
%%  {NewNeuronName2Pid_map,PidOldPidNewTuples}=fix_resonator_4stage(nonode, nonode, Tid,NeuronName2Pid_map),
%%  io:format("2~n"),
%%  lists:foreach(fun({Old,New})->rpc:call(NodeName,ets_statem,callChangePid,[PidEtsOwner,Old,New]) end,PidOldPidNewTuples),
%%  io:format("3~n"),
%%  neuron_statem:sendMessage(maps:get(afi1,NewNeuronName2Pid_map),maps:get(afi23,NewNeuronName2Pid_map),<<1>>,x),
%%  io:format("4~n"),
%%  PidSender!{stopWait,maps:get(afi1,NewNeuronName2Pid_map)}, %%dead lock???,
%%  io:format("5~n"),
%%
%%  NewNeuronName2Pid_map.
%%
%%
%%fix_resonator_4stage(nonode, _, Tid,NeuronName2Pid_mapOLD) ->
%%  Neurons = [{afi1, #neuron_statem_state{etsTid=Tid,weightPar=[11,-9], biasPar=-1}},
%%    {afi21, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
%%    {afi22, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
%%    {afi23, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}}], % afi24, afi25, afi26, afi27,
%%  % afb1, afb2, afb3, afb4,
%%  % afi31, afi32, afi33, afi34],
%%  io:format("~p",[Neurons]),
%%  io:format("1.1~n"),
%%
%%  NeuronName2Pid=lists:map(fun({Name, Record}) -> {ok,Pid}=neuron_statem:start_link(Name, {restore,Record,maps:get(Name,NeuronName2Pid_mapOLD)}), {Name, Pid} end, Neurons),
%%  %list neuron name -> pid
%%  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
%%  PidOldPidNewTuples = [{maps:get(X,NeuronName2Pid_mapOLD),maps:get(X,NeuronName2Pid_map)}||X <-maps:keys(NeuronName2Pid_map)],
%%  %todo:neuron_statem:pid_config(prev, next).
%%  io:format("1.2~n"),
%%
%%  neuron_statem:pidConfig(maps:get(afi1,NeuronName2Pid_map), [enable,get(pid_data_sender),maps:get(afi23,NeuronName2Pid_map)],
%%    [maps:get(afi21, NeuronName2Pid_map),{finalAcc,get(pid_data_getter)}]),
%%  neuron_statem:pidConfig(maps:get(afi21,NeuronName2Pid_map), [enable,maps:get(afi1,NeuronName2Pid_map)],
%%    [maps:get(afi22, NeuronName2Pid_map)]),
%%  neuron_statem:pidConfig(maps:get(afi22,NeuronName2Pid_map), [enable,maps:get(afi21,NeuronName2Pid_map)],
%%    [maps:get(afi23, NeuronName2Pid_map)]),
%%  neuron_statem:pidConfig(maps:get(afi23,NeuronName2Pid_map), [enable,maps:get(afi22,NeuronName2Pid_map)],
%%    [maps:get(afi1, NeuronName2Pid_map)]),
%%  {NeuronName2Pid_map,PidOldPidNewTuples}.
%%
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


%%%debugResonator_4stage() ->
%%%  Tid = ets:new(neurons_data,[set,public]),
%%%  Self = self(),
%%%  put(pid_data_sender,Self),
%%%  NeuronName2Pid_map = start_resonator_4stage(nonode,nonode),
%%%  receive
%%%  after 10000 -> io:format("\n\nend wait ~p\n\n",[NeuronName2Pid_map])
%%%  end,
%%%  io:format("finish config!!!!!!!!!!!!!"),
%%%  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),get(pid_data_sender),<<1>>,x),
%%%  receive
%%%    X -> io:format("1.got ------  ~p\n",[X])
%%%  after 1000 -> io:format("1.not got\n")
%%%  end,
%%%  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),maps:get(afi23,NeuronName2Pid_map),<<1>>,x),
%%%  receive
%%%    Y -> io:format("2.got ------  ~p\n",[Y])
%%%  after 1000 -> io:format("2.not got\n")
%%%  end,
%%%  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),get(pid_data_sender),<<1>>,x),
%%%  receive
%%%    Z -> io:format("3.got ------  ~p\n",[Z])
%%%  after 1000 -> io:format("3.not got\n")
%%%  end,
%%%  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),get(pid_data_sender),<<0>>,x),
%%%  receive
%%%    K-> io:format("3.got ------  ~p\n",[K])
%%%  after 1000 -> io:format("3.not got\n")
%%%  end.
