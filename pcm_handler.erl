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
              write_file_loop_avg(0, Sine_freq, Phase, 1, Loops, Step, PI2, Clk_freq, Amplitude, Samp_rate_ratio, FileName);
            0 -> io:format("err in Loops number~n"),
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
    write_to_file_3bytes(Samp_write, FileName),
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
        Samp_write = round((Samp_in+Samp_sum)/(1.0*Samp_rate_ratio)),
        write_to_file_3bytes(Samp_write, FileName),
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
  write_to_file_3bytes(Samp, FileName),
  write_to_file_binary(Samp, FileName);
write_to_file(Samp, FileName) when Samp>32767 ->
  write_to_file_3bytes(32767, FileName),
  write_to_file_binary(32767, FileName);
write_to_file(Samp, FileName) when Samp<(-32767) ->
  write_to_file_3bytes(-32767, FileName),
  write_to_file_binary(-32767, FileName).


%%---------------------------------------------------------
%%      Writing to file functions.
%% -- write_to_file_3bytes : for use in python
%% -- write_to_file_binary : for use in erlang
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


%% writes 4 bytes per integer.
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
write_zeros(0, FileName) -> done;
write_zeros(Num, FileName) ->
  file:write_file("try.pcm",integer_to_binary(0) , [append]),
  write_zeros(Num-1, FileName).


%% writing integers as text,
%% worked only with 1 term :(
write_use_consult(Samp)->
  file:open("try.pcm", [write, raw]),
  file:write_file("try.pcm",io_lib:format("~p", [Samp]) , [append]),
  file:write_file("try.pcm", ".",[append]),
  file:write_file("try.pcm",io_lib:format("~p", [-5]) , [append]),
  file:write_file("try.pcm", ".",[append]),
  {ok, File} = file:open("try.pcm", [read]),
  {ok, Terms}=file:consult("try.pcm"),
  file:close(File),
  Terms.