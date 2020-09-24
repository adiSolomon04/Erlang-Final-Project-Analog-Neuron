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

-export([plot_graph/2]).

%%%===================================================================
%%% API
%%%===================================================================

%% Spawn a python instance for graph plotting.
%% Function is:
%% plot_acc_vs_freq   Args=[file_data_name, start_freq]
%% plot_val_vs_time  Args=[file_data_name]

plot_graph(Function, Args)->
  spawn(fun() -> run_python(Function, Args) end).

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
  lists:map(
    fun(X) -> case is_list(X) of
                true -> list_to_binary(X);
                _ -> X
              end
    end
  , List).