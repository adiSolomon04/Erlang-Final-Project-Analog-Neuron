%%%-------------------------------------------------------------------
%%% @author eran
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 29. Jul 2020 2:52 AM
%%%-------------------------------------------------------------------
-module(ets_statem).
-author("eran").

-behaviour(gen_statem).

%% API
-export([start/3, callChangePid/3, callChangeHeir/2]).

%% gen_statem callbacks
-export([init/1, format_status/2, handle_event/4, terminate/3,
  code_change/4, callback_mode/0, etsOwnerState/3, backupState/3]).

-define(SERVER, ?MODULE).

-record(ets_statem_state, {}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Creates a gen_statem process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.

%% @param:    Name_ets_statem the name of the statem (the name it will register)
%%            the pid of the calling process
%%            StartState = backup/etsOwner according to this parameter
%%            PidHeir - in backup -> none, in etsOwner -> the Heir pid
%%                                   (the pid of the process that will get the table if the process falls)
%% @returns:  {ok,MyPid}
%% @sendMessage: if StartState =:= etsOwner -> send {{node(),self()},Tid}
start(Pid_Server, StartState, PidHeir) ->
  gen_statem:start(?MODULE, [Pid_Server,StartState,PidHeir], []).

%% callChangePid
%% @param:    Name_ets_statem the name of the statem (the name it will registered)
%%            OldPid,NewPid= the Pid of the falling neuron and the new one
%%            Tid - the state
%% @sendMessage: replay {MyPlace,{updatePid,NewPid}}
callChangePid(Name_ets_statem, OldPid, NewPid) ->
  gen_statem:call(Name_ets_statem,{changePid,{OldPid,NewPid}}).

%% callChangePid
%% @param:    Name_ets_statem the name of the statem (the name it will registered)
%%            Heir - the pid of the Heir
%%            Tid - the state
%% @sendMessage: replay {MyPlace,{updatePid,NewPid}}
callChangeHeir(Name_ets_statem, Heir) ->
  gen_statem:call(Name_ets_statem,{changeHeir,{Heir}}).

%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

%% @private
%% @doc Whenever a gen_statem is started using gen_statem:start/[3,4] or
%% gen_statem:start_link/[3,4], this function is called by the new
%% process to initialize.

%% calls from start_link
%% @param:    the pid of the calling process
%%            StartState = backup
%%            PidHeir -none
init([_,backup,none]) ->
  S = self(),
  io:format("here1 ~p" ,[S]),
  {ok, backupState, x};

%% calls from start_link
%% @param:    the pid of the calling process
%%            StartState = etsOwner according to this parameter
%%            PidHeir - etsOwner -> the Heir pid (the pid of the process that will get the table if the process falls)
%% @sendMessage: if StartState =:= etsOwner -> send {{node(),self()},Tid}
init([Pid_Server,etsOwner,PidHeir]) ->
  %%todo: maybe need read/write_concurrency???
  Tid = ets:new(neurons_data,[set,public,{heir,PidHeir,x}]),
  MyPlace = {node(),self()},
  Pid_Server!{MyPlace,Tid}, %% send the Tid back to the server
  {ok, etsOwnerState, Tid}.

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

%% calls from callChangePid
%% @param:    {call,Pid_Server} - the pid of the calling process
%%            {changePid,{OldPid,NewPid}} = the Pid of the falling neuron and the new one
%%            Tid - the state
%% @sendMessage: replay {MyPlace,{updatePid,NewPid}}
etsOwnerState({call,Pid_Server}, {changePid,{OldPid,NewPid}},Tid) ->
  [{OldPid,NeuronData}]=ets:take(Tid,OldPid),
  ets:insert_new(Tid,{NewPid,NeuronData}),
  MyPlace = {node(),self()},
  Reply = [{reply,Pid_Server,{MyPlace,{updatePid,NewPid}}}],
  NextStateName = etsOwnerState,
  {next_state, NextStateName,Tid,Reply};

%% calls from callChangeHeir
%% @param:    {call,Pid_Server} - the pid of the calling process
%%            changeHeir,{Heir}} = the Pid of the heir to update in the Tid option
%%            Tid - the state
%% @sendMessage: replay {MyPlace,{changedHeir,Heir}}
etsOwnerState({call,Pid_Server}, {changeHeir,{Heir}},Tid) ->
  ets:setopts(Tid,{heir, Heir, x}),
  MyPlace = {node(),self()},
  Reply= [{reply,Pid_Server,{MyPlace,{changedHeir,Heir}}}],
  NextStateName = etsOwnerState,
  {next_state, NextStateName,Tid, Reply}.


%% calls when the ets owner process falls, take the charge of the ets
%% @param:    info - active when get message
%%            {'ETS-TRANSFER',Tid,_,_} - the message that the ets process fell and the Tid
%% @next_state: etsOwnerState
%% need to update the Heir of the Tid and open new backup process
backupState(info, {'ETS-TRANSFER',Tid,_,_}, x) ->
  %global:unregister_name(Name_ets_statem),
  %global:register_name(HeirData,self()),
  NextStateName = etsOwnerState,
  {next_state, NextStateName, Tid}.

%% @private
%% @doc If callback_mode is handle_event_function, then whenever a
%% gen_statem receives an event from call/2, cast/2, or as a normal
%% process message, this function is called.
handle_event(_EventType, _EventContent, _StateName, State = #ets_statem_state{}) ->
  NextStateName = the_next_state_name,
  {next_state, NextStateName, State}.

%% @private
%% @doc This function is called by a gen_statem when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_statem terminates with
%% Reason. The return value is ignored.
terminate(_Reason, _StateName, _State = #ets_statem_state{}) ->
  ok.

%% @private
%% @doc Convert process state when code is changed
code_change(_OldVsn, StateName, State = #ets_statem_state{}, _Extra) ->
  {ok, StateName, State}.


