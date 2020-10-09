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
  code_change/3, handlePicture/2]).

-define(SERVER, neuron_server).

-record(neuron_server_state, {supervisors_four_nodes=[], supervisors_single_node=#{}, env, frame, digraph_nodes, digraph_edges}).

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
  monitor_node('eran@adisolo', true),
  {Env} = neuron_wx:start(),
  %wx:set_env(Env),
  graphviz:digraph("Network"),
  graphviz:to_file("network.png", "png"),
  graphviz:delete(),
  Frame = wxFrame:new(wx:null(), 1, "Launched Networks and Nodes"),
  wxFrame:show(Frame),
  Panel = wxPanel:new(Frame),
  wxPanel:connect(Panel, paint, [{callback,fun(WxData, _)->
    neuron_server:handlePicture({nothing,Panel}, WxData)
                                           end}]),
  handlePicture({Env, Frame}, x),
  {ok, #neuron_server_state{digraph_nodes = digraph:new(), digraph_edges = digraph:new(), env=Env, frame=Frame}}.

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
    State = #neuron_server_state{supervisors_single_node = Map}) ->
  io:format("here cast1~n"),
  NewSupervisor=neuron_supervisor:start(single_node, Net_Size, [Node], Frequency_Detect),
  %NewSupervisor!{test_network,{195, 200}},
  NewMap= case maps:find(Node, Map) of
            error -> Map#{Node => [NewSupervisor]};
            {ok, List} -> Map#{Node => List++[NewSupervisor]}
          end,
  io:format("here cast2~n"),
  {noreply, State#neuron_server_state{supervisors_single_node = NewMap}};
handle_cast({launch_network,[four_nodes, Net_Size, Nodes, Frequency_Detect]},
    State = #neuron_server_state{supervisors_four_nodes = Supervisors}) ->
  io:format("here cast1 four~n"),
  NewSupervisor=neuron_supervisor:start(four_nodes, Net_Size, Nodes, Frequency_Detect),
  {noreply, State#neuron_server_state{supervisors_four_nodes = Supervisors++[NewSupervisor]}};
handle_cast(Req={test_network, _}, State = #neuron_server_state{supervisors_four_nodes = List, supervisors_single_node = Map}) ->
  Supervisors = List ++ lists:flatten(maps:values(Map)),
  lists:foreach(fun(Pid)-> Pid!Req end, Supervisors),
  %%gather(Supervisors), %todo: supervisor sends a message with {done_testing, Pid}
  {noreply, State};
handle_cast({env,Env}, State)->
  %wx:set_env(Env),
  %wxMessageDialog:showModal(wxMessageDialog:new(wx:null(), "message server")),
  {noreply, State#neuron_server_state{env = Env}}.

%% @private
%% @doc Handling all non call/cast messages
-spec(handle_info(Info :: timeout() | term(), State :: #neuron_server_state{}) ->
  {noreply, NewState :: #neuron_server_state{}} |
  {noreply, NewState :: #neuron_server_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #neuron_server_state{}}).
handle_info(_Info, State = #neuron_server_state{}) ->
  io:format("~p~n", [_Info]),
  {noreply, State}.

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


display_net(State=#neuron_server_state{env=Env, frame = Frame})->
  create_new_net(State),
  handlePicture({Env, Frame}, x).

create_new_net(#neuron_server_state{digraph_nodes = GraphNodes, digraph_edges = Graph})->
  Nodes = digraph:vertices(GraphNodes),
  EdgeList = getEdgesList(Graph),
  Edges = lists:foreach(fun(X) -> {element(3,X),element(2,X)} end, EdgeList),
  graphviz:digraph("Network"),
  graphviz:add_cluster_nodes("Nodes Used",Nodes),
  lists:foreach(fun({X,Y}) -> graphviz:add_edge(X,Y)end, Edges),
  graphviz:set_shape("doublecircle", Nodes),
  graphviz:to_file("network.png", "png"),
  graphviz:delete().

handlePicture({Env, Frame}, _)->
  timer:sleep(200),
  case Env of
    nothing -> do_nothing;
    _ -> wx:set_env(Env)
  end,
  Picture = wxImage:new("AuthorsTree.png"),
  {Width, Height} = {wxImage:getWidth(Picture),wxImage:getHeight(Picture)},
  {Width1, Height1} = wxPanel:getSize(Frame),
  %{Width1, Height1} = wxPanel:getSize(Panel17),
  PictureDrawScaled1 = wxImage:scale(Picture, round(Width*Height1/Height), round(Height1)),
  %"network17.png"),
  PictureBit = wxBitmap:new(PictureDrawScaled1),
  DC = wxPaintDC:new(Frame),
  wxDC:drawBitmap(DC, PictureBit, {0,0}),
  wxPaintDC:destroy(DC),
  wxWindow:updateWindowUI(Frame),
  done.

getEdgesList(G)->
  Edges=digraph:edges(G),
  [digraph:edge(G,E) || E <- Edges].