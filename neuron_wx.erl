-module(neuron_wx).
-author("adisolo").

%% API
-export([start/0, handleButtonStart/2]).
-include_lib("wx/include/wx.hrl").

-record(data_launch, {env, net_size, net_conc, text_nodes, text_freq}).

%% Will get the pid of server
%% will send the information on button pressing
start() ->
  WX = wx:new(),

  %%Fonts
  FontTopHeader = wxFont:new(20, ?wxFONTFAMILY_ROMAN, ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_NORMAL),
  FontHeader = wxFont:new(18, ?wxFONTFAMILY_ROMAN, ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_NORMAL),
  FontSubHeader = wxFont:new(14, ?wxFONTFAMILY_ROMAN, ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_NORMAL),
  FontInfo = wxFont:new(12, ?wxFONTFAMILY_ROMAN, ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_NORMAL),

  %%Frame and components build
  Frame = wxFrame:new(wx:null(), ?wxID_ANY, "Analog Neuron - Resonator Network"),
  TopTxt = wxStaticText:new(Frame, ?wxID_ANY, "Analog Neuron - Resonator Network"),
  wxTextCtrl:setFont(TopTxt, FontTopHeader),


  %L Components
  %%% Configure
  TextConfiguration = wxStaticText:new(Frame, ?wxID_ANY, "Configure Next Network"),
  wxStaticText:setFont(TextConfiguration, FontHeader),
  TextNetType = wxStaticText:new(Frame, ?wxID_ANY, "Network Size"),
  wxStaticText:setFont(TextNetType, FontSubHeader),
  RButton17 = wxRadioButton:new(Frame, ?wxID_ANY, "17 Neurons", [{style, ?wxRB_GROUP}]),
  RButton4 =  wxRadioButton:new(Frame, ?wxID_ANY, "4 Neurons", []),
  TextDetectFreq = wxStaticText:new(Frame, ?wxID_ANY, "Detect Frequency"),
  wxStaticText:setFont(TextDetectFreq, FontSubHeader),
  TextCtrlFreqSelect = wxTextCtrl:new(Frame, ?wxID_ANY,  [{value, "104.2"}]),
  ButtonLaunchNet = wxButton:new(Frame, ?wxID_ANY, [{label, "LAUNCH NETWORK"}]), %{style, ?wxBU_LEFT}
  LaunchRec = #data_launch{env=wx:get_env(),
    net_size=RButton17,
    net_conc="not used yet",
    text_nodes="not used yet",
    text_freq= TextCtrlFreqSelect},



  %% Run Network
  TextTest = wxStaticText:new(Frame, ?wxID_ANY, "Test Launched Networks"),
  wxStaticText:setFont(TextTest, FontHeader),
  TextEnterFreq = wxStaticText:new(Frame, ?wxID_ANY, "Enter a changing sin"),
  wxStaticText:setFont(TextEnterFreq, FontSubHeader),
  %%
  TextBoxer = wxBoxSizer:new(?wxHORIZONTAL),
  TextFrom = wxStaticText:new(Frame, ?wxID_ANY, "From"),
  %wxStaticText:setFont(TextFrom, FontInfo),
  TextCtrlFromHz = wxTextCtrl:new(Frame, ?wxID_ANY,  [{value, "100"}]),
  TextToFreq = wxStaticText:new(Frame, ?wxID_ANY, "Hz, To"),
  %wxStaticText:setFont(TextToFreq, FontInfo),
  TextCtrlToHz = wxTextCtrl:new(Frame, ?wxID_ANY,  [{value, "106"}]),
  TextHz = wxStaticText:new(Frame, ?wxID_ANY, "Hz"),
  %wxStaticText:setFont(TextHz, FontInfo),
  lists:foreach(fun(X)-> wxBoxSizer:add(TextBoxer, X)end,
    [TextFrom, TextCtrlFromHz, TextToFreq, TextCtrlToHz, TextHz]),
  %%
  TextIntoSys = wxStaticText:new(Frame, ?wxID_ANY, "Into the System"),
  ButtonTest = wxButton:new(Frame, ?wxID_ANY, [{label, "TEST NETWORKS"}]), %{style, ?wxBU_LEFT}


  %FilePickerInput = wxFilePickerCtrl:new(Frame, ?wxID_ANY),
  %ButtonStart = wxButton:new(Frame, ?wxID_ANY, [{label, "Start"}]),

  %%%Buttons
  wxButton:connect(ButtonLaunchNet, command_button_clicked, [{callback, fun handleLaunchNet/2}, {userData, LaunchRec}]),


  %R Components
  TextNet = wxStaticText:new(Frame, ?wxID_ANY, "The Network"), %%?wxID_ANY
  wxTextCtrl:setFont(TextNet, FontHeader),



  %% bitmap
  PictureDraw = wxImage:new("Erlang_logo.png"),
  Picture = wxBitmap:new(PictureDraw),
  %% panel for picture
  Panel = wxPanel:new(Frame, [{size, {wxBitmap:getHeight(Picture), wxBitmap:getWidth(Picture)}}]),
  wxPanel:connect(Panel, paint, [{callback,fun(WxData, _)->panelPictureUpdate({Frame,PictureDraw}, WxData)end}]),


  %3 Components
  %TextOutput = wxStaticText:new(Frame, ?wxID_ANY, "Program Output"), %%?wxID_ANY
  %wxTextCtrl:setFont(TextOutput, FontHeader),



  %%Sizer Attachment
  % One big sizer vertical
  % split to two vertical(1, 2).
  % split 2 to two horizontal
  MainSizer = wxBoxSizer:new(?wxVERTICAL),
  MainSizerTop = wxBoxSizer:new(?wxHORIZONTAL),
  MainSizerTopL = wxBoxSizer:new(?wxVERTICAL),
  RadioButtonSizer = wxBoxSizer:new(?wxHORIZONTAL),
  MainSizerTopR = wxBoxSizer:new(?wxVERTICAL),
  %SizeR = wxSizer:fit(MainSizerR, Panel),
  %%MainSizerBottom = wxBoxSizer:new(?wxVERTICAL),

  wxSizer:add(MainSizer, TopTxt, [{flag, ?wxALIGN_TOP bor ?wxALIGN_CENTER}, {border, 8}]),
  wxSizer:addSpacer(MainSizer, 20),
  wxSizer:add(MainSizer, MainSizerTop, [{proportion, 1},{flag, ?wxEXPAND}]), %,[{flag, ?wxALIGN_CENTER}]),
  %%wxSizer:add(MainSizer, MainSizerBottom),
  wxSizer:addSpacer(MainSizerTop, 10),
  wxSizer:add(MainSizerTop, MainSizerTopL),%{flag, ?wxALIGN_LEFT},  {proportion, 1}, {flag, ?wxEXPAND}
  wxSizer:add(MainSizerTop, MainSizerTopR, [{proportion, 2}, {flag, ?wxEXPAND}]),%{flag, ?wxALIGN_RIGHT},
  wxSizer:addSpacer(MainSizerTop, 10),

  %%%% Assign to L
  %%%%
  wxSizer:add(RadioButtonSizer, RButton17),
  wxSizer:add(RadioButtonSizer, RButton4),

  %% Configure
  lists:foreach(fun(X)-> wxSizer:add(MainSizerTopL, X, [{flag, ?wxALL bor ?wxEXPAND}, {border, 4}]) end,
    [TextConfiguration, TextNetType, RadioButtonSizer, TextDetectFreq, TextCtrlFreqSelect,  ButtonLaunchNet]),
  wxSizer:addSpacer(MainSizerTopL, 10),
  %% Test
  lists:foreach(fun(X)-> wxSizer:add(MainSizerTopL, X, [{flag, ?wxALL bor ?wxEXPAND}, {border, 4}]) end,
  [TextTest, TextEnterFreq, TextBoxer, TextIntoSys, ButtonTest]),

  %%%% Assign to R
  %%%%
  wxSizer:addSpacer(MainSizerTopR, 6),
  wxSizer:add(MainSizerTopR, TextNet, [{flag, ?wxALIGN_CENTRE }, {border, 8}]),
  wxSizer:add(MainSizerTopR, Panel, [{flag, ?wxALIGN_RIGHT}, {border, 8}]),%, {proportion, 1}, ]),

  %% Assign to 3
  %%wxSizer:add(MainSizerBottom, TextOutput, [{flag, ?wxALL bor ?wxALIGN_CENTRE }, {border, 8}]),

  wxWindow:setSizer(Frame, MainSizer),
  %wxWindow:setSize(Frame, 418, 547),
  %%Show Frame
  wxFrame:show(Frame).
  %wxSizer:fitInside(MainSizerR, Panel).

handleButtonStart(WxData,_)->
  %Get the userdata
  Data=WxData#wx.userData,
  wx:set_env(Data),
  %FilePicker = Data#data.file,
  %Use the info
  Frame = wxFrame:new(wx:null(), ?wxID_ANY, "Print"),
  Text="hi",%%io_lib:format("The file is: ~p~n", [wxFilePickerCtrl:getPath(FilePicker)]),
  wxStaticText:new(Frame, ?wxID_ANY, Text),
  wxFrame:show(Frame).

% upload the picture to the panel
panelPictureUpdate({Frame,PictureDraw}, #wx{obj =Panel} ) ->
  timer:sleep(250),
  {Width, Height} = wxPanel:getSize(Panel),
  Size={Width, Height},
  io:format("~p~n", ["print"]),
  PictureDrawScaled = wxImage:scale(PictureDraw, round(Width*10/11), round(Height*10/11)),
  %% display picture
  Picture = wxBitmap:new(PictureDrawScaled),
  DC = wxPaintDC:new(Panel),
  wxDC:drawBitmap(DC, Picture, {0,0}),
  wxPaintDC:destroy(DC),
  wxWindow:updateWindowUI(Frame),
  ok.


handleLaunchNet(WxData, _) ->
  LaunchRec=WxData#wx.userData,

  Freq = wxTextCtrl:getValue(LaunchRec#data_launch.text_freq),
  case is_number(Freq) of
    false -> throw_err_and_exit; %% message box with error and exit this func.
    true -> Nodes = wxTextCtrl:getValue(LaunchRec#data_launch.text_nodes)
      %% check if all alive. if do - continue and run the program.
  end,


  RB17= LaunchRec#data_launch.net_size,
  case wxRadioButton:getValue(RB17) of
    false -> supervisor_with_neuron_4;
    true -> supervisor_neuron_17
  end.