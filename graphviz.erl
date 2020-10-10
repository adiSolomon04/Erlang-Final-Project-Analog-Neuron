-module(graphviz).
-export([digraph/1, graph/1, delete/0, add_node/1, add_edge/2, graph_server/1, to_dot/1, to_file/2, add_cluster/2, set_shape/2, add_cluster_nodes/2, set_env/1]).
-export([graph4neurons/0, graph17neurons/0]).

-record(graph, {graphId, type, graphOptions=[],
   nodes=[], edges=[], cluster=[], cluster_nodes=[], numClusters=1, shapes=#{}, env}).

%% =============================
%% graphviz display Network
%% =============================
graph4neurons() ->
   graphviz:digraph("G"),
   graphviz:add_edge(input_pdm, afi1),
   graphviz:set_shape("Mdiamond", input_pdm),
   Edges = [{afi1, afi21}, {afi21, afi22}, {afi22, afi23}, {afi23, afi1}],
   graphviz:add_cluster("FeedBack Layer", Edges),
   graphviz:to_file("AuthorsTree.png", "png"),
   graphviz:delete().

%  graphviz:graph17neurons().
graph17neurons() ->
   graphviz:digraph("G"),
   graphviz:add_edge(input_pdm, afi11),
   graphviz:set_shape("Mdiamond", input_pdm),
   graphviz:add_cluster_nodes("Feedback Layer", [afi11, afi12, afi13, afi14]),
   graphviz:add_cluster_nodes("Layer2", [afi21, afi22, afi23, afi24]),
   graphviz:add_cluster_nodes("Enable Layer", [afb1, afb2, afb3, afb4]),
   graphviz:add_cluster_nodes("Sum layer", [afi31, afi32, afi33, afi34]),

   Edges = [
      {afi11, afi12},
      {afi12, afi13}, {afi12, afi32}, {afi12, afb2},
      {afi13, afi14},
      {afi14, afi11}, {afi14, afi21}, {afi14, afi33}, {afi14, afb3},
      {afi21, afi22},
      {afi22, afi23}, {afi22, afb4}, {afi22, afi34},
      {afi23, afi24},
      {afi24, afb1}, {afi24, afi31},
      {afb1, afi31}, {afb2, afi32}, {afb3, afi33}, {afb4, afi34},
      {afi31, sum}, {afi32, sum}, {afi33, sum}, {afi34, sum}],
   lists:foreach(fun({X,Y})->graphviz:add_edge(X, Y) end,Edges),
   graphviz:to_file("network17.png", "png"),
   graphviz:delete().

%% =============================

% -- Constructor
digraph(Id) ->
   register(graph_server, spawn(?MODULE, graph_server, [#graph{graphId = Id, type = {digraph, "->"}}])).

graph(Id) ->
   register(graph_server, spawn(?MODULE, graph_server, [#graph{graphId = Id, type={graph, "--"}}])).

% -- Destructor
delete() ->
   graph_server ! {stop, self()},
   receive
      stopped -> done
   end.

% -- Methods
add_node(Id) -> graph_server ! {add_node, Id}.
add_edge(NodeOne, NodeTwo) -> graph_server ! {add_edge, NodeOne, NodeTwo}.
add_cluster(Label, Edges) -> graph_server ! {add_cluster, Label, Edges}.
add_cluster_nodes(Label, Nodes) -> graph_server ! {add_cluster_nodes, Label, Nodes}.
set_env(Env) -> graph_server ! {env, Env}.
set_shape(Shape, Nodes) -> graph_server ! {set_shapes, Shape, Nodes}.
to_dot(File) -> graph_server ! {to_dot, File}.
to_file(File, Format) -> graph_server ! {to_file, File, Format}.

% -- Server/Dispatcher
graph_server(Graph) ->
   receive
      {env, Env} ->
         graph_server(Graph#graph{env=Env});

      {add_cluster, Label, Edges} ->
         graph_server(add_cluster_server(Graph, {Label, Edges}));

      {add_cluster_nodes, Label, Nodes} ->
         graph_server(add_cluster_nodes_server(Graph, {Label, Nodes}));

      {set_shapes, Shape, Nodes} ->
         graph_server(set_shapes(Graph, Shape, Nodes));

      {add_node, Id} -> 
         graph_server(add_node(Graph, Id));

      {add_edge, NodeOne, NodeTwo} -> 
         graph_server(add_edge(Graph, NodeOne, NodeTwo));

      {to_dot, File} ->
         to_dot(Graph, File),
         graph_server(Graph);

      {to_file, File, Format} -> 
         to_file(Graph, File, Format),
         #graph{graphId = Id, type = Type} = Graph,
         graph_server(#graph{graphId = Id, type = Type});

      {value, Pid} -> 
         Pid ! {value, Graph}, 
         graph_server(Graph);

      {stop, Pid} -> Pid!stopped
   end.


% -- Implementation
add_cluster_server(Graph = #graph{graphId = GraphId, cluster=Clusters, numClusters=Num},{Label, Edges}) ->
   io:format("Add cluster ~s to graph ~s !~n",[Label, GraphId]),
   Graph#graph{cluster =Clusters++[{Num, Label, Edges}], numClusters = Num+1}.

add_cluster_nodes_server(Graph = #graph{graphId = GraphId, cluster_nodes = ClNodes, numClusters=Num}, {Label, Nodes}) ->
   io:format("Add cluster nodes ~s to graph ~s !~n",[Label, GraphId]),
   Graph#graph{cluster_nodes =ClNodes++[{Num, Label, Nodes}], numClusters = Num+1}.

add_node(Graph = #graph{graphId = GraphId, nodes=Nodes}, Id) ->
   io:format("Add node ~s to graph ~s !~n",[Id, GraphId]),
   Graph#graph{nodes=Nodes++[Id]}.

set_shapes(Graph=#graph{shapes = ShapesMap}, Shape, Nodes) when is_list(Nodes) ->
   NewShapesMap = case maps:find(Shape, ShapesMap) of
                    error -> ShapesMap#{Shape => Nodes};
                    ListNodes -> ShapesMap#{Shape => ListNodes++Nodes}
                 end,
   Graph#graph{shapes = NewShapesMap};
set_shapes(Graph=#graph{shapes = ShapesMap}, Shape, Node) ->
   NewShapesMap = case maps:find(Shape, ShapesMap) of
                     error -> ShapesMap#{Shape => [Node]};
                     ListNodes -> ShapesMap#{Shape => ListNodes++[Node]}
                  end,
   Graph#graph{shapes = NewShapesMap}.


add_edge(Graph = #graph{graphId = GraphId, edges =Edges}, NodeOne, NodeTwo) ->
   io:format("Add edge ~s -> ~s to graph ~s !~n", [NodeOne, NodeTwo, GraphId]),
   Graph#graph{edges= Edges ++ [{NodeOne, NodeTwo}]}.

to_dot(#graph{graphId = GraphId, type = Type, graphOptions= _,
   nodes=Nodes, edges=Edges, cluster=Clusters, cluster_nodes = ClNodes, shapes = ShapesMap}, File)->
   {GraphType, EdgeType} = Type,
   
   % open file
   {ok, IODevice} = file:open(File, [write]),

   % print graph
   io:format(IODevice, "~s ~s {~n", [GraphType, GraphId]),

   % print cluster
   lists:foreach(
      fun({Num, Label, Edges}) ->
         io:format(IODevice, "\tsubgraph cluster_~p{~n\tstyle=filled;~n\tnode [style=filled];~n",[Num]),
         lists:foreach(
            fun(Edge) ->
               {NodeOne, NodeTwo} = Edge,
               io:format(IODevice, "\t  ~s ~s ~s;~n",[NodeOne, EdgeType, NodeTwo])
            end,
            Edges),
         io:format(IODevice, "\t  label = \"~s\";~n\t}~n", [Label]) end,
      Clusters),

   % print cluster nodes
   lists:foreach(
      fun({Num, Label, Nodes}) ->
         io:format(IODevice, "\tsubgraph cluster_~p{~n\tstyle=filled;~n\tnode [style=filled];~n",[Num]),
         lists:foreach(
            fun(Node) ->
               io:format(IODevice, "\t  ~s;~n",[Node])
            end,
            Nodes),
         io:format(IODevice, "\t  label = \"~s\";~n\t}~n", [Label]) end,
      ClNodes),

   % print nodes
   lists:foreach(
      fun(Node) ->
            io:format(IODevice, "  ~s;~n",[Node]) 
      end, 
      Nodes
   ),

   % print edges
   lists:foreach(
      fun(Edge) ->
            {NodeOne, NodeTwo} = Edge,
            io:format(IODevice, "  ~s ~s ~s;~n",[NodeOne, EdgeType, NodeTwo]) 
      end, 
      Edges
   ),

   io:format("map~p~n", [ShapesMap]),
   % set shapes
   lists:foreach(
      fun({Shape, Nodes}) ->
         lists:foreach(
            fun(Node) ->
               io:format(IODevice, "  ~s [shape = ~s];~n",[Node, Shape])
            end,
            Nodes)
      end,
   maps:to_list(ShapesMap)),

% close file
   io:format(IODevice, "}~n", []),
   file:close(IODevice).

to_file(Graph, File, Format) ->
   {A1,A2,A3} = now(),
   DotFile = lists:concat([File, ".dot-", A1, "-", A2, "-", A3]),
   to_dot(Graph, DotFile),
   DotCommant = lists:concat(["dot -T", Format, " -o", File, " ", DotFile]),
   os:cmd(DotCommant),
   file:delete(DotFile).