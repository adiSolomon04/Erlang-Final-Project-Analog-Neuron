%%%-------------------------------------------------------------------
%%% @author adisolo
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 10. Sep 2020 16:38
%%%-------------------------------------------------------------------
-module(pcm_handler).
-author("adisolo").
-compile(export_all).

%% API
-export([create_wave/3]).

%%---------------------------------------------------------
%%      Creating PDM input from PCM file
%%---------------------------------------------------------
%% FileName - the full file name
pdm_process(Terms, SendingRate) when is_list(Terms)->
  receive
    NeuronPid -> foreachMessageSendToFirstNeuron(Terms,0,0,SendingRate, NeuronPid)
  end;
pdm_process(FileName, SendingRate)->
  Terms = read_file_consult(FileName),
  receive
    NeuronPid -> foreachMessageSendToFirstNeuron(Terms,0,0,SendingRate, NeuronPid)
  end.


foreachMessageSendToFirstNeuron([],_,_,_, NeuronPid)->
  neuron_statem:stop(NeuronPid,[]),
  io:format("sent all messages\n"),
  os:cmd("notify-send Task complete_succesfully"),
  sccefully_send_all_message;
foreachMessageSendToFirstNeuron([Head|Tail],Rand_gauss_var,SendingRateCounter,SendingRate, NeuronPid)->
  if SendingRateCounter rem 100 == 0, SendingRateCounter =/= 0->
    if SendingRateCounter rem 10000 == 0-> io:format("wat to send ~p~n",[SendingRateCounter]);
      true -> ok
    end,

    receive
      X when X == SendingRateCounter-50 ->
        if SendingRateCounter rem 10000 == 10000-50-> io:format("SendingRateCounter~p~n",[SendingRateCounter]);
          true -> ok
        end
    end;
    true -> ok
  end,
  {NewNeuronPid,NewRand_gauss_var} = sendToFirstNeuron(Head,Rand_gauss_var,SendingRateCounter,SendingRate, NeuronPid),
  foreachMessageSendToFirstNeuron(Tail,NewRand_gauss_var,(SendingRateCounter+1) ,SendingRate, NewNeuronPid).


sendToFirstNeuron(Acc,Rand_gauss_var,SendingRateCounter,SendingRate, NeuronPid) ->
  %% translate Number to Bitstring
  if Acc > 524288 ->
    NewAcc=524288;
    Acc < -524288 ->
      NewAcc=-524288;
    true-> NewAcc=Acc
  end,
  if NewAcc > 32767 ->
    Bit = <<1>>,
    NewRand_gauss_var =32767;
    NewAcc < -32767 ->
      Bit = <<0>>,
      NewRand_gauss_var =-32767;
    true-> TempRand_gauss_var = Rand_gauss_var +32768 +NewAcc,
            if TempRand_gauss_var> 65536 -> NewRand_gauss_var =TempRand_gauss_var -65536,
                                            Bit = <<1>>;
              true -> NewRand_gauss_var=TempRand_gauss_var,
                      Bit = <<0>>
            end
    end,
  %% send message to the first neuron after SendingRate millisecond
  receive
    wait -> NewNeuronPid=function_wait(NeuronPid),
      S=self(),
      neuron_statem:sendMessage(NewNeuronPid,S,Bit, x),
      {NeuronPid,NewRand_gauss_var}
    after 0 ->
    if
      SendingRateCounter rem SendingRate == 0 -> timer:sleep(1);
    true -> ok
    end,
    NewNeuronPid= NeuronPid,
      S=self(),
      neuron_statem:sendMessage(NeuronPid,S,Bit, x),
    {NewNeuronPid,NewRand_gauss_var}
  end.


function_wait(NeuronPid)->
  receive
    stopWait ->NeuronPid;
    {stopWait,NewNeuronPid} ->NewNeuronPid

  end.

%%---------------------------------------------------------
%%      Creating Our Own PCM sin List
%%---------------------------------------------------------

%%%%% OPTIONAL Distribute Sine creations
%% Can get a list of output files and write to multiple files.
%% Use a gather function at the end.
%% Number of writes total: (End-Start)*200,000 /Samp Rate.

create_wave_list(Start_freq, End_freq, Samp_rate)->
  %% Parameters
  Clk_freq = 1536000,		% Input PDM Clock frequency [Hz]
  Samp_freq = 8000,		% Output PCM Sample frequency [Hz]
  Amplitude = 1000,
  PI2=6.283185307179586476925286766559, %%2*math:pi(),
  Step = 200000, %% 200000
  Samp_rate_ratio = round(Clk_freq/Samp_freq + 0.5),
  %% Calc first Loop
  Sine_freq =Start_freq+ 1/Step,	% Waveform frequency [Hz]
  Phase = PI2*Sine_freq /(1.0*Clk_freq),

  %% File Opening for writing
  % [write, raw] - deletes the prev content & enables write, writes fast.
  case (End_freq-Start_freq)*Step of
    Loops when Loops>0 ->
      io:format("~p~n", [Loops]),
      SinSample = write_list_loop_avg(0, Sine_freq, Phase, 1, Loops, Step, PI2, Clk_freq, Amplitude, case Samp_rate of
                                                                                           0 -> Samp_rate_ratio;
                                                                                           _ -> Samp_rate
                                                                                         end,[]);
    0 -> io:format("Running 1,000,000 Loops wuth Samp_rate as 1~n"),
      SinSample= write_list_loop_avg(0, Sine_freq,  Phase, 1, 10000000, Step, PI2, Clk_freq, Amplitude, 1,[]);
    _ -> io:format("err in Loops number~n"),
      SinSample = write_list_loop_avg(0, Sine_freq,  Phase, 1, 10000000, Step, PI2, Clk_freq, Amplitude, Samp_rate_ratio,[])
  end.


%% writes sin wave to the pcm file
%% sin wave with a changing freq
%% (starts in Sine_freq, ends in Sin_freq+Step*Loops

write_list_loop_avg(Samp_sum, _, Phase, Samp_rate_ratio, 0, _, _, _, Amplitude, Samp_rate_ratio,SinSample)->
  Sine_wave = Amplitude * math:sin(Phase),
  Samp_in = Sine_wave,
  Samp_write = round((Samp_in+Samp_sum)/Samp_rate_ratio),
  SinSampleNew = [Samp_write|SinSample],
  lists:reverse(SinSampleNew);

write_list_loop_avg(_, _, _, _, 0, _, _, _, _, _, SinSample)->
  lists:reverse(SinSample);

write_list_loop_avg(Samp_sum, Sine_freq, Phase, Samp_rate_count, Loops, Step, PI2, Clk_freq, Amplitude, Samp_rate_ratio, SinSample)->
  Sine_wave = Amplitude * math:sin(Phase),
  Samp_in = Sine_wave,
  case Samp_rate_count of
    Samp_rate_ratio ->

      if (Loops rem 10000) == 0 -> io:format("print ~p~n", [Loops]);
        true -> ok
      end,


      Samp_write = round((Samp_in+Samp_sum)/(1.0*Samp_rate_ratio)),
      SinSampleNew = [Samp_write|SinSample],
      Samp = 0,
      Count = 1;
    _ ->
      Samp = Samp_in+Samp_sum,
      Count = Samp_rate_count+1,
      SinSampleNew = SinSample
  end,

  write_list_loop_avg(
    Samp,
    Sine_freq+ 1/Step,	% Waveform frequency [Hz]
    Phase + PI2*(Sine_freq+ 1/Step) /Clk_freq,
    Count,
    Loops-1,
    Step,
    PI2,
    Clk_freq,
    Amplitude,
    Samp_rate_ratio,
    SinSampleNew).

%%---------------------------------------------------------
%%      Creating Our Own PCM sin File
%%---------------------------------------------------------

%%%%% OPTIONAL Distribute Sine creations
%% Can get a list of output files and write to multiple files.
%% Use a gather function at the end.
%% Number of writes total: (End-Start)*200,000 /Samp Rate.

create_wave(Start_freq, End_freq, Samp_rate)->

  %% will be input
  %% file name without '.pcm'
  FileName = "input_wave",

  %% Parameters
  Clk_freq = 1536000,		% Input PDM Clock frequency [Hz]
  Samp_freq = 8000,		% Output PCM Sample frequency [Hz]
  Amplitude = 1000,
  PI2=6.283185307179586476925286766559, %%2*math:pi(),
  Step = 200000,
  Samp_rate_ratio = round(Clk_freq/Samp_freq + 0.5),
  %% Calc first Loop
  Sine_freq =Start_freq+ 1/Step,	% Waveform frequency [Hz]
  Phase = PI2*Sine_freq /(1.0*Clk_freq),

  %% File Opening for writing
  % [write, raw] - deletes the prev content & enables write, writes fast.
  {ok, PcmFile}= file:open(FileName++".pcm", [write, raw]),
  {ok, PcmFile_erl}=file:open(FileName++"_erl.pcm", [write, raw]),

   case (End_freq-Start_freq)*Step of
            Loops when Loops>0 ->
              io:format("~p~n", [Loops]),
              write_file_loop_avg(0, Sine_freq, Phase, 1, Loops, Step, PI2, Clk_freq, Amplitude, case Samp_rate of
                                                                                                   0 -> Samp_rate_ratio;
                                                                                                   _ -> Samp_rate
                                                                                                 end, FileName);
            0 -> io:format("Running 1,000,000 Loops wuth Samp_rate as 1~n"),
              write_file_loop_avg(0, Sine_freq,  Phase, 1, 10000000, Step, PI2, Clk_freq, Amplitude, 1, FileName);
            _ -> io:format("err in Loops number~n"),
              write_file_loop_avg(0, Sine_freq,  Phase, 1, 10000000, Step, PI2, Clk_freq, Amplitude, Samp_rate_ratio, FileName)
          end,
  file:close(PcmFile),
  file:close(PcmFile_erl).


  %% writes sin wave to the pcm file
  %% sin wave with a changing freq
  %% (starts in Sine_freq, ends in Sin_freq+Step*Loops

  write_file_loop_avg(Samp_sum, _, Phase, Samp_rate_ratio, 0, _, _, _, Amplitude, Samp_rate_ratio, FileName)->
    Sine_wave = Amplitude * math:sin(Phase),
    Samp_in = Sine_wave,
    Samp_write = round((Samp_in+Samp_sum)/Samp_rate_ratio),
    write_to_file(Samp_write, FileName),
    doneWriting; %% write to PCM.

  write_file_loop_avg(_, _, _, _, 0, _, _, _, _, _, _)->
    doneWriting;

  write_file_loop_avg(Samp_sum, Sine_freq, Phase, Samp_rate_count, Loops, Step, PI2, Clk_freq, Amplitude, Samp_rate_ratio, FileName)->
    Sine_wave = Amplitude * math:sin(Phase),
    Samp_in = Sine_wave,
    %%io:format("print~p,~p~n",[Samp_rate_count, Samp_rate_ratio]),
    %io:format("~p~n",[Samp_rate_ratio]),
    case Samp_rate_count of
      Samp_rate_ratio ->

        if (Loops rem 10000) == 0 -> io:format("print ~p~n", [Loops]);
          true -> ok
        end,


        Samp_write = round((Samp_in+Samp_sum)/(1.0*Samp_rate_ratio)),
        write_to_file(Samp_write, FileName),
        Samp = 0,
        Count = 1;
      _ ->
        Samp = Samp_in+Samp_sum,
        Count = Samp_rate_count+1
    end,

    write_file_loop_avg(
      Samp,
      Sine_freq+ 1/Step,	% Waveform frequency [Hz]
      Phase + PI2*(Sine_freq+ 1/Step) /Clk_freq,
      Count,
      Loops-1,
      Step,
      PI2,
      Clk_freq,
      Amplitude,
      Samp_rate_ratio,
      FileName).


%% writes data to file.
write_to_file(Samp, FileName) when (Samp<32767) and (Samp>(-32767)) ->
  %write_to_file_3bytes(Samp, FileName),
  write_file_consult(Samp, FileName);
write_to_file(Samp, FileName) when Samp>32767 ->
  %write_to_file_3bytes(32767, FileName),
  write_file_consult(32767, FileName);
write_to_file(Samp, FileName) when Samp<(-32767) ->
  %write_to_file_3bytes(-32767, FileName),
  write_file_consult(-32767, FileName).


%%---------------------------------------------------------
%%      Acc to File Writing - for graph plotting
%%---------------------------------------------------------

acc_process(FileName) ->
  %%% add open for writing and closing.
  {ok, PcmFile}= file:open(FileName++".pcm", [write, raw]),

  acc_loop(FileName),
  file:close(PcmFile).

acc_loop(FileName)->

  receive
    {_, [Num]} when is_number(Num)->
      write_to_file_3bytes(round(Num), FileName),
      %io:format("acc ~p~n", [round(Num)]),
      acc_loop(FileName);
    done -> killed
  end.

%% Same, But sends bit to timing process.
acc_process(FileName, Pid_timing,PidSender) ->
  %%% add open for writing and closing.
  {ok, PcmFile}= file:open(FileName++".pcm", [write, raw]),

  Acc = acc_loop(FileName, Pid_timing,0,PidSender,[]),
  io:format("start saving~n"),
  python_comm:plot_graph(plot_acc_vs_freq_fromlist,["output_wave.pcm",100,Acc]),
  io:format("end saving~n"),

  %lists:foreach(fun({X,N})->write_to_file_3bytes(round(X), FileName),io:format("~p~n",[N]) end,lists:zip(Acc,lists:seq(1,lists:flatlength(Acc)))),
  file:close(PcmFile).

acc_loop(FileName, Pid_timing,GotMessageCounter,PidSender,TODELETE)->
  if GotMessageCounter rem 100 == 50 -> PidSender!GotMessageCounter,io:format("gotMessageCounter~p\n",[GotMessageCounter]);
    true -> ok
  end,

  receive
    {_, [Num]} when is_number(Num)->
      TIME1 = erlang:timestamp(),
      TODELETE2 = [round(Num)|TODELETE],
      %write_to_file_3bytes(round(Num), FileName),
      Pid_timing!{timer:now_diff(erlang:timestamp(), TIME1),<<1>>},
      %io:format("acc ~p~n", [round(Num)]),
      acc_loop(FileName, Pid_timing,GotMessageCounter+1,PidSender,TODELETE2);
    done -> io:format("got done"), killed , TODELETE
  end.




acc_process_appendData(Pid_timing,PidSender,PidPlotGraph) ->
  %%% add open for writing and closing.

  Acc = acc_appendData_loop( Pid_timing,0,PidSender,PidPlotGraph,[]),
  PidPlotGraph!plot,
  io:format("exit acc~n").

  %lists:foreach(fun({X,N})->write_to_file_3bytes(round(X), FileName),io:format("~p~n",[N]) end,lists:zip(Acc,lists:seq(1,lists:flatlength(Acc)))),

acc_appendData_loop(Pid_timing,GotMessageCounter,PidSender,PidPlotGraph,ListAcc)->
  if GotMessageCounter rem 100 == 50 -> PidSender!GotMessageCounter,
        if GotMessageCounter rem 10000 == (10000-50)-> io:format("gotMessageCounter~p\n",[GotMessageCounter]);
        true -> ok
      end;
    true -> ok
  end,

  receive
    {_, [Num]} when is_number(Num)->
      TIME1 = erlang:timestamp(),
      ListAccNew = [round(Num)|ListAcc],
      %write_to_file_3bytes(round(Num), FileName),
      Pid_timing!{timer:now_diff(erlang:timestamp(), TIME1),<<1>>},
      %io:format("acc ~p~n", [round(Num)]),
      if GotMessageCounter rem 50000 == 0 -> PidPlotGraph!ListAcc, ListAccFinal =[];
        true -> ListAccFinal = ListAccNew
      end,
      acc_appendData_loop(Pid_timing,GotMessageCounter+1,PidSender,PidPlotGraph,ListAccFinal);
    done -> io:format("got done") , PidPlotGraph!ListAcc
  end.

%%---------------------------------------------------------
%%      Timing process
%%---------------------------------------------------------
% used for determining time passing.
% will be used in the future for wx process.
% will tell us that there are sill computations
timing_process(Pid_wx)->
  Time = erlang:timestamp(),
  timing_loop(Pid_wx, Time).

timing_loop(Pid, Time)->
  receive
    {X,_} -> case timer:now_diff(erlang:timestamp(), Time) of
              Diff when Diff >1000000 -> io:format("~p 1 second passed~p~n",[X,Diff]), timing_loop(Pid, erlang:timestamp());
             _ -> timing_loop(Pid, Time)
         end
  end.


%%---------------------------------------------------------
%%      Writing, Reading to file functions.
%% -- write_to_file_3bytes : for use in python
%% -- write_file_consult, read_file_consult : for use in erlang
%%---------------------------------------------------------

%% writes data to file.
%%%% The binary writes int16 as 3 separate 8bit integers
%%%% for reading need to multiple the 1st byte by 2^8 and
%%%% sum with the 2nd byte by 16, sum to third.
%%%%%% (Need to add '1' to the negatives 1st, 2nd bytes.
write_to_file_3bytes(Samp, FileName)->
  <<B1:8, B2_tmp:4, B3_tmp:4>> = <<Samp:16/integer>>,
  case Samp of
    _ when Samp<0 ->
      B2= <<15:4, B2_tmp:4>>,
      B3= <<15:4, B3_tmp:4>>;
    _ ->
      B2= <<0:4, B2_tmp:4>>,
      B3= <<0:4, B3_tmp:4>>
  end,
  file:write_file(FileName++".pcm", <<B1:8>>, [append]),
  file:write_file(FileName++".pcm", B2, [append]),
  file:write_file(FileName++".pcm", B3, [append]).


%% writing integers as text,
write_file_consult(Samp,FileName)->
  file:write_file(FileName++"_erl.pcm",io_lib:format("~p", [Samp]) , [append]),
  file:write_file(FileName++"_erl.pcm", ".\n",[append]).

%% reading integers as text,
%%% File Name with '.pcm'
read_file_consult(FileName)->
  {ok, File} = file:open(FileName, [read]),
  {ok, Terms}=file:consult(FileName),
  file:close(File),
  Terms.

%% writes 4 bytes per integer. NOT USED
%% for reading use read(_, 4)
%% and convert to integer using 'binary_to_integer'
%%%%%%% Doesnt work for negative numbers.
write_to_file_binary(Samp, FileName)->
  A=integer_to_binary(Samp),
  file:open("try.pcm", [write, raw]),
  write_zeros(6-byte_size(A), FileName),
  file:write_file("try.pcm",integer_to_binary(Samp) , [append]),
  {ok, File}=file:open("try.pcm", [read, raw, binary]),
  {ok, Data}=file:read(File, 6),
  file:close(File),
  binary_to_integer(Data).
write_zeros(0, _) -> done;
write_zeros(Num, FileName) ->
  file:write_file("try.pcm",integer_to_binary(0) , [append]),
  write_zeros(Num-1, FileName).



%%---------------------------------------------------------
%%      Testing write time
%%---------------------------------------------------------

%% we want to write millions of numbers to a file (using 'write_3_bytes')
%% The goal is to write with the least amount of time.
%% I will try to write 4 mill numbers, using a 'writing process'.
%% The process will receive a List of size:
%% 1000, 10000, 100000 and so on.
%% The time will be captured.

test_timing_write()->
  %% Each number should be an int16.
  Length=1000000,
  List4mill = lists:map(fun(_)-> rand:uniform(65534)-32767 end, lists:seq(1,Length)),
  ArgList=[{1000,"test1000"}, {10000,"test10000"},{100000,"test100000"}],
  lists:map(fun(X)->test_timing_send_list(List4mill, X) end, ArgList).


test_timing_send_list(List4mill, {SizeList,FileName})->
  file:open(FileName++".pcm", [write, raw]),
  MyPid=self(),
  spawn(pcm_handler, split_send, [SizeList, MyPid, [], List4mill]),
  TimeStart=erlang:timestamp(),
  TimeEnd = test_timing_write_list(FileName),
  {timer:now_diff(TimeEnd, TimeStart)/1000000, FileName}.


test_timing_write_list(FileName)->
  receive
    done -> erlang:timestamp();
    List -> lists:foreach(fun(X)->write_to_file_3bytes(X, FileName) end, List), test_timing_write_list(FileName)
  end.

%% Split to size and send.
split_send(_, Pid, List1, [])->
  Pid!List1,
  Pid!done;
split_send(Size, Pid, List1, List2)->
  Pid!List1,
  {_List1, _List2}=lists:split(Size, List2),
  split_send(Size, Pid, _List1, _List2).


