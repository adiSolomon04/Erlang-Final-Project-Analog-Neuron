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
-export([create_wave/2]).


%%---------------------------------------------------------
%%      Creating PDM PCM input from PCM file
%%---------------------------------------------------------
pdm_process(FileName, SendingRate, NeuronPid)->
  sending_pdm_to_first_neuron.


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
  PI2=6.283185307179586476925286766559, %%2*math:pi(),
  Step = 200000,
  Samp_rate_ratio = round(Clk_freq/Samp_freq + 0.5),
  %% Calc first Loop
  Sine_freq =Start_freq+ 1/Step,	% Waveform frequency [Hz]
  Phase = PI2*Sine_freq /(1.0*Clk_freq),

  %% PCM File
  file:delete("input_wave.pcm"),
  {_, PCM_file} = file:open("input_wave.pcm", [raw]), %% [append]s for not truncating.
  {_, PCM_file_1} = file:open("check.txt", [write, raw]),

   case (End_freq-Start_freq)*Step of
            Loops when Loops>0 ->
              write_file_loop_avg(0, Sine_freq, Phase, 1, Loops, Step, PI2, Clk_freq, Amplitude, Samp_rate_ratio, PCM_file);
            0 -> io:format("err in Loops number~n"),
              write_file_loop_avg(0, Sine_freq,  Phase, 1, 10000000, Step, PI2, Clk_freq, Amplitude, 1, PCM_file);
            _ -> io:format("err in Loops number~n"),
              write_file_loop_avg(0, Sine_freq,  Phase, 1, 10000000, Step, PI2, Clk_freq, Amplitude, Samp_rate_ratio, PCM_file)
          end.


  %% writes sin wave to the pcm file
  %% sin wave with a changing freq
  %% (starts in Sine_freq, ends in Sin_freq+Step*Loops

  write_file_loop_avg(Samp_sum, _, Phase, Samp_rate_ratio, 0, _, _, _, Amplitude, Samp_rate_ratio, _)->
    Sine_wave = Amplitude * math:sin(Phase),
    Samp_in = Sine_wave,
    Samp_write = round((Samp_in+Samp_sum)/Samp_rate_ratio),
    write_to_file_3bytes(Samp_write),
    doneWriting; %% write to PCM.

  write_file_loop_avg(_, _, _, _, 0, _, _, _, _, _, _)->
    doneWriting;

  write_file_loop_avg(Samp_sum, Sine_freq, Phase, Samp_rate_count, Loops, Step, PI2, Clk_freq, Amplitude, Samp_rate_ratio, PCM_file)->
    Sine_wave = Amplitude * math:sin(Phase),
    Samp_in = Sine_wave,
    %%io:format("print~p,~p~n",[Samp_rate_count, Samp_rate_ratio]),
    %io:format("~p~n",[Samp_rate_ratio]),
    case Samp_rate_count of
      Samp_rate_ratio ->
        Samp_write = round((Samp_in+Samp_sum)/(1.0*Samp_rate_ratio)),
        write_to_file_3bytes(Samp_write),
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
      PCM_file).



%% writes data to file. NOT Used
%% The binary writes int16 as two separate 8bit integers (as two bytes)
%% for reading need to multiple the 1st byte by 2^8 and
%% sum with the 2nd byte
write_to_file(Samp, PCM_file) when (Samp<32767) and (Samp>(-32767)) ->
  %int16 ,(short) with an amplitude of 1000 sine_wave is between 1000 to -1000 and short sign is 2^15=32768...in range
  Binary = <<Samp:16/integer>>,
  %io:format("print ~n~p", [Samp]),
  file:write_file("input_wave.pcm", Binary, [append]),
  file:write_file("check.txt", io_lib:format("~p, ~p~n",[Samp, Binary]), [append]);

write_to_file(Samp, PCM_file) when Samp>32767 ->
  Binary = <<32767:16/integer>>,
  file:write_file("input_wave.pcm", Binary, [append]);

write_to_file(Samp, PCM_file) when Samp<(-32767) ->
  Binary = <<-32767:16/integer>>,
  file:write_file("input_wave.pcm", Binary, [append]).


%% writes data to file.
%%%% The binary writes int16 as 3 separate 8bit integers
%%%% for reading need to multiple the 1st byte by 2^8 and
%%%% sum with the 2nd byte by 16, sum to third.
%%%%%% (Need to add '1' to the negatives 1st, 2nd bytes.
write_to_file_3bytes(Samp)->
  <<B1:8, B2_tmp:4, B3_tmp:4>> = <<Samp:16/integer>>,
  case Samp of
    _ when Samp<0 ->
      B2= <<15:4, B2_tmp:4>>,
      B3= <<15:4, B3_tmp:4>>;
    _ ->
      B2= <<0:4, B2_tmp:4>>,
      B3= <<0:4, B3_tmp:4>>
  end,
  file:write_file("input_wave.pcm", <<B1:8>>, [append]),
  file:write_file("input_wave.pcm", B2, [append]),
  file:write_file("input_wave.pcm", B3, [append]).