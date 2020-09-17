-module(neuron_wx).
-author("adisolo").

%% API
-export([start/0]).

-include_lib("wx/include/wx.hrl").

start() ->

  %%Frame and components build
  WX = wx:new(),
  Frame = wxFrame:new(wx:null(), 1, "Top Frame"),
  TopTxt = wxStaticText:new(Frame, ?wxID_ANY, "Analog Neuron final Project"), %%?wxID_ANY

  %L Components
  TextConfiguration = wxStaticText:new(Frame, ?wxID_ANY, "Program Configuration"), %%?wxID_ANY
  TextSetNumNeurons = wxStaticText:new(Frame, ?wxID_ANY, "Enter number of Neurons per Layer"), %%?wxID_ANY
  TextCtrlNeurons = wxTextCtrl:new(Frame, ?wxID_ANY,  [{value, "example:4 3 6 7"}]),
  ButtonBuild = wxButton:new(Frame, ?wxID_ANY, [{label, "Build"}]), %{style, ?wxBU_LEFT}
  FilePickerInput = wxFilePickerCtrl:new(Frame, ?wxID_ANY),
  ButtonStart = wxButton:new(Frame, ?wxID_ANY, [{label, "Start"}]),


  %R Components


  %3 Components
  TextOutput = wxStaticText:new(Frame, ?wxID_ANY, "Program Output"), %%?wxID_ANY



  %%Font set
  Font = wxFont:new(20, ?wxFONTFAMILY_ROMAN, ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_NORMAL),
  wxTextCtrl:setFont(TopTxt, Font),
  Font2 = wxFont:new(18, ?wxFONTFAMILY_ROMAN, ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_NORMAL),
  wxTextCtrl:setFont(TextConfiguration, Font2),
  wxTextCtrl:setFont(TextOutput, Font2),
  Font3 = wxFont:new(12, ?wxFONTFAMILY_ROMAN, ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_NORMAL),
  wxTextCtrl:setFont(TextSetNumNeurons, Font3),


  %%Sizer Attachment
  MainSizer = wxBoxSizer:new(?wxVERTICAL),
  MainSizer2 = wxBoxSizer:new(?wxHORIZONTAL),
  MainSizerL = wxBoxSizer:new(?wxVERTICAL),
  MainSizerR = wxBoxSizer:new(?wxVERTICAL),
  MainSizer3 = wxBoxSizer:new(?wxVERTICAL),

  wxSizer:add(MainSizer, TopTxt, [{flag, ?wxALIGN_TOP bor ?wxALIGN_CENTER}, {border, 5}]),
  wxSizer:add(MainSizer, MainSizer2),
  wxSizer:add(MainSizer, MainSizer3),
  wxSizer:add(MainSizer2, MainSizerL, [{flag, ?wxALIGN_LEFT}, {border, 5}]),
  wxSizer:add(MainSizer2, MainSizerR, [{flag, ?wxALIGN_RIGHT}, {border, 5}]),

  %% Assign to L
  lists:foreach(fun(X)-> wxSizer:add(MainSizerL, X, [{flag, ?wxALL bor ?wxEXPAND}, {border, 8}]) end,
    [TextConfiguration, TextSetNumNeurons, TextCtrlNeurons, ButtonBuild, FilePickerInput, ButtonStart]),
  %wxSizer:add(MainSizerL, TextConfiguration, [{flag, ?wxALL bor ?wxEXPAND}, {border, 5}]),
  %wxSizer:add(MainSizerL, TextSetNumNeurons, [{flag, ?wxALL bor ?wxEXPAND}, {border, 5}]),
  %wxSizer:add(MainSizerL, TextCtrlL, [{flag, ?wxALL bor ?wxEXPAND}, {border, 5}]),

  %% Assign to R


  %% Assign to 3
  wxSizer:add(MainSizer3, TextOutput, [{flag, ?wxALL bor ?wxALIGN_CENTRE }, {border, 8}]),


  wxWindow:setSizer(Frame, MainSizer),
  %%Show Frame
  wxFrame:show(Frame).


