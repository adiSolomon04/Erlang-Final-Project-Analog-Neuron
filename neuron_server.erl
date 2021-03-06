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
-include_lib("wx/include/wx.hrl").

%% API
-export([start_link/0, test_networks/1, wx_env/1, launch_network/3, sup_done/1, getSupName/4]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3, handlePicture/2]).

-define(SERVER, neuron_server).

-record(neuron_server_state, { supervisors_map=#{}, env, frame, nodes, sup_done=[], digraph_edges, numSup=1, name2pid=#{}}).

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

sup_done(Sup_Name) ->
  gen_server:cast(?SERVER, {sup_done, Sup_Name}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%% @doc Initializes the server
-spec(init(Args :: term()) ->
  {ok, State :: #neuron_server_state{}} | {ok, State :: #neuron_server_state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  {Env} = neuron_wx:start(),
  %wx:set_env(Env),
  graphviz:digraph("Network"),
  graphviz:to_file("network.png", "png"),
  graphviz:delete(),
  Frame = wxFrame:new(wx:null(), 1, "Launched Networks and Nodes"),
  wxWindow:setClientSize(Frame, {500, 500}),
  wxWindow:centerOnParent(Frame, [{dir,?wxVERTICAL}]),
  wxFrame:show(Frame),
  Panel = wxPanel:new(Frame),
  wxPanel:connect(Panel, paint, [{callback,fun(WxData, _)->
    neuron_server:handlePicture(Panel, WxData)
                                           end}]),
  wxWindow:refresh(Panel),
  {ok, #neuron_server_state{nodes = digraph:new(), digraph_edges = digraph:new(), env=Env, frame=Panel}}.

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

%% Handles the launch of a single node network
handle_cast({launch_network,[single_node, Net_Size, [Node], Frequency_Detect]},
    State = #neuron_server_state{supervisors_map = Map, nodes = NodesGraph, digraph_edges = Graph, numSup=Num, name2pid=MapName2Pid}) ->
  Check=checkNodesConnected([Node],[node()]),
  if
    Check==false ->
      wxMessageDialog:showModal(wxMessageDialog:new(wx:null(), "Wrong Node")),
      {noreply, State#neuron_server_state{supervisors_map = Map}};
    true ->
      Sup_Name = getSupName(Num, Net_Size, single_node, Frequency_Detect),
      Node_Name = getNodeName(Node),
      NewSupervisor=neuron_supervisor:start(single_node, Net_Size, [Node], Frequency_Detect, Sup_Name),
      digraph:add_vertex(NodesGraph, Node_Name),
      digraph:add_vertex(Graph, Node_Name),
      digraph:add_vertex(Graph, Sup_Name),
      digraph:add_edge(Graph, Node_Name, Sup_Name),
      %NewSupervisor!{test_network,{195, 200}},
      NewMap= case maps:find(Node, Map) of
                error ->monitor_node(Node, true), Map#{Node => [NewSupervisor]};
                {ok, List} -> Map#{Node => List++[NewSupervisor]}
              end,
      NewMapName2Pid = MapName2Pid#{Sup_Name => NewSupervisor},
      display_net(State),
      {noreply, State#neuron_server_state{supervisors_map = NewMap, numSup=Num+1, name2pid=NewMapName2Pid}}
  end;

%% Handles the launch of a four node network
handle_cast({launch_network,[four_nodes, Net_Size, Nodes, Frequency_Detect]},
    State = #neuron_server_state{supervisors_map = Map, nodes = NodesGraph, digraph_edges = Graph, numSup=Num, name2pid=MapName2Pid}) -> %, pid2name = Pid2Name
  Check=checkNodesConnected(Nodes,[node()]),
  if
    Check==false ->
      wxMessageDialog:showModal(wxMessageDialog:new(wx:null(), "Wrong Nodes")),{noreply, State#neuron_server_state{supervisors_map = Map}};
    true ->
      Sup_Name = getSupName(Num, Net_Size, four_nodes, Frequency_Detect),
      NewSupervisor=neuron_supervisor:start(four_nodes, Net_Size, Nodes, Frequency_Detect, Sup_Name),
      lists:foreach(fun(Node) ->
        Node_Name = getNodeName(Node),
        digraph:add_vertex(NodesGraph, Node_Name),
        digraph:add_vertex(Graph, Node_Name),
        digraph:add_vertex(Graph, Sup_Name),
        digraph:add_edge(Graph, Node_Name, Sup_Name)
                    end,
        Nodes),
      NewMap=makeMap(Nodes,Map,NewSupervisor,length(Nodes)),
      display_net(State),
      NewMapName2Pid = MapName2Pid#{Sup_Name => NewSupervisor},
      {noreply, State#neuron_server_state{supervisors_map = NewMap, numSup=Num+1, name2pid=NewMapName2Pid}}
  end;

handle_cast(Req={test_network, _}, State = #neuron_server_state{supervisors_map = _, name2pid=MapName2Pid}) ->
  Supervisors =  lists:flatten(maps:values(MapName2Pid)),
  lists:foreach(fun(Pid)-> Pid!Req end, Supervisors),
  %%gather(Supervisors), %todo: supervisor sends a message with {done_testing, Pid}
  {noreply, State};
handle_cast({env,Env}, State)->
  %wx:set_env(Env),
  %wxMessageDialog:showModal(wxMessageDialog:new(wx:null(), "message server")),
  {noreply, State#neuron_server_state{env = Env}};

handle_cast({sup_done, Sup_Name}, State=#neuron_server_state{sup_done = Sup_Done, digraph_edges = Graph})->
  digraph:del_vertex(Graph, Sup_Name),
  New_Sup_Done = Sup_Done++[Sup_Name],
  New_State = State#neuron_server_state{sup_done = New_Sup_Done},
  display_net(New_State),
  {noreply, New_State}.

%% @private
%% @doc Handling all non call/cast messages


handle_info({nodedown, NodeDown}, State = #neuron_server_state{supervisors_map = Map, nodes = NodesGraph, digraph_edges = Graph}) ->
  digraph:del_vertex(NodesGraph, getNodeName(NodeDown)),
  digraph:del_vertex(Graph, getNodeName(NodeDown)),
  display_net(State),
  Nodes=maps:keys(Map),
  ListDown= maps:get(NodeDown,Map),
  MapList= lists:map(fun(X)->List= maps:get(X,Map),NewList=List--ListDown,{X,NewList} end,Nodes),
  lists:foreach(fun(X)->
    X ! 'NODEDOWN'
                end,ListDown),
  NewMap=maps:from_list(MapList),
{noreply, State#neuron_server_state{supervisors_map = NewMap}}.


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

makeMap(_,Map,_,0)-> Map;
makeMap(Nodes,Map,NewSupervisor,N)-> Curr=lists:nth(N,Nodes),NewN=N-1,
  NewMap=case maps:find(Curr, Map) of
  error ->monitor_node(Curr, true), Map#{Curr => [NewSupervisor]};
  {ok, List} -> Map#{Curr => List++[NewSupervisor]}
  end,makeMap(Nodes,NewMap,NewSupervisor,NewN).

display_net(State=#neuron_server_state{frame = Panel})->
  create_new_net(State),
  wxWindow:refresh(Panel).

create_new_net(#neuron_server_state{nodes = NodesGraph, sup_done = Sup_Done, digraph_edges = Graph})->
  Nodes = digraph:vertices(NodesGraph),
  EdgeList = getEdgesList(Graph),
  Edges = lists:map(fun(X) -> {element(3,X),element(2,X)} end, EdgeList),
  graphviz:digraph("Network"),
  graphviz:add_cluster_nodes("Nodes Used",Nodes),
  graphviz:add_cluster_nodes("Supervisors Done",Sup_Done),
  lists:foreach(fun({X,Y}) -> graphviz:add_edge(X,Y)end, Edges),
  graphviz:set_shape("doublecircle", Nodes),
  graphviz:to_file("network.png", "png"),
  graphviz:delete().

handlePicture(Panel, _)->
  timer:sleep(200),
  Picture = wxImage:new("network.png"),
  {Width, Height} = {wxImage:getWidth(Picture),wxImage:getHeight(Picture)},
  {Width1, Height1} = wxPanel:getSize(Panel),

  %{Width1, Height1} = wxPanel:getSize(Panel17),
  PictureDrawScaled1 =case Width*Height1/Height-Width1 of
                        Res when Res<0 -> wxImage:scale(Picture, round(Width*Height1/Height), round(Height1));
                        _ -> wxImage:scale(Picture, round(Width1), round(Height*Width1/Width))
                      end,
  %"network17.png"),
  PictureBit = wxBitmap:new(PictureDrawScaled1),
  DC = wxPaintDC:new(Panel),
  wxDC:drawBitmap(DC, PictureBit, {0,0}),
  wxPaintDC:destroy(DC),
  wxWindow:updateWindowUI(Panel),
  done.

getEdgesList(G)->
  Edges=digraph:edges(G),
  [digraph:edge(G,E) || E <- Edges].

getNodeName(Node) when is_atom(Node) ->
  %% atom to string, without @
  lists:map(fun(X) -> case X of
                        64 -> 95;
                        46 -> 95;
                        _ -> X
                      end
            end, atom_to_list(Node));
getNodeName(_) -> err.

getSupName(Num, Net_Size, Net_Conc, Frequency_Detect) ->
  Freq_no_dots = getName_only_(io_lib:format("~p",[Frequency_Detect])),
  [NumSup]=io_lib:format("~w",[Num]),
  [NumNeurons]=io_lib:format("~w",[Net_Size]),
  "sup"++NumSup++"_"++NumNeurons++io_lib:format("_on_~s_",[Net_Conc])++"f_"++Freq_no_dots++"Hz".

getName_only_([String]) ->
  NewString = lists:map(fun(X) -> case X of
                        64 -> 95;
                        46 -> 95;
                        _ -> X
                      end
            end, String),
  NewString.
checkNodesConnected(Nodes,CurrNode)->
  (lists:all(fun(X)-> (pong == net_adm:ping(X)) end,Nodes--CurrNode)).