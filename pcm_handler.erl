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

%% API
-export([pdm_process/1, create_wave_list/3, acc_process_appendData/3, msgAcc_process/2, timing_process/1, msg_process/1]).

%%---------------------------------------------------------
%%      Creating PDM input from PCM file
%%---------------------------------------------------------
%% FileName - the full file name
pdm_process(SendingRate)->
  receive
    {config, NeuronPid, Supervisor}->
          put(neuron_pid, NeuronPid),
          put(supervisor, Supervisor),
          pdm_process_loop(SendingRate)
  end.

pdm_process_loop(SendingRate)->
  receive
    {supervisor, Supervisor}-> put(supervisor, Supervisor), pdm_process_loop(SendingRate);
    {test_network, Terms} when is_list(Terms)-> %% Test the Net
      foreachMessageSendToFirstNeuron(Terms,0,0,SendingRate, get(neuron_pid)), pdm_process_loop(SendingRate);
    wait ->
      NeuronPid=function_wait(kill_and_recover),
      put(neuron_pid, NeuronPid),
      pdm_process_loop(SendingRate);
    kill_and_recover ->
      receive
                          wait ->
                            NeuronPid=function_wait(kill_and_recover),
                            put(neuron_pid, NeuronPid),
                            pdm_process_loop(SendingRate)
                        end
  end.


foreachMessageSendToFirstNeuron([],_,_,_, NeuronPid)->
  neuron_statem:stop(NeuronPid,[]),
  os:cmd("notify-send Task complete_succesfully"),
  sccefully_send_all_message;
foreachMessageSendToFirstNeuron([Head|Tail],Rand_gauss_var,SendingRateCounter,SendingRate, NeuronPid)->
  if SendingRateCounter rem 100 == 0, SendingRateCounter =/= 0->
    %% wait for message to continue sending
    receive
      X when X == SendingRateCounter-50 ->
        if SendingRateCounter rem 10000 == 10000-50-> was_print;
          true -> ok
        end;
      wait -> S=self(),S!wait
    end;
    %% send message number to supervisor
    true -> ok
  end,
   if SendingRateCounter rem 500 == 0, SendingRateCounter =/= 0-> get(supervisor)!{from_pdm, 500};

     true -> ok
  end,
  {NewNeuronPid,NewRand_gauss_var,ToCountinueCount} = sendToFirstNeuron(Head,Rand_gauss_var,SendingRateCounter,SendingRate, NeuronPid),
  if
    ToCountinueCount == continue ->foreachMessageSendToFirstNeuron(Tail,NewRand_gauss_var,(SendingRateCounter+1) ,SendingRate, NewNeuronPid);
    ToCountinueCount == 0->foreachMessageSendToFirstNeuron(Tail,NewRand_gauss_var,1 ,SendingRate, NewNeuronPid);
    true -> problem
  end.


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
      {NewNeuronPid,NewRand_gauss_var,0};
    {supervisor, NewSupervisor}-> put(supervisor, NewSupervisor),
      NewNeuronPid= NeuronPid,
      S=self(),
      neuron_statem:sendMessage(NeuronPid,S,Bit, x),
      {NewNeuronPid,NewRand_gauss_var,continue}
    after 0 ->
    if
      SendingRateCounter rem SendingRate == 0 -> timer:sleep(1);
    true -> ok
    end,
    NewNeuronPid= NeuronPid,
      S=self(),
      neuron_statem:sendMessage(NeuronPid,S,Bit, x),
    {NewNeuronPid,NewRand_gauss_var,continue}
  end.


function_wait(NeuronPid)->
  receive
    stopWait ->NeuronPid;
    {stopWait,NewNeuronPid} -> put(neuron_pid, NewNeuronPid),NewNeuronPid

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
      write_list_loop_avg(0, Sine_freq, Phase, 1, Loops, Step, PI2, Clk_freq, Amplitude, case Samp_rate of
                                                                                           0 -> Samp_rate_ratio;
                                                                                           _ -> Samp_rate
                                                                                         end,[]);
    0 -> io:format("Running 1,000,000 Loops wuth Samp_rate as 1~n"),
      write_list_loop_avg(0, Sine_freq,  Phase, 1, 10000000, Step, PI2, Clk_freq, Amplitude, 1,[]);
    _ -> io:format("err in Loops number~n"),
      write_list_loop_avg(0, Sine_freq,  Phase, 1, 10000000, Step, PI2, Clk_freq, Amplitude, Samp_rate_ratio,[])
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
%%      Acc to File Writing - for graph plotting
%%---------------------------------------------------------
acc_process_appendData(Pid_timing,PidSender,PidPlotGraph) ->
  %%% add open for writing and closing.

  acc_appendData_loop( Pid_timing,0,PidSender,PidPlotGraph,[]),
  PidPlotGraph!plot.


acc_appendData_loop(Pid_timing,GotMessageCounter,PidSender,PidPlotGraph,ListAcc)->
  if GotMessageCounter rem 100 == 50 -> PidSender!GotMessageCounter, ok;
    true -> ok
  end,

  receive
    {_, [Num]} when is_number(Num)->
      TIME1 = erlang:timestamp(),
      ListAccNew = [round(Num)|ListAcc],
      Pid_timing!{timer:now_diff(erlang:timestamp(), TIME1),<<1>>},
      if GotMessageCounter rem 50000 == 0 -> PidPlotGraph!ListAccNew, ListAccFinal =[];
        true -> ListAccFinal = ListAccNew
      end,
      acc_appendData_loop(Pid_timing,GotMessageCounter+1,PidSender,PidPlotGraph,ListAccFinal);
    zeroCounter -> PidSenderNew = receive
                                    {set_pid_sender, Pid}  -> Pid
                                  after
                                    0 -> PidSender
                                  end,
      acc_appendData_loop(Pid_timing,0,PidSenderNew,PidPlotGraph,ListAcc);
    done -> PidPlotGraph!ListAcc
  end.


%%% 17 Neurons-----------------------------
msg_process(PidSender) ->
  %%% add open for writing and closing.
  msg_loop(0,PidSender).




msgAcc_process(Pid_timing,PidPlotGraph) ->
  %%% add open for writing and closing.

  msgAcc_loop( Pid_timing,PidPlotGraph,0,[]),
  PidPlotGraph!plot.

msg_loop(GotMessageCounter,PidSender)->
  receive
    zeroCounter -> io:format("zeroCounter - wait for Pid~n"),
      PidSenderNew = receive
                       {set_pid_sender, Pid}  -> io:format("Pid Sender~p~n",[Pid]),Pid
                     after
                       0 -> PidSender
                     end,
      msg_loop(0,PidSenderNew);
    {_, [Num]} when is_number(Num)->
      if GotMessageCounter rem 100 == 50 -> PidSender!GotMessageCounter,    if GotMessageCounter rem 10000 == (10000-50)-> io:format("gotMessageCounter~p\n",[GotMessageCounter]);
                                                                              true -> ok
                                                                            end;
        true -> ok
      end,
      msg_loop(GotMessageCounter+1,PidSender)
end.
%% zeroCounter -> msgAcc_loop(Pid_timing,PidPlotGraph,0,ListAcc);
%% done -> io:format("got done") , PidPlotGraph!ListAcc

msgAcc_loop(Pid_timing,PidPlotGraph,GotMessageCounter,ListAcc)->
  receive
    {_, [Num]} when is_number(Num)->
      TIME1 = erlang:timestamp(),
      ListAccNew = [round(Num)|ListAcc],
      %write_to_file_3bytes(round(Num), FileName),
      Pid_timing!{timer:now_diff(erlang:timestamp(), TIME1),<<1>>},
      %io:format("acc ~p~n", [round(Num)]),
      if GotMessageCounter rem 50000 == 0 -> PidPlotGraph!ListAccNew, ListAccFinal =[];
        true -> ListAccFinal = ListAccNew
      end,
      msgAcc_loop(Pid_timing,PidPlotGraph,GotMessageCounter+1,ListAccFinal);
    zeroCounter -> msgAcc_loop(Pid_timing,PidPlotGraph,0,ListAcc);
    done -> io:format("got done") , PidPlotGraph!ListAcc
  end.
%%% 17 Neurons-----------------------------


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


