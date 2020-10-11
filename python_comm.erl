%%%-------------------------------------------------------------------
%%% @author adisolo
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%% erl-port communication with python.
%%% @end
%%% Created : 17. Sep 2020 12:01
%%%-------------------------------------------------------------------
-module(python_comm).
-author("adisolo").
-compile(export_all).
-export([plot_graph/2]).

%%%===================================================================
%%% API
%%%===================================================================

%% Spawn a python instance for graph plotting.
%% Function is:
%% plot_acc_vs_freq_fromlist   Args=[file_data_name, start_freq, list]
%% plot_val_vs_time_fromlist   Args=[file_data_name, list]

%% NOT USED
%% plot_acc_vs_freq   Args=[file_data_name, start_freq]
%% plot_val_vs_time  Args=[file_data_name]

plot_graph(Function, Args)->
  spawn(fun() -> run_python(Function, Args) end).


%% spawn a process which
plot_graph_process(Function_Append,Function_Plot,Args_Plot)->
  io:format("gotr hereeeeeeeeeeeeeee"),
  {ok, CurrentDirectory} = file:get_cwd(),
  {ok, P}= python:start([
    {python_path, CurrentDirectory},
    {python, "python3"}]),
  plot_graph_process_loop(Function_Append,Function_Plot,Args_Plot,P).


plot_graph_process_loop(Function_Append,Function_Plot,Args_Plot,P)->
  receive
    plot -> io:format("plot~n"),python:call(P, graph_handler, Function_Plot,Args_Plot);
    List ->io:format("append~n"),python:call(P, graph_handler, Function_Append, [List]),
      plot_graph_process_loop(Function_Append,Function_Plot,Args_Plot,P)
  end.


%%%===================================================================
%%%      opening a Python instance erl-port
%%%===================================================================

%% How to open instance
%%%%Eshell V10.4.4  (abort with ^G)
%%%%1> python:start().
%%%%{error,python_not_found}
%%%%2> python:start([{python, "/bin/python3"}]).
%%%%{ok,<0.81.0>}

% http://erlport.org/docs/python.html#reference-manual

run_python(Function, Args)->
  {ok, CurrentDirectory} = file:get_cwd(),
  {ok, P}= python:start([
    {python_path, CurrentDirectory},
    {python, "python3"}]),
  python:call(P, graph_handler, Function, string_to_binary(Args)).


%%%===================================================================
%%% Internal functions
%%%===================================================================

%% transfer string to 'binary'
%% in order to transfer to 'str' in python
string_to_binary(List) ->
  [Head|Tail] = List,
  [list_to_binary(Head)|Tail].
  %lists:map(
  %  fun(X) -> case is_list(X) of
  %              true -> list_to_binary(X);
  %              _ -> X
  %            end
  %  end
  %, List).

%%%===================================================================
%%% Testing Transfer Time python
%%%===================================================================

%% Testing - adi
%List = pcm_handler:create_wave_list(0, 2.5, 1). %% 50 k
%python_comm:run_python(plot_val_vs_time_fromlist, ["not used", List]).

%% TEST RESULTS

%%% 7> python_comm:run_python(plot_val_vs_time_fromlist, ["not used", List1]). %% 50 k
%%% "Time: 0.324717 seconds" - other result are close.
%%% 8> %% 50 k
%%% 8> python_comm:run_python(plot_val_vs_time_fromlist, ["not used", List2]). %% 100 k
%%% "Time: 1.092377 seconds" - other result are close.
%%% 9> %% 100 k
%%% 9> python_comm:run_python(plot_val_vs_time_fromlist, ["not used", List3]). %% 200 k
%%% "Time: 4.655224 seconds"
%%% "Time: 5.91483 seconds"
%%% "Time: 3.813945 seconds"
%%% "Time: 5.219672 seconds"
%%% 10> %% 200 k
%%% 10> python_comm:run_python(plot_val_vs_time_fromlist, ["not used", List4]). %% 300 k
%%% "Time: 14.548159 seconds"
%%% "Time: 16.541054 seconds"
%%% "Time: 12.826313 seconds"
%%% 11> %% 300 k