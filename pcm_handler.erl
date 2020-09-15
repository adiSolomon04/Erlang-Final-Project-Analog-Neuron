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
-export([wave_gen/0, create_wave/2]).

%%---------------------------------------------------------
%%      Creating PDM PCM input from PCM file
%%---------------------------------------------------------
wave_gen()->
  cool

  .






%%---------------------------------------------------------
%%      Creating Our Own PCM sin File
%%---------------------------------------------------------
create_wave(Start_freq, End_freq)->
  %% Parameters
  Clk_freq = 1536000,		% Input PDM Clock frequency [Hz]
  Samp_freq = 8000,		% Output PCM Sample frequency [Hz]
        %Sine_freq=Start_freq,
        %Phase = 0,
  Amplitude = 1000,
  PI2=6.283185307179586476925286766559,
  Step = 20000,
  Samp_rate_ratio = round(Clk_freq/Samp_freq + 0.5),

  %% Calc first Loop
  Sine_freq =Start_freq+ 1/Step,	% Waveform frequency [Hz]
  Phase = PI2*Sine_freq /Clk_freq,

  %% PCM File
  file:delete("Input_wave.pcm"),
  {_, PCM_file} = file:open("Input_wave.pcm", [write, raw]), %% [append]s for not truncating.

   case (End_freq-Start_freq)*Step of
            Loops when Loops>0 ->
              write_file_loop(0, Sine_freq, Phase, 0, Loops, Step, PI2, Clk_freq, Amplitude, Samp_rate_ratio, PCM_file);
            _ -> io:format("err in Loops number~n"),
              write_file_loop(0, Sine_freq,  Phase, 0, 1000000, Step, PI2, Clk_freq, Amplitude, Samp_rate_ratio, PCM_file)
          end.



  %% writes sin wave to the pcm file
  %% sin wave with a changing freq
  %% (starts in Sine_freq, ends in Sin_freq+Step*Loops

  write_file_loop(Samp_sum, _, Phase, Samp_rate_ratio, 0, _, _, _, Amplitude, Samp_rate_ratio, PCM_file)->
    Sine_wave = Amplitude * math:sin(Phase),
    Samp_in = floor(Sine_wave),
    Samp_write = round((Samp_in+Samp_sum)/Samp_rate_ratio),
    write_to_file(Samp_write, PCM_file),
    doneWriting; %% write to PCM.

  write_file_loop(_, _, _, _, 0, _, _, _, _, _, _)->
    doneWriting;

  write_file_loop(Samp_sum, Sine_freq, Phase, Samp_rate_count, Loops, Step, PI2, Clk_freq, Amplitude, Samp_rate_ratio, PCM_file)->
    Sine_wave = Amplitude * math:sin(Phase),
    Samp_in = floor(Sine_wave),
    io:format("print~n~p~n",[Samp_rate_count]),
    io:format("~p~n",[Samp_rate_ratio]),
    case Samp_rate_count of
      Samp_rate_ratio ->
        Samp_write = round((Samp_in+Samp_sum)/Samp_rate_ratio),
        write_to_file(Samp_write, PCM_file),
        Samp = 0,
        Count = 0;
      _ ->
        Samp = Samp_in+Samp_sum,
        Count = Samp_rate_count+1
    end,

    write_file_loop(
      Samp,
      Sine_freq+ 1/Step,	% Waveform frequency [Hz]
      Phase + PI2*Sine_freq /Clk_freq,
      Count,
      Loops-1,
      Step,
      PI2,
      Clk_freq,
      Amplitude,
      Samp_rate_ratio,
      PCM_file).

write_to_file(Samp, PCM_file) when (Samp<32767) and (Samp>(-32767)) ->
  %int16 ,(short) with an amplitude of 1000 sine_wave is between 1000 to -1000 and short sign is 2^15=32768...in range
        %Binary = <<Samp:16/binary>>,   %% taking two bytes
  Binary = <<Samp:16>>,%%term_to_binary(Samp),
        %%io:format("~p~n",[byte_size(Binary)]),
  file:write_file("Input_wave.pcm", Binary, [append]);

write_to_file(Samp, PCM_file) when Samp>32767 ->
  Binary = <<32767:16>>,
  file:write_file("Input_wave.pcm", Binary, [append]);

write_to_file(Samp, PCM_file) when Samp<(-32767) ->
  Binary = <<-32767:16>>,
  file:write_file("Input_wave.pcm", Binary, [append]).



%% add avg to system