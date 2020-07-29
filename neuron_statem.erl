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

-record(neuron_statem_state, {etsTid = undifined, neuronParameters,pidIn,pidOut}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Creates a gen_statem process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
start_link(EtsId, NeuronParameters) ->
  gen_statem:start_link({local, ?SERVER}, ?MODULE, [EtsId, NeuronParameters], []).

%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

%% @private
%% @doc Whenever a gen_statem is started using gen_statem:start/[3,4] or
%% gen_statem:start_link/[3,4], this function is called by the new
%% process to initialize.
init([EtsId,restore]) ->
  % emter the parmeters to the ets and record/Parametes
  {ok, state_name, #neuron_statem_state{etsTid = EtsId, neuronParameters = restore}};


%% @private
%% @doc Whenever a gen_statem is started using gen_statem:start/[3,4] or
%% gen_statem:start_link/[3,4], this function is called by the new
%% process to initialize.
init([EtsId, NeuronParameters]) ->
  % emter the parmeters to the ets and record/Parametes
  {ok, state_name, #neuron_statem_state{etsTid = EtsId, neuronParameters = NeuronParameters}}.



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


network_config(cast, {PidGetMsg,PidSendMsg}, State = #neuron_statem_state{}) ->
  % save the pids
  NextStateName = analog_neuron,
  {next_state, NextStateName, State#neuron_statem_state{pidIn =PidGetMsg ,pidOut=PidSendMsg}}.


analog_neuron(cast, {Pid,SynaptaBitString}, State = #neuron_statem_state{}) ->
  % do neuron function
  gotBitString(Pid, SynaptaBitString, State),
  NextStateName = analog_neuron,
  {next_state, NextStateName, State}.

hold(cast, {Pid,SynaptaBitString}, State = #neuron_statem_state{}) ->
  % save the pids
  % do neuron function
  NextStateName = analog_neuron,
  {next_state, NextStateName, State}.

%% @private
%% @doc If callback_mode is handle_event_function, then whenever a
%% gen_statem receives an event from call/2, cast/2, or as a normal
%% process message, this function is called.
handle_event(_EventType, _EventContent, _StateName, State = #neuron_statem_state{}) ->
  NextStateName = the_next_state_name,
  {next_state, NextStateName, State}.

%% @private
%% @doc This function is called by a gen_statem when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_statem terminates with
%% Reason. The return value is ignored.
terminate(_Reason, _StateName, _State = #neuron_statem_state{}) ->
  ok.

%% @private
%% @doc Convert process state when code is changed
code_change(_OldVsn, StateName, State = #neuron_statem_state{}, _Extra) ->
  {ok, StateName, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

gotBitString(Pid, SynaptaBitString, State) ->
  %% Todo: do the neuron function
  %% Todo: the fucking branch.
  %% send the message if needed
  %% return the new state
  do.