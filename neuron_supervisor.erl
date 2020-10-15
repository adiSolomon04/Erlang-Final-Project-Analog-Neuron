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
-export([start/5, init/5, start4neurons/3, start17neurons/3, fix4neurons/4, fix17neurons/4, open_ets_satatem/2]).

  %% record for neuron init.
-record(neuron_statem_state, {etsTid, actTypePar=identity,weightPar,biasPar=0,leakageFactorPar=5,leakagePeriodPar=73,pidIn=[],pidOut=[]}).

%%%===================================================================
%%%  Supervisor
%%%===================================================================


start(Node_Conc, Net_Size, Nodes, Frequency_Detect, Sup_Name)->
  spawn(fun()->neuron_supervisor:init(Node_Conc, Net_Size, Nodes, Frequency_Detect, Sup_Name)end).


%%% Node_Conc is single_node / four_nodes
init(Node_Conc, Net_Size, Nodes, Frequency_Detect, Sup_Name)->
  %Set as a system process
  process_flag(trap_exit, true),
  %% Open an ets heir and holders process in every Node
  %% Get messages with the Tid from ets processes.

  %% ====================
  %% INPUTS
  %% ====================
  put(freq_detect, Frequency_Detect),
  put(start_freq, 0),
  put(stop_freq, 0),
  put(net_size, Net_Size),
  put(sup_Name, Sup_Name),
  %% ====================
  %% ETS
  %% ====================

  Self = self(),
  OpenEts =[neuron_supervisor:open_ets_satatem(Self,NodeName)||NodeName<-Nodes],
  Tids = [Tid||{{_,_,_},Tid} <- OpenEts],
  MapNodesToPidOwners = maps:from_list([{Node,PidEtsOwner}||{{Node,PidEtsOwner,_},_} <- OpenEts]),
  %% ====================
  %% Open Processes
  %% ====================
  %% sender
  PidSender = spawn(pcm_handler,pdm_process,[40]),
  erlang:monitor(process,PidSender),
  put(pid_data_sender, PidSender),
  %% plot
  PidPlotGraph = spawn(python_comm,plot_graph_process,[append_acc_vs_freq,plot_acc_vs_freq_global,Sup_Name]), %% todo:add startFreq to global in python
  erlang:monitor(process,PidPlotGraph),
  put(pid_plot_graph, PidPlotGraph),
  %% timing
  PidTiming = spawn(fun()->pcm_handler:timing_process(self())end),
  %% acc
  PidAcc = case Net_Size of
             4 -> spawn(fun()->pcm_handler:acc_process_appendData(PidTiming,PidSender,PidPlotGraph)end);
             17 -> spawn(fun()->pcm_handler:msgAcc_process( PidTiming,PidPlotGraph)end)
           end,
  erlang:monitor(process,PidAcc),
  put(pid_acc,PidAcc),
  %% msg (for 17 neurons)
  PidMsg = case Net_Size of
             4 -> none;
             17 ->
               Pid = spawn(fun()->pcm_handler:msg_process(PidSender)end),
               erlang:monitor(process,Pid),
               put(pid_msg,Pid),
               Pid
           end,


  %% ====================
  %% Build Net
  %% ====================
  NeuronName2Pid_map = case Net_Size of
                         4  -> neuron_supervisor:start4neurons(Node_Conc, Nodes, Tids);
                         17 -> neuron_supervisor:start17neurons(Node_Conc, Nodes, Tids)
                       end,

  %% ====================
  put(pdm_msg_number,0),
  ListPid = maps:values(NeuronName2Pid_map),
  %% monitor a process that links all of the neurons.
  {LinkedPid,_} = spawn_monitor(fun()->lists:foreach(fun(X)->link(X)end,ListPid), receive Y->Y end end),
  {HeirPid,_}=spawn_monitor(fun()->protectionPid() end),
  HeirEts=ets:new(heir_ets,[set,public,{heir,HeirPid,'SupervisorDown'}]),
  ets:insert(HeirEts,[{pidTiming,PidTiming},{pidSender,PidSender},{pidPlotGraph,PidPlotGraph},
    {pidAcc,PidAcc},{neuronName2Pid_map,NeuronName2Pid_map},{linkedPid,LinkedPid},
    {nodes,Nodes}, {tids,Tids},{mapNodesToPidOwnersNew,MapNodesToPidOwners},
    {openEts,OpenEts},{netSize, Net_Size},{pidMsg,PidMsg},{node_Conc,Node_Conc}, {frequency_Detect,Frequency_Detect},
    {pdm_msg_number,0},{start_freq, not_started},{stop_freq, not_started},{sup_Name, Sup_Name}]),
  supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,PidMsg,NeuronName2Pid_map,LinkedPid,Nodes,Tids,MapNodesToPidOwners,OpenEts,HeirEts,HeirPid).

%% The main function, the supervisor process receives different messages and calls the appropriate functions to handle the situation
supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,PidMsg,NeuronName2Pid_map,LinkedPid,Nodes,Tids,MapNodesToPidOwners,OpenEts,HeirEts,HeirPid)->
  receive
    {'DOWN', _, process, _, normal}->  exit(HeirPid,kill),nothing;
    'NODEDOWN'->checkNodesConnected(Nodes),exit(PidTiming, kill_and_start_over),
      exit(PidSender, kill_and_start_over),
      exit(PidPlotGraph, kill_and_start_over),
      exit(PidAcc, kill_and_start_over),
      exit(PidMsg, kill_and_start_over),
      exit(LinkedPid, kill_and_start_over),
      exit(HeirPid, kill_and_start_over),
      lists:foreach(fun({{_,PidEtsOwner,PidBackup},_}) ->  exit(PidEtsOwner, kill_and_start_over),exit(PidBackup, kill_and_start_over) end , OpenEts),
      flushKillMSG();
    {'DOWN', _, process, Pid, _}->
      Check=checkNodesConnected(Nodes),
      if
        Check==false -> exit(PidTiming, kill_and_start_over),
          exit(PidSender, kill_and_start_over),
          exit(PidPlotGraph, kill_and_start_over),
          exit(PidAcc, kill_and_start_over),
          exit(PidMsg, kill_and_start_over),
          exit(LinkedPid, kill_and_start_over),
          exit(HeirPid, kill_and_start_over),
          lists:foreach(fun({{_,PidEtsOwner,PidBackup},_}) ->  exit(PidEtsOwner, kill_and_start_over),exit(PidBackup, kill_and_start_over) end , OpenEts),
          flushKillMSG() ;
        true ->

      ValuePidEtsOwner = lists:search(fun({{_,PidEtsOwner,_},_}) ->PidEtsOwner==Pid end,OpenEts),
      ValuePidBackup = lists:search(fun({{_,_,PidBackup},_}) ->PidBackup==Pid end,OpenEts),

      if Pid==HeirPid ->
        {NewHeirPid,_}=spawn_monitor(fun()->protectionPid() end),
        ets:setopts(HeirEts,{heir, NewHeirPid, 'SupervisorDown'}),
        supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,PidMsg,NeuronName2Pid_map,LinkedPid,Nodes,Tids,MapNodesToPidOwners,OpenEts,HeirEts,NewHeirPid);

        ValuePidEtsOwner =/= false -> {value,{{NodeName,_,PidBackup},Tid}} = ValuePidEtsOwner,
          Self=self(),
          {ok,PidBackNew} = rpc:call(NodeName,ets_statem,start,[Self,backup,none]),
          rpc:call(NodeName,ets_statem,callChangeHeir,[PidBackup,PidBackNew]),
          erlang:monitor(process,PidBackNew),
          NewOpenEts = lists:keyreplace(Tid, 2, OpenEts, {{NodeName,PidBackup,PidBackNew},Tid}),
          MapNodesToPidOwnersNew = maps:update(NodeName,PidBackup,MapNodesToPidOwners),
          ets:insert(HeirEts,{openEts,NewOpenEts}),
          ets:insert(HeirEts,{mapNodesToPidOwnersNew,MapNodesToPidOwnersNew}),
          supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,PidMsg,NeuronName2Pid_map,LinkedPid,Nodes,Tids,MapNodesToPidOwnersNew,NewOpenEts,HeirEts,HeirPid);

        ValuePidBackup =/= false -> {value,{{NodeName,PidEtsOwner,_},Tid}} = ValuePidBackup,
          Self=self(),
          {ok,PidBackNew} = rpc:call(NodeName,ets_statem,start,[Self,backup,none]),
          rpc:call(NodeName,ets_statem,callChangeHeir,[PidEtsOwner,PidBackNew]),
          erlang:monitor(process,PidBackNew),
          NewOpenEts = lists:keyreplace(Tid, 2, OpenEts, {{NodeName,PidEtsOwner,PidBackNew},Tid}),
          ets:insert(HeirEts,{openEts,NewOpenEts}),
          supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,PidMsg,NeuronName2Pid_map,LinkedPid,Nodes,Tids,MapNodesToPidOwners,NewOpenEts,HeirEts,HeirPid);

        Pid == LinkedPid ->
         NewNeuronName2Pid_map = case get(net_size) of
                                   4 -> neuron_supervisor:fix4neurons(Nodes, Tids, MapNodesToPidOwners,NeuronName2Pid_map);
                                   17 -> neuron_supervisor:fix17neurons(Nodes, Tids, MapNodesToPidOwners,NeuronName2Pid_map)
                                 end,
         ets:insert(HeirEts,{neuronName2Pid_map,NewNeuronName2Pid_map}),
         ListPid = maps:values(NewNeuronName2Pid_map),
         {NewLinkedPid,_} = spawn_monitor(fun()->lists:foreach(fun(X)->link(X)end,ListPid), receive Y->Y end end),
          ets:insert(HeirEts,{linkedPid,NewLinkedPid}),
          supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,PidMsg,NewNeuronName2Pid_map,NewLinkedPid,Nodes,Tids,MapNodesToPidOwners,OpenEts,HeirEts,HeirPid);

        Pid == PidSender -> Start=get(start_freq), Stop=get(stop_freq),
          PidSenderNew = spawn(pcm_handler,pdm_process,[40]),
          erlang:monitor(process,PidSenderNew),
          PidSenderNew!{config, kill_and_recover, self()},
          PidSenderNew! kill_and_recover, %% Waits for a wait message, and than the Pid name
          if Start=/=0, Stop=/=0 ->
            Samp = pcm_handler:create_wave_list(Start,Stop,1),
            {_, SampRemaining}=lists:split(get(pdm_msg_number), Samp),
            PidSenderNew! {test_network, SampRemaining};
            true -> dont_send
          end,
          put(pid_data_sender,PidSenderNew),
          case get(net_size) of
            4 -> PidAcc!{set_pid_sender, PidSenderNew};
            17 -> PidMsg!{set_pid_sender, PidSenderNew}
          end,

          ets:insert(HeirEts,[{pidSender,PidSenderNew}]),
          exit(LinkedPid, kill_and_recover),
          supervisor(PidTiming,PidSenderNew,PidPlotGraph,PidAcc,PidMsg,NeuronName2Pid_map,LinkedPid,Nodes,Tids,MapNodesToPidOwners,OpenEts, HeirEts,HeirPid);
        Pid == PidMsg -> PidMsgNew = spawn(fun()->pcm_handler:msg_process(PidSender)end),
          erlang:monitor(process,PidMsgNew),
          put(pid_msg,PidMsgNew),
          ets:insert(HeirEts,{pidMsg,PidMsgNew}),
          exit(LinkedPid, kill_and_recover),
          supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,PidMsgNew,NeuronName2Pid_map,LinkedPid,Nodes,Tids,MapNodesToPidOwners,OpenEts, HeirEts,HeirPid);
        Pid == PidPlotGraph ; Pid == PidAcc ->
            exit(PidTiming, kill_and_start_over),
            exit(PidSender, kill_and_start_over),
            exit(PidPlotGraph, kill_and_start_over),
            exit(PidAcc, kill_and_start_over),
            exit(PidMsg, kill_and_start_over),
            exit(LinkedPid, kill_and_start_over),
            exit(HeirPid, kill_and_start_over),

            lists:foreach(fun({{_,PidEtsOwner,PidBackup},_}) ->  exit(PidEtsOwner, kill_and_start_over),exit(PidBackup, kill_and_start_over) end , OpenEts),
            flushKillMSG(),
            [{node_Conc,Node_Conc}]=ets:lookup(HeirEts,node_Conc),
            [{netSize,Net_Size}]=ets:lookup(HeirEts,netSize),
            [{frequency_Detect,Frequency_Detect}]=ets:lookup(HeirEts,frequency_Detect),
            ets:delete(HeirEts),
            self()!{test_network, {get(start_freq), get(stop_freq)}},
            neuron_supervisor:init(Node_Conc, Net_Size, Nodes, Frequency_Detect, get(sup_name));
        true ->
          supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,PidMsg,NeuronName2Pid_map,LinkedPid,Nodes,Tids,MapNodesToPidOwners,OpenEts, HeirEts,HeirPid)
      end end;

    {from_pdm, NumberOfMessages}->
      put(pdm_msg_number,get(pdm_msg_number)+NumberOfMessages),
      ets:insert(HeirEts,{pdm_msg_number,get(pdm_msg_number)}),
      supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,PidMsg,NeuronName2Pid_map,LinkedPid,Nodes,Tids,MapNodesToPidOwners,OpenEts, HeirEts,HeirPid);

    {test_network,{StartFreq, StopFreq}}->
      erlang:display("got test_network"),
      %%todo:add startFreq to global in python. call from here.
      ets:insert(HeirEts,{start_freq, StartFreq}),
      ets:insert(HeirEts,{stop_freq, StopFreq}),
      put(start_freq, StartFreq),
      put(stop_freq, StopFreq),
      PidPlotGraph!{start_freq, StartFreq},
      PidSender!{test_network, pcm_handler:create_wave_list(StartFreq,StopFreq,1)},
      supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,PidMsg,NeuronName2Pid_map,LinkedPid,Nodes,Tids,MapNodesToPidOwners,OpenEts, HeirEts,HeirPid)
  end .



flushKillMSG()->
  receive
    _->flushKillMSG()
    after 100->ok
  end.

checkNodesConnected(Nodes)->
  lists:all(fun(X)-> pong == net_adm:ping(X) end,Nodes).

protectionPid()->
  receive
    {'ETS-TRANSFER',HeirEts,_,_}->[{pidTiming,PidTiming}]=ets:lookup(HeirEts,pidTiming),[{pidSender,PidSender}]=ets:lookup(HeirEts,pidSender),
      [{pidPlotGraph,PidPlotGraph}]=ets:lookup(HeirEts,pidPlotGraph),[{pidAcc,PidAcc}]=ets:lookup(HeirEts,pidAcc),
      [{pidMsg,PidMsg}]=ets:lookup(HeirEts,pidMsg),[{neuronName2Pid_map,NeuronName2Pid_map}]=ets:lookup(HeirEts,neuronName2Pid_map),
      [{linkedPid,_}]=ets:lookup(HeirEts,linkedPid),[{nodes,Nodes}]=ets:lookup(HeirEts,nodes),[{tids,Tids}]=ets:lookup(HeirEts,tids),
      [{mapNodesToPidOwnersNew,MapNodesToPidOwnersNew}]=ets:lookup(HeirEts,mapNodesToPidOwnersNew),[{openEts,OpenEts}]=ets:lookup(HeirEts,openEts),
      [{netSize,Net_Size}]=ets:lookup(HeirEts,netSize), [{pdm_msg_number,Pdm_msg_number}] = ets:lookup(HeirEts,pdm_msg_number),
      [{start_freq, StartFreq}] = ets:lookup(HeirEts,start_freq), [{stop_freq, StopFreq}] =  ets:lookup(HeirEts,stop_freq),
      [{frequency_Detect,Frequency_Detect}] = ets:lookup(HeirEts,frequency_Detect), [{sup_Name, Sup_Name}]=ets:lookup(HeirEts,sup_Name),

      put(net_size, Net_Size),
      put(sup_Name, Sup_Name),
      put(start_freq, StartFreq),
      put(stop_freq, StopFreq),
      put(pid_data_sender, PidSender),
      put(pid_plot_graph, PidPlotGraph),
      put(pid_acc,PidAcc),
      put(freq_detect, Frequency_Detect),
      put(pdm_msg_number,Pdm_msg_number),
      put(pid_msg,PidMsg),
      {HeirPid,_}=spawn_monitor(fun()->protectionPid() end),
      erlang:monitor(process,PidSender),
      PidSender!{supervisor, self()},
      erlang:monitor(process,PidPlotGraph),
      erlang:monitor(process,PidAcc),
      ListPid = maps:values(NeuronName2Pid_map),
      {NewLinkedPid,_} = spawn_monitor(fun()->lists:foreach(fun(X)->link(X)end,ListPid), receive Y->Y end end),
      ets:setopts(HeirEts,{heir, HeirPid, 'SupervisorDown'}),
      supervisor(PidTiming,PidSender,PidPlotGraph,PidAcc,PidMsg,NeuronName2Pid_map,NewLinkedPid,Nodes,Tids,MapNodesToPidOwnersNew,OpenEts,HeirEts,HeirPid)
  end.

%% pdm to sleep.
%% 17 process destroy.
%% Reset Msg queue.

%%%===================================================================
%%%  Neurons Launcher
%%%===================================================================

start4neurons(Resonator_options,Nodes, Tids) ->
  NeuronName2Pid_map=  start_resonator_4stage(Resonator_options, Nodes, Tids),
  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),maps:get(afi23,NeuronName2Pid_map),<<1>>,x),
  get(pid_data_sender) ! {config, maps:get(afi1,NeuronName2Pid_map), self()},
  erlang:display("network configured"),
  NeuronName2Pid_map.


start17neurons(Node_Conc,Nodes, Tids) ->
  NeuronName2Pid_map=  start_resonator_17stage(Node_Conc, Nodes, Tids),
  neuron_statem:sendMessage(maps:get(afi11,NeuronName2Pid_map),maps:get(afi14,NeuronName2Pid_map),<<1>>,x),
  get(pid_data_sender) ! {config, maps:get(afi11,NeuronName2Pid_map), self()},
  erlang:display("network configured"),
  NeuronName2Pid_map.

%%%===================================================================
%%%  Build Resonator
%%%===================================================================
start_resonator_4stage(single_node, [Node],[Tid]) ->
  Neurons = get_4_neurons([], [Tid]),
  NeuronName2Pid=lists:map(fun({Name, Record}) ->
    {ok,Pid}=rpc:call(Node, neuron_statem, start, [Record]), {Name, Pid} end, Neurons),
  %list neuron name -> pid
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  pidConfig4(NeuronName2Pid_map),
  NeuronName2Pid_map;

start_resonator_4stage(four_nodes, Nodes, Tids) ->
  Neurons = get_4_neurons(Nodes, Tids),
  NeuronName2Pid=lists:map(fun({Name, Record, Node}) ->
    {ok,Pid}=rpc:call(Node, neuron_statem, start, [Record]), {Name, Pid} end, Neurons),
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),

  pidConfig4(NeuronName2Pid_map),
  NeuronName2Pid_map.

start_resonator_17stage(single_node, [Node], [Tid]) ->
  Neurons = get_17_neurons([], [Tid]),
  NeuronName2Pid=lists:map(fun({Name, Record}) ->
    {ok,Pid}=rpc:call(Node, neuron_statem, start, [Record]), {Name, Pid} end, Neurons),
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  pidConfig17(NeuronName2Pid_map),
  NeuronName2Pid_map;
start_resonator_17stage(four_nodes, Nodes, Tids) ->
  Neurons = get_17_neurons(Nodes, Tids),
  NeuronName2Pid=lists:map(fun({Name, Record, Node}) ->
  {ok,Pid}=rpc:call(Node, neuron_statem, start, [Record]), {Name, Pid} end, Neurons),
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  pidConfig17(NeuronName2Pid_map),
  NeuronName2Pid_map.


%%%===================================================================
%%%  Fix Network
%%%===================================================================

fix4neurons([Node], [Tid], MapNodesToPidOwners, NeuronName2Pid_map) ->
  get(pid_acc)!zeroCounter,
  get(pid_data_sender)!wait,
  {NewNeuronName2Pid_map,PidOldPidNewTuples}=fix_resonator_4stage(onenode, Node, Tid,NeuronName2Pid_map),
  lists:foreach(fun({{Old,New},NodeName})->rpc:call(NodeName,ets_statem,callChangePid,[maps:get(NodeName,MapNodesToPidOwners),Old,New]) end,lists:zip(PidOldPidNewTuples,[Node,Node,Node,Node])),
  neuron_statem:sendMessage(maps:get(afi1,NewNeuronName2Pid_map),maps:get(afi23,NewNeuronName2Pid_map),<<1>>,x),
  get(pid_data_sender)!{stopWait,maps:get(afi1,NewNeuronName2Pid_map)},
  NewNeuronName2Pid_map;

fix4neurons(Nodes, Tids,MapNodesToPidOwners,NeuronName2Pid_map) ->
  get(pid_acc)!zeroCounter,
  get(pid_data_sender)!wait,
  {NewNeuronName2Pid_map,PidOldPidNewTuples}=fix_resonator_4stage(fournodes, Nodes, Tids,NeuronName2Pid_map),
  lists:foreach(fun({{Old,New},NodeName})->rpc:call(NodeName,ets_statem,callChangePid,[maps:get(NodeName,MapNodesToPidOwners),Old,New]) end,lists:zip(PidOldPidNewTuples,Nodes)),
  neuron_statem:sendMessage(maps:get(afi1,NewNeuronName2Pid_map),maps:get(afi23,NewNeuronName2Pid_map),<<1>>,x),
  get(pid_data_sender)!{stopWait,maps:get(afi1,NewNeuronName2Pid_map)},
  NewNeuronName2Pid_map.


fix17neurons([Node], [Tid], MapNodesToPidOwners, NeuronName2Pid_map) ->
  get(pid_msg)!zeroCounter,
  get(pid_data_sender)!wait,
  {NewNeuronName2Pid_map,PidOldPidNewTuples}=fix_resonator_17stage(onenode, Node, Tid, NeuronName2Pid_map),
  lists:foreach(fun({{Old,New},NodeName})->rpc:call(NodeName,ets_statem,callChangePid,[maps:get(NodeName,MapNodesToPidOwners),Old,New]) end,
    lists:zip(PidOldPidNewTuples,lists:map(fun(_)->Node end, lists:seq(1,17)))),
  neuron_statem:sendMessage(maps:get(afi11,NewNeuronName2Pid_map),maps:get(afi14,NewNeuronName2Pid_map),<<1>>,x),
  get(pid_data_sender)!{stopWait,maps:get(afi11,NewNeuronName2Pid_map)},
  NewNeuronName2Pid_map;

fix17neurons(Nodes, Tids,MapNodesToPidOwners,NeuronName2Pid_map) ->
  get(pid_msg)!zeroCounter,
  get(pid_data_sender)!wait,
  {NewNeuronName2Pid_map,PidOldPidNewTuples}=fix_resonator_17stage(fournodes, Nodes, Tids,NeuronName2Pid_map),
  NeuronList=lists:seq(1,17),

  lists:foreach(fun({{Old,New},NodeName})->rpc:call(NodeName,ets_statem,callChangePid,[maps:get(NodeName,MapNodesToPidOwners),Old,New]) end,
  lists:zip(PidOldPidNewTuples,lists:map(fun(X)-> case X of
                                                             A when A == 1; A == 2;A == 3; A == 4-> lists:nth(3,Nodes);
                                                             B when B == 5; B == 6;B == 7; B == 8-> lists:nth(1,Nodes);
                                                             C when C == 9; C == 10;C == 11; C == 12-> lists:nth(2,Nodes);
                                                             D when D == 13; D == 14;D == 15; D == 16; D == 17-> lists:nth(4,Nodes)
end end, NeuronList))),

  neuron_statem:sendMessage(maps:get(afi11,NewNeuronName2Pid_map),maps:get(afi14,NewNeuronName2Pid_map),<<1>>,x),
  get(pid_data_sender)!{stopWait,maps:get(afi11,NewNeuronName2Pid_map)},
  NewNeuronName2Pid_map.

fix_resonator_4stage(onenode, Node, Tid,NeuronName2Pid_mapOLD) ->
  Neurons = get_4_neurons([], [Tid]),
  NeuronName2Pid=lists:map(fun({Name, Record}) ->
    {ok,Pid}=rpc:call(Node, neuron_statem, start, [{restore,Record,maps:get(Name,NeuronName2Pid_mapOLD)}]),
    {Name, Pid} end, Neurons),
  %list neuron name -> pid
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  PidOldPidNewTuples = [{maps:get(X,NeuronName2Pid_mapOLD),maps:get(X,NeuronName2Pid_map)}||X <-maps:keys(NeuronName2Pid_map)],
  neuron_statem:pidConfig(maps:get(afi1,NeuronName2Pid_map), [enable,get(pid_data_sender),maps:get(afi23,NeuronName2Pid_map)],
    [maps:get(afi21, NeuronName2Pid_map),{finalAcc,get(pid_acc)}]),
  neuron_statem:pidConfig(maps:get(afi21,NeuronName2Pid_map), [enable,maps:get(afi1,NeuronName2Pid_map)],
    [maps:get(afi22, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi22,NeuronName2Pid_map), [enable,maps:get(afi21,NeuronName2Pid_map)],
    [maps:get(afi23, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi23,NeuronName2Pid_map), [enable,maps:get(afi22,NeuronName2Pid_map)],
    [maps:get(afi1, NeuronName2Pid_map)]),
  {NeuronName2Pid_map,PidOldPidNewTuples};

fix_resonator_4stage(fournodes, Nodes, Tids,NeuronName2Pid_mapOLD) ->
  Neurons = get_4_neurons(Nodes, Tids),

  NeuronName2Pid=lists:map(fun({Name, Record,Node}) ->
    {ok,Pid}=rpc:call(Node, neuron_statem, start, [{restore,Record,maps:get(Name,NeuronName2Pid_mapOLD)}]),
    {Name, Pid} end, Neurons),
  %list neuron name -> pid
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  PidOldPidNewTuples = [{maps:get(X,NeuronName2Pid_mapOLD),maps:get(X,NeuronName2Pid_map)}||X <-maps:keys(NeuronName2Pid_map)],
  pidConfig4(NeuronName2Pid_map),
  {NeuronName2Pid_map,PidOldPidNewTuples}.


fix_resonator_17stage(onenode, Node, Tid,NeuronName2Pid_mapOLD) ->
  Neurons = get_17_neurons([], [Tid]),
  NeuronName2Pid=lists:map(fun({Name, Record}) ->
    {ok,Pid}=rpc:call(Node, neuron_statem, start, [{restore,Record,maps:get(Name,NeuronName2Pid_mapOLD)}]),
    {Name, Pid} end, Neurons),
  %list neuron name -> pid
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  PidOldPidNewTuples = [{maps:get(X,NeuronName2Pid_mapOLD),maps:get(X,NeuronName2Pid_map)}||X <-maps:keys(NeuronName2Pid_map)],
  pidConfig17(NeuronName2Pid_map),
  {NeuronName2Pid_map,PidOldPidNewTuples};

fix_resonator_17stage(fournodes, Nodes, Tids,NeuronName2Pid_mapOLD) ->
  Neurons = get_17_neurons(Nodes, Tids),
  NeuronName2Pid=lists:map(fun({Name, Record,Node}) ->
    {ok,Pid}=rpc:call(Node, neuron_statem, start, [{restore,Record,maps:get(Name,NeuronName2Pid_mapOLD)}]),
    {Name, Pid} end, Neurons),
  %list neuron name -> pid
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  PidOldPidNewTuples = [{maps:get(X,NeuronName2Pid_mapOLD),maps:get(X,NeuronName2Pid_map)}||X <-maps:keys(NeuronName2Pid_map)],
  pidConfig17(NeuronName2Pid_map),
  {NeuronName2Pid_map,PidOldPidNewTuples}.


%%%===================================================================
%%%  Fix Network
%%%===================================================================
get_4_neurons(_,[Tid])->
  Frequency_Detect=get(freq_detect), LF = 5, %% todo: save freq after crush.
  LP =round((1.0)*(1.536*math:pow(10,6))/(Frequency_Detect*math:pow(2,LF)*2*math:pi())),
  Gain=math:pow(2,(2*LF-3))*(1+LP),
  Factor_Gain=(1.0)*9472/Gain,
  [{afi1, #neuron_statem_state{etsTid=Tid,weightPar=[11*Factor_Gain,-9*Factor_Gain], biasPar=-1*Factor_Gain, leakagePeriodPar = LP}},
    {afi21, #neuron_statem_state{etsTid=Tid,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}},
    {afi22, #neuron_statem_state{etsTid=Tid,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}},
    {afi23, #neuron_statem_state{etsTid=Tid,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}}];


get_4_neurons([Node1, Node2, Node3, Node4], [Tid1, Tid2, Tid3, Tid4])->
  Frequency_Detect=get(freq_detect), LF = 5,
  LP =round((1.0)*(1.536*math:pow(10,6))/(Frequency_Detect*math:pow(2,LF)*2*math:pi())),
  Gain=math:pow(2,(2*LF-3))*(1+LP),
  Factor_Gain=(1.0)*9472/Gain,
  [{afi1, #neuron_statem_state{etsTid=Tid1,weightPar=[11*Factor_Gain,-9*Factor_Gain], biasPar=-1*Factor_Gain, leakagePeriodPar = LP}, Node1},
   {afi21, #neuron_statem_state{etsTid=Tid2,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}, Node2},
   {afi22, #neuron_statem_state{etsTid=Tid3,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}, Node3},
   {afi23, #neuron_statem_state{etsTid=Tid4,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}, Node4}].

get_17_neurons(_,[Tid])->
  Frequency_Detect=get(freq_detect), LF = 5,
  LP =round((1.0)*(1.536*math:pow(10,6))/(Frequency_Detect*math:pow(2,LF)*2*math:pi())),
  Gain=math:pow(2,(2*LF-3))*(1+LP),
  Factor_Gain=(1.0)*9472/Gain,
  [{afi11, #neuron_statem_state{etsTid=Tid,weightPar=[11*Factor_Gain,-9*Factor_Gain], biasPar=-1*Factor_Gain, leakagePeriodPar = LP}},
    {afi12, #neuron_statem_state{etsTid=Tid,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}},
    {afi13, #neuron_statem_state{etsTid=Tid,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}},
    {afi14, #neuron_statem_state{etsTid=Tid,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}},
    {afi21, #neuron_statem_state{etsTid=Tid,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}},
    {afi22, #neuron_statem_state{etsTid=Tid,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}},
    {afi23, #neuron_statem_state{etsTid=Tid,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}},
    {afi24, #neuron_statem_state{etsTid=Tid,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}},
    {afb1, #neuron_statem_state{etsTid=Tid, actTypePar = binaryStep, weightPar=[10], biasPar=-5}},
    {afb2, #neuron_statem_state{etsTid=Tid, actTypePar = binaryStep, weightPar=[10], biasPar=-5}},
    {afb3, #neuron_statem_state{etsTid=Tid, actTypePar = binaryStep, weightPar=[10], biasPar=-5}},
    {afb4, #neuron_statem_state{etsTid=Tid, actTypePar = binaryStep, weightPar=[10], biasPar=-5}},
    {afi31, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi32, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi33, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {afi34, #neuron_statem_state{etsTid=Tid,weightPar=[10], biasPar=-5}},
    {sum, #neuron_statem_state{etsTid=Tid,weightPar=[6,6,6,6], biasPar=-12, leakagePeriodPar = 500}}];

get_17_neurons([Node1, Node2, Node3, Node4], [Tid1, Tid2, Tid3, Tid4])->
  Frequency_Detect=get(freq_detect), LF = 5,
  LP =round((1.0)*(1.536*math:pow(10,6))/(Frequency_Detect*math:pow(2,LF)*2*math:pi())),
  Gain=math:pow(2,(2*LF-3))*(1+LP),
  Factor_Gain=(1.0)*9472/Gain,
  [{afi11, #neuron_statem_state{etsTid=Tid1,weightPar=[11*Factor_Gain,-9*Factor_Gain], biasPar=-1*Factor_Gain, leakagePeriodPar = LP}, Node1},
    {afi12, #neuron_statem_state{etsTid=Tid1,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}, Node1},
    {afi13, #neuron_statem_state{etsTid=Tid1,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP}, Node1},
    {afi14, #neuron_statem_state{etsTid=Tid1,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP},Node1},
    {afi21, #neuron_statem_state{etsTid=Tid2,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP},Node2},
    {afi22, #neuron_statem_state{etsTid=Tid2,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP},Node2},
    {afi23, #neuron_statem_state{etsTid=Tid2,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP},Node2},
    {afi24, #neuron_statem_state{etsTid=Tid2,weightPar=[10*Factor_Gain], biasPar=-5*Factor_Gain, leakagePeriodPar = LP},Node2},
    {afb1, #neuron_statem_state{etsTid=Tid3, actTypePar = binaryStep, weightPar=[10], biasPar=-5},Node3},
    {afb2, #neuron_statem_state{etsTid=Tid3, actTypePar = binaryStep, weightPar=[10], biasPar=-5},Node3},
    {afb3, #neuron_statem_state{etsTid=Tid3, actTypePar = binaryStep, weightPar=[10], biasPar=-5},Node3},
    {afb4, #neuron_statem_state{etsTid=Tid3, actTypePar = binaryStep, weightPar=[10], biasPar=-5},Node3},
    {afi31, #neuron_statem_state{etsTid=Tid4,weightPar=[10], biasPar=-5},Node4},
    {afi32, #neuron_statem_state{etsTid=Tid4,weightPar=[10], biasPar=-5},Node4},
    {afi33, #neuron_statem_state{etsTid=Tid4,weightPar=[10], biasPar=-5},Node4},
    {afi34, #neuron_statem_state{etsTid=Tid4,weightPar=[10], biasPar=-5},Node4},
    {sum, #neuron_statem_state{etsTid=Tid4,weightPar=[6,6,6,6], biasPar=-12, leakagePeriodPar = 500},Node4}].

pidConfig4(NeuronName2Pid_map)->
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
    [maps:get(afi1, NeuronName2Pid_map)]).


%% DONT DELETE - need maybe later between pc's
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

pidConfig17(NeuronName2Pid_map)->
  neuron_statem:pidConfig(maps:get(afi11,NeuronName2Pid_map), [enable,get(pid_data_sender),maps:get(afi14,NeuronName2Pid_map)],
    [maps:get(afi12,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi12,NeuronName2Pid_map), [enable,maps:get(afi11,NeuronName2Pid_map)],
    [maps:get(afi13,NeuronName2Pid_map),maps:get(afi32,NeuronName2Pid_map),maps:get(afb2,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi13,NeuronName2Pid_map), [enable,maps:get(afi12,NeuronName2Pid_map)],
    [maps:get(afi14,NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi14,NeuronName2Pid_map), [enable,maps:get(afi13,NeuronName2Pid_map)],
    [maps:get(afi11,NeuronName2Pid_map),maps:get(afi21,NeuronName2Pid_map),
      maps:get(afi33,NeuronName2Pid_map),maps:get(afb3,NeuronName2Pid_map),{msgControl,get(pid_msg)}]),
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
    [{finalAcc,get(pid_acc)}]).


open_ets_satatem(Pid_Server,NodeName)->
  {ok,PidBackup} = rpc:call(NodeName,ets_statem,start,[Pid_Server,backup,none]),
  erlang:monitor(process,PidBackup),
  {ok,PidEtsOwner} =  rpc:call(NodeName,ets_statem,start,[Pid_Server,etsOwner,PidBackup]),
  erlang:monitor(process,PidEtsOwner),
  receive
    {{Node,PidEtsOwner},Tid} ->
      {{Node,PidEtsOwner,PidBackup},Tid}
  end.

