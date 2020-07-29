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
-export([start_link/3]).

%% gen_statem callbacks
-export([init/1, format_status/2, state_name/3, handle_event/4, terminate/3,
  code_change/4, callback_mode/0]).

-define(SERVER, ?MODULE).

-record(ets_statem_state, {}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Creates a gen_statem process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
start_link(Pid_Server,StartState,PidHeir) ->
  gen_statem:start_link({local, ?SERVER}, ?MODULE, [Pid_Server,StartState,PidHeir], []).

%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

%% @private
%% @doc Whenever a gen_statem is started using gen_statem:start/[3,4] or
%% gen_statem:start_link/[3,4], this function is called by the new
%% process to initialize.
init([Pid_Server,backup,none]) ->
  {ok, backupState, Pid_Server};

init([Pid_Server,etsOwner,PidHeir]) ->
  %%todo: maybe need read/write_concurrency
  Tid = ets:new(neurons_data,[set,{heir,PidHeir,none},public]),
  Pid_Server!{self(),Tid}, %% send the Tid back to the server
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
  Status = some_term,
  Status.

%% @private
%% @doc There should be one instance of this function for each possible
%% state name.  If callback_mode is state_functions, one of these
%% functions is called when gen_statem receives and event from
%% call/2, cast/2, or as a normal process message.
state_name(cast, _EventContent, State = #ets_statem_state{}) ->
  NextStateName = next_state,
  {next_state, NextStateName, State}.


etsOwnerState({call,Pid_Server}, {changePid,{OldPid,NewPid}},Tid) ->
  [NeuronData]=ets:take(Tid,OldPid),
  ets:insert_new(Tid,{NewPid,NeuronData}),
  Reply = [{self(),{updatePid,NewPid}}],
  NextStateName = etsOwnerState,
  {next_state, NextStateName,Tid,Reply};

etsOwnerState({call,Pid_Server}, {changeHeir,{Heir}},Tid) ->
  ets:setopts(Tid,Heir),
  Reply= [{reply,Pid_Server,{self(),{changedHeir,Heir}}}],
  NextStateName = etsOwnerState,
  {next_state, NextStateName,Tid, Reply}.


backupState(info, {'ETS-TRANSFER',Tid,_,_}, _) ->
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

%%%===================================================================
%%% Internal functions
%%%===================================================================
