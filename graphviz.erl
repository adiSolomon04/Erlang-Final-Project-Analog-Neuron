-module(graphviz).
-export([digraph/1, graph/1, delete/0, add_node/1, add_edge/2, graph_server/1, to_dot/1, to_file/2]).
-export([graph4neurons/0, graph17neurons/0]).

% -- Constructor
digraph(Id) ->
   register(graph_server, spawn(?MODULE, graph_server, [{Id, {digraph, "->"}, [] ,[], []}])).

graph(Id) ->
   register(graph_server, spawn(?MODULE, graph_server, [{Id, {graph, "--"}, [] ,[], []}])).

% -- Destructor
delete() ->
   graph_server ! stop.


%% =============================
%% graphviz display Network
%% =============================
graph4neurons() ->
   graphviz:digraph("G"),
   Edges = [{afi1, afi21}, {afi21, afi22}, {afi22, afi23}, {afi23, afi1}],
   lists:foreach(fun({X,Y})->graphviz:add_edge(X, Y) end,Edges),
   graphviz:to_file("AuthorsTree.png", "png"),
   graphviz:delete().

graph17neurons() ->
   graphviz:digraph("G"),
   Edges = [{afi11, afi12},
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
   graphviz:to_file("AuthorsTree.png", "png"),
   graphviz:delete().

%% =============================


% -- Server/Dispatcher
graph_server(Graph) ->
   receive
      {add_node, Id} -> 
         graph_server(add_node(Graph, Id));

      {add_edge, NodeOne, NodeTwo} -> 
         graph_server(add_edge(Graph, NodeOne, NodeTwo));

      {to_dot, File} ->
         to_dot(Graph, File),
         graph_server(Graph);

      {to_file, File, Format} -> 
         to_file(Graph, File, Format),
         graph_server(Graph);

      {value, Pid} -> 
         Pid ! {value, Graph}, 
         graph_server(Graph);

      draw_17 ->
         graph_server(Graph);

      stop -> true
   end.

% -- Methods

add_node(Id) -> graph_server ! {add_node, Id}.
add_edge(NodeOne, NodeTwo) -> graph_server ! {add_edge, NodeOne, NodeTwo}.
to_dot(File) -> graph_server ! {to_dot, File}.
to_file(File, Format) -> graph_server ! {to_file, File, Format}.

% -- Implementation

add_node(Graph, Id) ->
   {GraphId, Type, GraphOptions, Nodes, Edges} = Graph,
   io:format("Add node ~s to graph ~s !~n",[Id, GraphId]),
   {GraphId, Type, GraphOptions, Nodes ++ [Id], Edges}.

add_edge(Graph, NodeOne, NodeTwo) ->
   {GraphId, Type, GraphOptions, Nodes, Edges} = Graph,
   io:format("Add edge ~s -> ~s to graph ~s !~n", [NodeOne, NodeTwo, GraphId]), 
   {GraphId, Type, GraphOptions, Nodes, Edges ++ [{NodeOne, NodeTwo}]}.

to_dot(Graph, File) ->
   {GraphId, Type, GraphOptions, Nodes, Edges} = Graph,
   {GraphType, EdgeType} = Type,
   
   % open file
   {ok, IODevice} = file:open(File, [write]),

   % print graph
   io:format(IODevice, "~s ~s {~n", [GraphType, GraphId]),

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

graph17()-> ok.