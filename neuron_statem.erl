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
-export([start_link/3, pidConfig/3, sendMessage/4]).

%% gen_statem callbacks
-export([init/1, format_status/2, state_name/3, handle_event/4, terminate/3,
  code_change/4, callback_mode/0,network_config/3,analog_neuron/3,hold/3,gotBitString/3]).

-define(SERVER, ?MODULE).

-record(neuron_statem_state, {etsTid,actTypePar,weightPar,biasPar,leakageFactorPar,leakagePeriodPar,pidIn,pidOut}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Creates a gen_statem process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
start_link(Name_neuron_statem,EtsTid, NeuronParameters) ->
  gen_statem:start_link({local, Name_neuron_statem}, ?MODULE, [EtsTid, NeuronParameters], []).

pidConfig(Name_neuron_statem,PrevPid,NextPid) ->
  gen_statem:cast(Name_neuron_statem,{PrevPid,NextPid}).


sendMessage({final,Name_neuron_statem},SendPid,SynBitString,_) ->
  Name_neuron_statem!{SendPid,SynBitString};
sendMessage({finalAcc,Name_neuron_statem},SendPid,_,Acc) ->
  io:format("Acc~p",[Acc]),
  Name_neuron_statem!{SendPid,Acc};
sendMessage(Name_neuron_statem,SendPid,SynBitString,_) ->
  gen_statem:cast(Name_neuron_statem,{SendPid,SynBitString}).
%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

%% @private
%% @doc Whenever a gen_statem is started using gen_statem:start/[3,4] or
%% gen_statem:start_link/[3,4], this function is called by the new
%% process to initialize.
init([EtsTid,restore]) ->
  % take the parameters from the ets
  Self = self(),
  [{Self,NeuronMap}]=ets:lookup(EtsTid,Self),
  %NeuronMap=ets:lookup(EtsTid,self()),
  RestoreMap=maps:get(restoreMap,NeuronMap),
  {ok, network_config, #neuron_statem_state{etsTid = EtsTid, actTypePar=maps:get(actType,RestoreMap),
   weightPar=maps:get(weight,RestoreMap),
  biasPar=maps:get(bias,RestoreMap), leakageFactorPar=maps:get(leakageFactor,RestoreMap),
  leakagePeriodPar=maps:get(leakagePeriod,RestoreMap),pidIn=maps:get(pidIn,RestoreMap),pidOut=maps:get(pidOut,RestoreMap)}};

%% @private
%% @doc Whenever a gen_statem is started using gen_statem:start/[3,4] or
%% gen_statem:start_link/[3,4], this function is called by the new
%% process to initialize.
%init([EtsTid, NeuronParametersMap]) ->
%  io:format("init!!!"),
%  % enter the parameters to the ets and record/Parameters
%  {ok, network_config, #neuron_statem_state{etsTid = EtsTid, actTypePar=maps:get(actType,NeuronParametersMap),
%   weightPar=maps:get(weight,NeuronParametersMap),
%  biasPar=maps:get(bias,NeuronParametersMap), leakageFactorPar=maps:get(leakageFactor,NeuronParametersMap),
%  leakagePeriodPar=maps:get(leakagePeriod,NeuronParametersMap),pidIn=[],pidOut=[]}}.

init([EtsTid, NeuronParametersMap]) ->
  S=self(),
  io:format("~p init!!!",[S]),
  % enter the parameters to the ets and record/Parameters
  {ok, network_config, NeuronParametersMap}.

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
  Status = _StateName,
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
  io:format("~p config!!!",[self()]),
  ListMsgMap = [{X,[]}||X <- PidGetMsg],
  MsgMap = maps:from_list(ListMsgMap),
  [PidEnabel|EnterPidGetMsg] =PidGetMsg,
  if PidEnabel==enable-> MsgMapFinal = maps:put(enable,[<<1>>],MsgMap) ;
      true -> MsgMapFinal = MsgMap
  end,
  EtsMap = #{msgMap=> MsgMapFinal, acc => 0,pn_generator=>1,rand_gauss_var=>0,leakage_timer=>0},
  Self = self(),
  ets:insert(EtsId,{Self,EtsMap}),
   MapWeight = maps:from_list(lists:zip(EnterPidGetMsg,Weight)),

% save the pids
  NextStateName = analog_neuron,
  {next_state, NextStateName, State#neuron_statem_state{etsTid = EtsId, actTypePar=ActType,
    weightPar=MapWeight,
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
  leakagePeriodPar=_,pidIn =PidIn ,pidOut=_}) ->  Self = self(),
  [{Self,NeuronMap}]=ets:lookup(EtsMap,Self),
  MsgMap=maps:get(msgMap,NeuronMap),
  NewMsgQueue= maps:get(Pid,MsgMap)++[SynBitString], NewMsgMap=maps:update(Pid,NewMsgQueue,MsgMap),NewNeuronMap=maps:update(msgMap,NewMsgMap,NeuronMap),

  IsReady=checkReady(maps:iterator(maps:get(msgMap,NewNeuronMap))),EnablePid=lists:nth(1,PidIn),
  if
    IsReady==false -> ets:insert(EtsMap,{self(),NewNeuronMap});
    true ->
           [EnableMsg|EnableList]=maps:get(EnablePid,MsgMap),NewMsgMapEnable=maps:update(EnablePid,EnableList,NewMsgMap),NewMapUpdated=maps:update(msgMap,NewMsgMapEnable,NewNeuronMap),
            ets:insert(EtsMap,{self(),NewMapUpdated}),
           if
              EnableMsg==<<1>>->%io:format("NewMsgMapEnable:  ~p \n", [NewMsgMapEnable]),
                NewState=State#neuron_statem_state{etsTid = EtsMap,pidIn =PidIn--[EnablePid]},gotBitStringEnabled(SynBitString,
               NewState,EnablePid);
              true -> NewState=State#neuron_statem_state{etsTid = EtsMap},gotBitStringNotEnable(NewState)
           end
  end, if
           EnablePid==enable ->[{Self,Map}]=ets:lookup(EtsMap,Self),Msg=maps:get(msgMap,Map),NewMap=maps:update(msgMap,maps:update(enable,[<<1>>],Msg),Map),

             ets:insert(EtsMap,{self(),NewMap});

           true -> ok
         end.


gotBitStringEnabled(SynBitString, State= #neuron_statem_state{etsTid = EtsMap, actTypePar=_, weightPar=_,
  biasPar=_, leakageFactorPar=_,
  leakagePeriodPar=_,pidIn =PidIn ,pidOut=PidOut},EnablePid) ->
  Self = self(),
  [{Self,NeuronMap}]=ets:lookup(EtsMap,Self),
  InputsMap=getLists(EtsMap,NeuronMap,maps:get(msgMap,NeuronMap),PidIn,maps:new()),
  calculations(State#neuron_statem_state{etsTid = EtsMap,pidOut=PidOut},InputsMap,size(SynBitString),1,[],[]),
  State#neuron_statem_state{etsTid = EtsMap,pidIn = [EnablePid]++PidIn}.

gotBitStringNotEnable(_= #neuron_statem_state{etsTid = EtsId, actTypePar=ActType, weightPar=_,
  biasPar=_, leakageFactorPar=_,
  leakagePeriodPar=_,pidIn =_ ,pidOut=PidOut}) ->Self = self(),
  [{Self,NeuronMap}]=ets:lookup(EtsId,Self),
  Acc=maps:get(acc,NeuronMap),
  maps:update(msgMap,maps:new(),NeuronMap),
  case ActType of
    identity-> OutputBit=handleIdentity(EtsId,Acc);
    binaryStep-> OutputBit=handleBinaryStep(Acc);
    sigmoid->  Self = self(),
      [{Self,SelfMapTest}]=ets:lookup(EtsId,Self),PN_generator=maps:get(pn_generator,SelfMapTest),
      {OutputBit,NewPnGenerator,NewRandVar}=handleSigmoid(Acc,0,0,PN_generator),
      UpdatedMap1=maps:update(pn_generator,NewPnGenerator,SelfMapTest),UpdatedMap2=maps:update(rand_gauss_var,NewRandVar,UpdatedMap1),
      ets:insert(EtsId,{self(),UpdatedMap2})
  end,Bin=my_list_to_binary([OutputBit]),%io:format("Bin:  ~p \n", [Bin]),
  sendToNextLayer(Bin,[Acc],PidOut).


%%% Checks whether the neuron has got synapses from all neurons from previous layer.
checkReady(MsgMapIter)  -> {_,Value,NewMsgMapIter}=maps:next(MsgMapIter),checkReady(Value,NewMsgMapIter).
checkReady(Value,MsgMapIter) when MsgMapIter==none ->  Value=/=[];
checkReady(Value,_) when Value==[] ->  false;
checkReady(_,MsgMapIter) -> {_,NewValue,NewMsgMapIter}=maps:next(MsgMapIter),checkReady(NewValue,NewMsgMapIter).

%%% Calculates the output synapses and sends a bit string of these synapses to the next layer.
calculations(_= #neuron_statem_state{etsTid = _,pidOut=PidOut},_,NumOfStages,N,Output,AccList) when N==NumOfStages+1 -> Bin=my_list_to_binary(Output),%io:format("Bin:  ~p \n", [Bin]),
  sendToNextLayer(Bin,AccList,PidOut); %%Bin,;
calculations(State= #neuron_statem_state{etsTid = _,pidOut=_},InputsMap,NumOfStages,N,Output,AccList)->
  CalcList=calcStage(State,InputsMap,N),NewOutput=Output++[lists:nth(1,CalcList)],NewAccList=AccList++[lists:nth(2,CalcList)], NewN=N+1,
  calculations(State,InputsMap,NumOfStages,NewN,NewOutput,NewAccList).

%%% Makes a Map (Pid ---> List of synapses) out of the received synapses and converts the format of the synapses from binary-strings to lists.
getLists(EtsMap,NeuronMap,_,[],Output) ->ets:insert(EtsMap,{self(),NeuronMap}), Output;
getLists(EtsMap,NeuronMap,MsgMap,[HPid|TPid],Output) -> [Head|Tail]=maps:get(HPid,MsgMap),
  NewOutput=maps:put(HPid,binary_to_list(Head),Output), NewQ=Tail,NewMsgMap=maps:update(HPid,NewQ,MsgMap),
  NewNeuronMap=maps:update(msgMap,NewMsgMap,NeuronMap), getLists(EtsMap,NewNeuronMap,NewMsgMap,TPid,NewOutput).

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
  Self = self(),
  [{Self,NeuronMap}]=ets:lookup(EtsId,Self),
  Acc=maps:get(acc,NeuronMap),

  SumAcc=accumulate(LF,PidIn,InputMap,N,0,Acc,Weight,length(PidIn)),
  if
    LF>=3-> CurAcc = SumAcc+Bias*math:pow(2,LF-3);
    true -> CurAcc = SumAcc+Bias
  end,
  case ActType of
    identity-> OutputBit=handleIdentity(EtsId,CurAcc);
    binaryStep-> OutputBit=handleBinaryStep(CurAcc);
    sigmoid->  Self = self(),
      [{Self,SelfMapTest}]=ets:lookup(EtsId,Self),PN_generator=maps:get(pn_generator,SelfMapTest),
      {OutputBit,NewPnGenerator,NewRandVar}=handleSigmoid(CurAcc,0,0,PN_generator),
      UpdatedMap1=maps:update(pn_generator,NewPnGenerator,SelfMapTest),UpdatedMap2=maps:update(rand_gauss_var,NewRandVar,UpdatedMap1),
      ets:insert(EtsId,{self(),UpdatedMap2})
  end,
  Self = self(),
  [{Self,SelfMap}]=ets:lookup(EtsId,Self),
  Leakage_Timer=maps:get(leakage_timer,SelfMap),
  if
    Leakage_Timer >= LP ->FinalAcc=leak(CurAcc,LF),New_Leakage_Timer=0;
    true -> New_Leakage_Timer=Leakage_Timer+1,FinalAcc=CurAcc
  end,
  UpdatedSelfMap=maps:update(leakage_timer,New_Leakage_Timer,SelfMap),
  FinalSelfMap=maps:update(acc,FinalAcc,UpdatedSelfMap),
  ets:insert(EtsId,{self(),FinalSelfMap}),
  [OutputBit,FinalAcc].

%%% Accumulates the Accumulator of the neuron at the first part of the calculations (Step 1 at cpp code).
accumulate(_,_,_,_,PidCount,Acc,_,Size) when PidCount==Size -> Acc;
accumulate(LF,PidIn,InputMap,N,PidCount,Acc,Weight,Size) -> CurrPid=lists:nth(PidCount+1,PidIn),NewPid=PidCount+1,
  if
  LF>=3-> NewAcc = Acc+maps:get(CurrPid,Weight)*lists:nth(N,maps:get(CurrPid,InputMap))*math:pow(2,LF-3);
  true -> NewAcc = Acc+maps:get(CurrPid,Weight)*lists:nth(N,maps:get(CurrPid,InputMap))
  end, accumulate(LF,PidIn,InputMap,N,NewPid,NewAcc,Weight,Size).

%%% Calculates output according to Identity activation type.
handleIdentity(EtsId,CurAcc) when CurAcc>32767 ->NewRandVar= 32767,Self = self(), [{Self,SelfMap}]=ets:lookup(EtsId,Self),
  ets:insert(EtsId,{self(),maps:update(rand_gauss_var,NewRandVar,SelfMap)}),1;
handleIdentity(EtsId,CurAcc) when CurAcc < -32767 ->NewRandVar= -32767,Self = self(), [{Self,SelfMap}]=ets:lookup(EtsId,Self),
  ets:insert(EtsId,{self(),maps:update(rand_gauss_var,NewRandVar,SelfMap)}),0;
handleIdentity(EtsId,CurAcc) ->[{Self,SelfMap}]=ets:lookup(EtsId,self()),RandVar=maps:get(rand_gauss_var,SelfMap),

  NewRandVar= RandVar + CurAcc+32768,Self = self(), [{Self,SelfMap}]=ets:lookup(EtsId,Self),
  if
    NewRandVar >=65536 ->ets:insert(EtsId,{self(),maps:update(rand_gauss_var,NewRandVar-65536,SelfMap)}),1 ;
    true -> ets:insert(EtsId,{self(),maps:update(rand_gauss_var,NewRandVar,SelfMap)}),0
  end.

%%% Calculates output according to Identity Binary Step type.
handleBinaryStep(CurAcc) when CurAcc>0 -> 1;
handleBinaryStep(CurAcc) when CurAcc=<0 -> 0.

%%% Calculates output according to Identity Sigmoid type.
handleSigmoid(CurAcc,8,GaussVar,PN_generator) -> Temp=GaussVar band 32768,
                                                       if
                                                         Temp /= 0  -> NewGaussVar = (GaussVar bor 4294901760);
                                                         true ->  NewGaussVar = GaussVar
                                                       end,
                                                       if
                                                        CurAcc > NewGaussVar -> {1,PN_generator,NewGaussVar};
                                                        true -> {0,PN_generator,NewGaussVar}
                                                       end;
handleSigmoid(CurAcc,N,GaussVar,PN_generator) ->
  NewGaussVar = GaussVar + (PN_generator band 8191),
  New_PN_generator = trunc(PN_generator/2) bor ((PN_generator band 16384) bxor ((PN_generator band 1)*trunc(math:pow(2,14)))),
  handleSigmoid(CurAcc,N+1,NewGaussVar,New_PN_generator).

%%% Executes leakage on neuron when needed.
leak(Acc,LF) when Acc < 0-> Decay_Delta=math:floor((-Acc)*math:pow(2,-LF)), if
                                                             Decay_Delta==0 -> 1 ;
                                                             true -> Decay_Delta
                                                           end;
leak(Acc,LF) when Acc > 0-> Decay_Delta=-math:floor((Acc)*math:pow(2,-LF)), if
                                                                    (Decay_Delta==0) and (Acc /= 0) -> 1;
                                                                    true -> Decay_Delta
                                                                  end.


sendToNextLayer(Bin,AccList,PidOut) ->  % io:format("ok? ~p\n",[{Bin,PidOut}]),
  S=self(),lists:foreach(fun(X)->sendMessage(X,S,Bin,AccList) end,PidOut).