%%%-------------------------------------------------------------------
%%% @author eran
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. Jul 2020 10:38 AM
%%%-------------------------------------------------------------------
-module(neuron_statem).
-author("eran").

-behaviour(gen_statem).

%% API
-export([start_link/2]).

%% gen_statem callbacks
-export([init/1, format_status/2, state_name/3, handle_event/4, terminate/3,
  code_change/4, callback_mode/0]).

-define(SERVER, ?MODULE).

-record(neuron_statem_state, {etsTid,actTypePar,weightPar,biasPar,leakageFactorPar,leakagePeriodPar,pidIn,pidOut}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Creates a gen_statem process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
start_link(EtsTid, NeuronParameters) ->
  gen_statem:start_link({local, ?SERVER}, ?MODULE, [EtsTid, NeuronParameters], []).

%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

%% @private
%% @doc Whenever a gen_statem is started using gen_statem:start/[3,4] or
%% gen_statem:start_link/[3,4], this function is called by the new
%% process to initialize.
init([EtsTid,restore]) ->
  % take the parameters from the ets
  NeuronMap=ets:lookup(EtsTid,self());
  RestoreMap=maps:get(restoreMap,NeuronMap);
  {ok, state_name, #neuron_statem_state{etsTid = EtsTid, actTypePar=maps:get(actType,RestoreMap),
   weightPar=maps:get(weight,RestoreMap),
  biasPar=maps:get(bias,RestoreMap), leakageFactorPar=maps:get(leakageFactor,RestoreMap),
  leakagePeriodPar=maps:get(leakagePeriod,RestoreMap),pidIn=maps:get(pidIn,RestoreMap),pidOut=maps:get(pidOut,RestoreMap)}};

%% @private
%% @doc Whenever a gen_statem is started using gen_statem:start/[3,4] or
%% gen_statem:start_link/[3,4], this function is called by the new
%% process to initialize.
init([EtsTid, NeuronParametersMap]) ->
  % enter the parameters to the ets and record/Parameters
  {ok, state_name, #neuron_statem_state{etsTid = EtsTid, actTypePar=maps:get(actType,NeuronParametersMap),
   weightPar=maps:get(weight,NeuronParametersMap),
  biasPar=maps:get(bias,NeuronParametersMap), leakageFactorPar=maps:get(leakageFactor,NeuronParametersMap),
  leakagePeriodPar=maps:get(leakagePeriod,NeuronParametersMap),pidIn=[],pidOut=[]}}.

%% @private
%% @doc This function is called by a gen_statem when it needs to find out
%% the callback mode of the callback module.
callback_mode() ->
  state_functions.

%% @private
%% @doc Called (1) whenever sys:get_status/1,2 is called by gen_statem or
%% (2) when gen_statem terminates abnormally.
%% This callback is optional.
format_status(_Opt, [_PDict, _StateName, _State]) ->
  Status = some_term,
  Status.

%% @private
%% @doc There should be one instance of this function for each possible
%% state name.  If callback_mode is state_functions, one of these
%% functions is called when gen_statem receives and event from
%% call/2, cast/2, or as a normal process message.
state_name(_EventType, _EventContent, State = #neuron_statem_state{}) ->
  NextStateName = next_state,
  {next_state, NextStateName, State}.


network_config(cast, {PidGetMsg,PidSendMsg}, State = #neuron_statem_state{etsTid = EtsId, actTypePar=ActType,
   weightPar=Weight,
  biasPar=Bias, leakageFactorPar=LF,
  leakagePeriodPar=LP,pidIn=_,pidOut=_}) ->
  % save the pids
  NextStateName = analog_neuron,
  {next_state, NextStateName, State#neuron_statem_state{etsTid = EtsId, actTypePar=ActType,
    weightPar=Weight,
    biasPar=Bias, leakageFactorPar=LF,
    leakagePeriodPar=LP,pidIn =PidGetMsg ,pidOut=PidSendMsg}}.


analog_neuron(cast, {Pid,SynBitString}, State = #neuron_statem_state{etsTid = _, actTypePar=_,
  weightPar=_,
  biasPar=_, leakageFactorPar=_,
  leakagePeriodPar=_,pidIn=_,pidOut=_}) ->
  NewState=gotBitString(Pid, SynBitString, State),
  NextStateName = analog_neuron,

  {next_state, NextStateName, State};

analog_neuron(cast, fixMessage, State = #neuron_statem_state{}) ->
  % go to repair state
  NextStateName = hold,
  {next_state, NextStateName, State}.

hold(cast, {Pid,SynBitString}, State = #neuron_statem_state{etsTid = _, actTypePar=_,
  weightPar=_,
  biasPar=_, leakageFactorPar=_,
  leakagePeriodPar=_,pidIn =_ ,pidOut=_}) ->
  % save the pids
  % do neuron function
  NextStateName = analog_neuron,
  {next_state, NextStateName, State}.

%% @private
%% @doc If callback_mode is handle_event_function, then whenever a
%% gen_statem receives an event from call/2, cast/2, or as a normal
%% process message, this function is called.
handle_event(_EventType, _EventContent, _StateName, State = #neuron_statem_state{etsTid = _, actTypePar=_,
  weightPar=_,
  biasPar=_, leakageFactorPar=_,
  leakagePeriodPar=_,pidIn =_ ,pidOut=_}) ->
  NextStateName = the_next_state_name,
  {next_state, NextStateName, State}.

%% @private
%% @doc This function is called by a gen_statem when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_statem terminates with
%% Reason. The return value is ignored.
terminate(_Reason, _StateName, _State = #neuron_statem_state{etsTid = _, actTypePar=_,
  weightPar=_,
  biasPar=_, leakageFactorPar=_,
  leakagePeriodPar=_,pidIn =_ ,pidOut=_}) ->
  ok.

%% @private
%% @doc Convert process state when code is changed
code_change(_OldVsn, StateName, State = #neuron_statem_state{etsTid = _, actTypePar=_,
  weightPar=_,
  biasPar=_, leakageFactorPar=_,
  leakagePeriodPar=_,pidIn =_ ,pidOut=_}, _Extra) ->
  {ok, StateName, State}.

%%%===================================================================
%%% EtsMap - has all neurons' maps that contains the variables of the neurons, the key is the Pid of the neuron.
%%% Neuron's map keys and values - *Key* ---> *Value* :
%%%  msgMap ---> A map of received synapses from neurons/Pids in the previous layer, the keys are the Pids
%%%  and the values are lists that store received synapses from that Pid, the head of the list is the earliest synapse that was received.
%%%  acc ---> The accumulator of the neuron.
%%%  pn_generator ---> Pseudo number generator, used for the output calculations for sigmoid activation type.
%%%  rand_gauss_var ---> Used for the output calculations for sigmoid activation type.
%%%  leakage_timer ---> Counts the number of pulse cycles following latest leakage step.
%%%
%%%
%%%
%%%
%%%
%%%
%%%
%%%
%%%===================================================================


%%%===================================================================
%%% Internal functions
%%%===================================================================
gotBitString(Pid, SynBitString, State= #neuron_statem_state{etsTid = EtsMap, actTypePar=_, weightPar=_,
  biasPar=_, leakageFactorPar=_,
  leakagePeriodPar=_,pidIn =PidIn ,pidOut=_}) ->
  NeuronMap=ets:lookup(EtsMap,self()),
  MsgMap=maps:get(msgMap,NeuronMap),
  NewMsgQueue= maps:get(Pid,MsgMap)++SynBitString, NewNeuronMap=maps:update(msgMap,maps:update(Pid,NewMsgQueue,MsgMap),NeuronMap),
  IsReady=checkReady(maps:iterator(maps:get(msgMap,NewNeuronMap))),
  if
    IsReady==false ->ets:insert(EtsMap,{self(),NewNeuronMap});
    true -> InputsMap=getLists(EtsMap,NewNeuronMap,maps:get(msgMap,NewNeuronMap),PidIn,maps:new()),
           calculations(State#neuron_statem_state{etsTid = EtsMap},InputsMap,size(SynBitString),1,[])
  end, State#neuron_statem_state{etsTid = EtsMap}.



%%% Checks whether the neuron has got synapses from all neurons from previous layer.
checkReady(MsgMapIter) when MsgMapIter==none -> true;
checkReady(MsgMapIter) when MsgMapIter=={_,[],_} -> false;
checkReady(MsgMapIter) -> checkReady(maps:next(MsgMapIter)).

%%% Calculates the output synapses and sends a bit string of these synapses to the next layer.
calculations(_,_,NumOfStages,N,Output) when N==NumOfStages+1->Bin=my_list_to_binary(Output),sendToNextLayer(Bin);
calculations(State= #neuron_statem_state{etsTid = EtsMap, actTypePar=_, weightPar=_,
  biasPar=_, leakageFactorPar=_,
  leakagePeriodPar=_,pidIn =_ ,pidOut=_},InputsMap,NumOfStages,N,Output)-> NewOutput=Output++calcStage(State,InputsMap,N),
  calculations(State= #neuron_statem_state{etsTid = EtsMap},InputsMap,NumOfStages,N+1,NewOutput).

%%% Makes a Map (Pid ---> List of synapses) out of the received synapses and converts the format of the synapses from binary-strings to lists.
getLists(EtsMap,NeuronMap,_,[],Output) ->ets:insert(EtsMap,{self(),NeuronMap}), Output;
getLists(EtsMap,NeuronMap,MsgMap,[HPid,TPid],Output) -> [Head|Tail]=maps:get(HPid,MsgMap),
  NewOutput=maps:put(HPid,binary_to_list(Head),Output), NewQ=Tail,
  NewNeuronMap=maps:update(msgMap,maps:update(HPid,NewQ,MsgMap),NeuronMap), getLists(EtsMap,NewNeuronMap,MsgMap,TPid,NewOutput).

%%% Converts List to binary-string.
my_list_to_binary(List) ->
  my_list_to_binary(List, <<>>).

my_list_to_binary([H|T], Acc) ->
  my_list_to_binary(T, <<Acc/binary,H>>);
my_list_to_binary([], Acc) ->
  Acc.

%%% Calculates the output of one "stage" of the input synapses.
calcStage(_ = #neuron_statem_state{etsTid = EtsId, actTypePar=ActType,
  weightPar=Weight,
  biasPar=Bias, leakageFactorPar=LF,
  leakagePeriodPar=LP,pidIn=PidIn,pidOut=_},InputMap,N)->
  Acc=maps:get(acc,ets:lookup(EtsId,self())),
  SumAcc=accumulate(LF,PidIn,InputMap,N,0,Acc,Weight),
  if
    LF>=3-> CurAcc = SumAcc+Bias*math:pow(2,LF-3);
    true -> CurAcc = SumAcc+Bias
  end,
  case ActType of
    identity-> OutputBit=handleIdentity(EtsId,CurAcc);
    binaryStep-> OutputBit=handleBinaryStep(CurAcc);
    sigmoid->SelfMapTest=ets:lookup(EtsId,self()),PN_generator=maps:get(pn_generator,SelfMapTest),
      {OutputBit,NewPnGenerator,NewRandVar}=handleSigmoid(CurAcc,0,0,PN_generator),
      UpdatedMap1=maps:update(pn_generator,NewPnGenerator,SelfMapTest),UpdatedMap2=maps:update(rand_gauss_var,NewRandVar,UpdatedMap1),
      ets:insert(EtsId,{self(),UpdatedMap2})
  end,
  SelfMap=ets:lookup(EtsId,self()),Leakage_Timer=maps:get(leakage_timer,SelfMap),
  if
    Leakage_Timer>=LP ->FinalAcc=leak(CurAcc,LF),New_Leakage_Timer=0;
    true -> New_Leakage_Timer=Leakage_Timer+1,FinalAcc=CurAcc
  end,
  UpdatedSelfMap=maps:update(leakage_timer,New_Leakage_Timer,SelfMap),
  FinalSelfMap=maps:update(acc,FinalAcc,UpdatedSelfMap),
  ets:insert(EtsId,{self(),FinalSelfMap}),
  OutputBit.

%%% Accumulates the Accumulator of the neuron at the first part of the calculations (Step 1 at cpp code).
accumulate(_,PidIn,_,_,PidCount,Acc,_) when PidCount==size(PidIn) -> Acc;
accumulate(LF,PidIn,InputMap,N,PidCount,Acc,Weight) ->CurrPid=lists:nth(PidCount,PidIn),
  if
  LF>=3-> NewAcc = Acc+maps:get(CurrPid,Weight)*lists:nth(N,maps:get(CurrPid,InputMap))*math:pow(2,LF-3);
  true -> NewAcc = Acc+maps:get(CurrPid,Weight)*lists:nth(N,maps:get(CurrPid,InputMap))
  end, accumulate(LF,PidIn,InputMap,N,PidCount+1,NewAcc,Weight).

%%% Calculates output according to Identity activation type.
handleIdentity(EtsId,CurAcc) when CurAcc>32767 ->NewRandVar= 32767,SelfMap=ets:lookup(EtsId,self()),
  ets:insert(EtsId,{self(),maps:update(rand_gauss_var,NewRandVar,SelfMap)}),1;
handleIdentity(EtsId,CurAcc) when CurAcc < -32767 ->NewRandVar= -32767,SelfMap=ets:lookup(EtsId,self()),
  ets:insert(EtsId,{self(),maps:update(rand_gauss_var,NewRandVar,SelfMap)}),0;
handleIdentity(EtsId,CurAcc) ->NewRandVar= CurAcc+32768,SelfMap=ets:lookup(EtsId,self()),
  if
    NewRandVar >=65536 ->ets:insert(EtsId,{self(),maps:update(rand_gauss_var,65536,SelfMap)}),1 ;
    true -> ets:insert(EtsId,{self(),maps:update(rand_gauss_var,NewRandVar,SelfMap)}),0
  end.

%%% Calculates output according to Identity Binary Step type.
handleBinaryStep(CurAcc) when CurAcc>0 -> 1;
handleBinaryStep(CurAcc) when CurAcc<0 -> 0.

%%% Calculates output according to Identity Sigmoid type.
handleSigmoid(CurAcc,8,GaussVar,PN_generator) ->Temp=GaussVar band 32768,
                                                       if
                                                         Temp /= 0  -> NewGaussVar=GaussVar band 4,294,901,760;
                                                         true ->  NewGaussVar=GaussVar
                                                       end,
                                                       if
                                                        CurAcc>GaussVar -> {1,PN_generator,NewGaussVar};
                                                        true -> {0,PN_generator,NewGaussVar}
                                                       end;
handleSigmoid(CurAcc,N,GaussVar,PN_generator) ->
  NewGaussVar=GaussVar+PN_generator band 8191,
  New_PN_generator=floor(PN_generator/2) bor ((pn_generator band 16384) bxor ((pn_generator band 1)*math:pow(2,14))),
  handleSigmoid(CurAcc,N+1,NewGaussVar,New_PN_generator).

%%% Executes leakage on neuron when needed.
leak(Acc,LF) when Acc < 0-> Decay_Delta=floor((-Acc)*pow(2,-LF)), if
                                                             Decay_Delta==0 -> 1 ;
                                                             true -> Decay_Delta
                                                           end;
leak(Acc,LF) when Acc > 0-> Decay_Delta=-floor((Acc)*pow(2,-LF)), if
                                                                    Decay_Delta==0 and Acc/=0 -> 1 ;
                                                                    true -> Decay_Delta
                                                                  end.