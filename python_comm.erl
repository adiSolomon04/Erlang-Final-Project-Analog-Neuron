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
%% API
-export([]).

%%---------------------------------------------------------
%%      opening a Python instance erl-port
%%---------------------------------------------------------

%% How to open instance
%%%%Eshell V10.4.4  (abort with ^G)
%%%%1> python:start().
%%%%{error,python_not_found}
%%%%2> python:start([{python, "/bin/python3"}]).
%%%%{ok,<0.81.0>}

% http://erlport.org/docs/python.html#reference-manual

run_python()->
  {ok, CurrentDirectory} = file:get_cwd(),
  {ok, P}= python:start([
    {python_path, CurrentDirectory},
    {python, "python3"}]),
  python:call(P, graph_handler, plot_waves,[]).