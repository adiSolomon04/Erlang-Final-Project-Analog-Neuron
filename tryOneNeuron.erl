%%%-------------------------------------------------------------------
%%% @author eran
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 09. Sep 2020 6:58 AM
%%%-------------------------------------------------------------------
-module(tryOneNeuron).
-author("eran").

%% API
-export([runOneNwuron/0, debugGotBitString/0, start_resonator_4stage/3, debugResonator_4stage/0, fullSystem/0]).

-record(neuron_statem_state, {etsTid, actTypePar=identity,weightPar,biasPar=0,leakageFactorPar=5,leakagePeriodPar=73,pidIn=[],pidOut=[]}).

runOneNwuron() ->
  Tid = ets:new(neurons_data,[set,public]),
  ActType = binaryStep,
  S = self(),
  PidIn =[S],
  PidOut = [{final,self()}],
  Weight = #{S=>10},
  BiasPar = -1,
  LeakagePeriodPar = 73,
  LeakageFactorPar = 5,
  NeuronParameters = #{actType => ActType,weight=>Weight,bias=>BiasPar,leakageFactor=>LeakageFactorPar,leakagePeriod =>LeakagePeriodPar},
  Neuron = neuron_statem:start_link(neuron1,Tid,NeuronParameters),
  neuron_statem:pidConfig(neuron1,PidIn,PidOut),
  SynBitString = <<1,0,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0>>,
  neuron_statem:sendMessage(neuron1,S,SynBitString),
  receive
    X -> io:format("got ------  ~p",[X])
    after 1000 -> io:format("not got")
  end.
  %neuron_statem:start_link()

fullSystem() ->
  S =self(),
  N = ets_statem:start_link(etsHolder1,S,backup,none),
  io:format("here ~p" ,[N]).

%%ets_statem:start_link(etsOwner1,S,etsOwner,none);


debugGotBitString() ->
  Tid = ets:new(neurons_data,[set,public]),
  KeyPid = self(),
  ActType = identity,
  S = e,
  PidIn =[kaki,S,d],
  PidOut = [{final,self()}],
  Weight = #{ S=>10, d =>-11},
  BiasPar = -1,
  LeakagePeriodPar = 73,
  LeakageFactorPar = 5,
  EtsMap = #{msgMap=> #{kaki=>[<<1>>], S=>[],d => [<<0,1,1,1,0>>]}, acc => 0,pn_generator=>1,rand_gauss_var=>1,leakage_timer=>0},
  ets:insert(Tid,{KeyPid,EtsMap}),
  SynBitString = <<1,1,0,1,1>>,
  State= #neuron_statem_state{etsTid = Tid, actTypePar=ActType, weightPar=Weight,
    biasPar=BiasPar, leakageFactorPar=LeakageFactorPar,
    leakagePeriodPar=LeakagePeriodPar,pidIn =PidIn ,pidOut=PidOut},
  neuron_statem:gotBitString(S, SynBitString, State),
  receive
    X -> io:format("got ------  ~p",[X])
  after 1000 -> io:format("not got")
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
  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),get(pid_data_sender),<<1>>),
  receive
    X -> io:format("1.got ------  ~p\n",[X])
    after 1000 -> io:format("1.not got\n")
  end,
  neuron_statem:sendMessage(maps:get(afi1,NeuronName2Pid_map),maps:get(afi23,NeuronName2Pid_map),<<1>>),
  receive
  Y -> io:format("2.got ------  ~p\n",[Y])
after 1000 -> io:format("2.not got\n")
end
.

start_resonator_4stage(nonode, _, Tid) ->
  Neurons = [{afi1, #neuron_statem_state{etsTid=Tid,weightPar=[11,-9]}},
    {afi21, #neuron_statem_state{etsTid=Tid,weightPar=[10]}},
    {afi22, #neuron_statem_state{etsTid=Tid,weightPar=[10]}},
    {afi23, #neuron_statem_state{etsTid=Tid,weightPar=[10]}}], % afi24, afi25, afi26, afi27,
  % afb1, afb2, afb3, afb4,
  % afi31, afi32, afi33, afi34],
  io:format("~p",[Neurons]),
  NeuronName2Pid=lists:map(fun({Name, Record}) -> {ok,Pid}=neuron_statem:start_link(Name, Tid, Record), {Name, Pid} end, Neurons),
  %list neuron name -> pid
  NeuronName2Pid_map = maps:from_list(NeuronName2Pid),
  %todo:neuron_statem:pid_config(prev, next).
  neuron_statem:pidConfig(maps:get(afi1,NeuronName2Pid_map), [get(pid_data_sender),maps:get(afi23,NeuronName2Pid_map)],
    [maps:get(afi21, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi21,NeuronName2Pid_map), [maps:get(afi1,NeuronName2Pid_map)],
    [maps:get(afi22, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi22,NeuronName2Pid_map), [maps:get(afi21,NeuronName2Pid_map)],
    [maps:get(afi23, NeuronName2Pid_map)]),
  neuron_statem:pidConfig(maps:get(afi23,NeuronName2Pid_map), [maps:get(afi22,NeuronName2Pid_map)],
    [maps:get(afi1, NeuronName2Pid_map),{final,get(pid_data_sender)}]),
  NeuronName2Pid_map;
start_resonator_4stage(onenode, Node, Tid) ->
  do;
start_resonator_4stage(fournodes, Nodes, Tid) ->
  do.



