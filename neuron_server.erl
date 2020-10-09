%%%-------------------------------------------------------------------
%%% @author adisolo
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 29. Jul 2020 15:20
%%%-------------------------------------------------------------------
-module(neuron_server).
-author("adisolo").

-behaviour(gen_server).

%% API
-export([start_link/0, test_networks/1, wx_env/1, launch_network/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3]).

-define(SERVER, neuron_server).

-record(neuron_server_state, { supervisors_map=#{}, env}).

%%%===================================================================
%%% API
%%%===================================================================
%% neuron_server:start_link().
%% @doc Spawns the server and registers the local name (unique)
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start({local, ?SERVER}, ?MODULE, [], []).

launch_network(Net_Size, [Node], Frequency_Detect)->
  gen_server:cast(?SERVER, {launch_network,[single_node, Net_Size, [Node], Frequency_Detect]});
launch_network(Net_Size, Nodes, Frequency_Detect)->
  gen_server:cast(?SERVER, {launch_network,[four_nodes, Net_Size, Nodes, Frequency_Detect]}).

test_networks(Freq={_, _}) ->
  gen_server:cast(?SERVER, {test_network, Freq}).

wx_env(Env)->
  gen_server:cast(?SERVER, {env, Env}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%% @doc Initializes the server
-spec(init(Args :: term()) ->
  {ok, State :: #neuron_server_state{}} | {ok, State :: #neuron_server_state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  neuron_wx:start(),
  {ok, #neuron_server_state{}}.

%% @private
%% @doc Handling call messages
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #neuron_server_state{}) ->
  {reply, Reply :: term(), NewState :: #neuron_server_state{}} |
  {reply, Reply :: term(), NewState :: #neuron_server_state{}, timeout() | hibernate} |
  {noreply, NewState :: #neuron_server_state{}} |
  {noreply, NewState :: #neuron_server_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #neuron_server_state{}} |
  {stop, Reason :: term(), NewState :: #neuron_server_state{}}).
handle_call(_Requset, _From, State = #neuron_server_state{}) ->
  {reply, ok, State}.

%% @private
%% @doc Handling cast messages
-spec(handle_cast(Request :: term(), State :: #neuron_server_state{}) ->
  {noreply, NewState :: #neuron_server_state{}} |
  {noreply, NewState :: #neuron_server_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #neuron_server_state{}}).

handle_cast({launch_network,[single_node, Net_Size, [Node], Frequency_Detect]},
    State = #neuron_server_state{supervisors_map = Map}) ->
  io:format("here cast1~n"),
  NewSupervisor=neuron_supervisor:start(single_node, Net_Size, [Node], Frequency_Detect),
  %NewSupervisor!{test_network,{195, 200}},
  NewMap= case maps:find(Node, Map) of
            error ->monitor_node(Node, true), Map#{Node => [NewSupervisor]};
            {ok, List} -> Map#{Node => List++[NewSupervisor]}
          end,
  io:format("here cast2~n"),
  {noreply, State#neuron_server_state{supervisors_map = NewMap}};
handle_cast({launch_network,[four_nodes, Net_Size, Nodes, Frequency_Detect]},
    State = #neuron_server_state{supervisors_map = Map}) ->
io:format("handle_cast Nodes: ~p ~n ",[Nodes]),
  NewSupervisor=neuron_supervisor:start(four_nodes, Net_Size, Nodes, Frequency_Detect),
  NewMap=makeMap(Nodes,Map,NewSupervisor,length(Nodes)),
  {noreply, State#neuron_server_state{supervisors_map = NewMap}};
handle_cast(Req={test_network, _}, State = #neuron_server_state{supervisors_map = Map}) ->
  Supervisors =  lists:flatten(maps:values(Map)),
  lists:foreach(fun(Pid)-> Pid!Req end, Supervisors),
  %%gather(Supervisors), %todo: supervisor sends a message with {done_testing, Pid}
  {noreply, State};
handle_cast({env,Env}, State)->
  %wx:set_env(Env),
  %wxMessageDialog:showModal(wxMessageDialog:new(wx:null(), "message server")),
  {noreply, State#neuron_server_state{env = Env}}.

%% @private
%% @doc Handling all non call/cast messages


handle_info({nodedown, NodeDown}, State = #neuron_server_state{supervisors_map = Map}) ->
  io:format("NODEDOWNAHAHAHAHAHAHAHAHAHAHAHAH~n"),
  Nodes=maps:keys(Map),
  ListDown= maps:get(NodeDown,Map),
  MapList= lists:map(fun(X)->List= maps:get(X,Map),NewList=List--ListDown,{X,NewList} end,Nodes),
  lists:foreach(fun(X)-> X ! 'NODEDOWN' end,ListDown),
  NewMap=maps:from_list(MapList),
{noreply, State#neuron_server_state{supervisors_map = NewMap}};
handle_info(Message, State = #neuron_server_state{supervisors_map = Map}) ->
  io:format("NODEDOWNAHAHAHAHAHAHAHAHAHAHAHAH ~p~n",[Message])
  .

%% @private
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #neuron_server_state{}) -> term()).
terminate(_Reason, _State = #neuron_server_state{}) ->
  ok.

%% @private
%% @doc Convert process state when code is changed
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #neuron_server_state{},
    Extra :: term()) ->
  {ok, NewState :: #neuron_server_state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State = #neuron_server_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

gather([Pid|Pids]) ->
  receive
    {done_testing, Pid} -> gather(Pids)
  end;
gather([])-> done.

makeMap(_,Map,_,0)-> Map;
makeMap(Nodes,Map,NewSupervisor,N)-> Curr=lists:nth(N,Nodes),NewN=N-1,
  NewMap=case maps:find(Curr, Map) of
  error ->io:format("Node: ~p ~n ",[Curr]),monitor_node(Curr, true), Map#{Curr => [NewSupervisor]};
  {ok, List} -> Map#{Curr => List++[NewSupervisor]}
  end,makeMap(Nodes,NewMap,NewSupervisor,NewN).