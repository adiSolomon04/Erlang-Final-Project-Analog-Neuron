-module(neuron_wx).
-author("adisolo").

%% API
-export([start/0, handleButtonStart/2]).
-include_lib("wx/include/wx.hrl").

-record(data, {env, file}).

%% Will get the pid of server
%% will send the information on button pressing
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

  %Buttons
  wxButton:connect(ButtonStart, command_button_clicked, [{callback, fun handleButtonStart/2}, {userData, #data{env = wx:get_env(), file=FilePickerInput}}]),


  %R Components
  TextNet = wxStaticText:new(Frame, ?wxID_ANY, "Net Description"), %%?wxID_ANY

  %% bitmap
  PictureDraw = wxImage:new("Erlang_logo.png"),
  Picture = wxBitmap:new(PictureDraw),
  %% panel for picture
  Panel = wxPanel:new(Frame, [{size, {wxBitmap:getHeight(Picture), wxBitmap:getWidth(Picture)}}]),
  wxPanel:connect(Panel, paint, [{callback,fun(WxData, _)->panelPictureUpdate({Frame,PictureDraw}, WxData)end}]),


  %3 Components
  TextOutput = wxStaticText:new(Frame, ?wxID_ANY, "Program Output"), %%?wxID_ANY



  %%Font set
  Font = wxFont:new(20, ?wxFONTFAMILY_ROMAN, ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_NORMAL),
  wxTextCtrl:setFont(TopTxt, Font),
  Font2 = wxFont:new(18, ?wxFONTFAMILY_ROMAN, ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_NORMAL),
  wxTextCtrl:setFont(TextConfiguration, Font2),
  wxTextCtrl:setFont(TextOutput, Font2),
  wxTextCtrl:setFont(TextNet, Font2),

  Font3 = wxFont:new(12, ?wxFONTFAMILY_ROMAN, ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_NORMAL),
  wxTextCtrl:setFont(TextSetNumNeurons, Font3),


  %%Sizer Attachment
  % One big sizer vertical
  % split to two vertical(1, 2).
  % split 2 to two horizontal
  MainSizer = wxBoxSizer:new(?wxVERTICAL),
  MainSizer2 = wxBoxSizer:new(?wxHORIZONTAL),
  MainSizerL = wxBoxSizer:new(?wxVERTICAL),
  MainSizerR = wxBoxSizer:new(?wxVERTICAL),
  %SizeR = wxSizer:fit(MainSizerR, Panel),
  MainSizer3 = wxBoxSizer:new(?wxVERTICAL),

  wxSizer:add(MainSizer, TopTxt, [{flag, ?wxALIGN_TOP bor ?wxALIGN_CENTER}, {border, 5}]),
  wxSizer:add(MainSizer, MainSizer2, [{flag, ?wxEXPAND}]), %,[{flag, ?wxALIGN_CENTER}]),
  wxSizer:add(MainSizer, MainSizer3),
  wxSizer:add(MainSizer2, MainSizerL, [{border, 5}]),%{flag, ?wxALIGN_LEFT},
  wxSizer:add(MainSizer2, MainSizerR, [{border, 5},{flag, ?wxEXPAND}]),%{flag, ?wxALIGN_RIGHT},

  %% Assign to L
  lists:foreach(fun(X)-> wxSizer:add(MainSizerL, X, [{flag, ?wxALL bor ?wxEXPAND}, {border, 8}]) end,
    [TextConfiguration, TextSetNumNeurons, TextCtrlNeurons, ButtonBuild, FilePickerInput, ButtonStart]),
  %wxSizer:add(MainSizerL, TextConfiguration, [{flag, ?wxALL bor ?wxEXPAND}, {border, 5}]),
  %wxSizer:add(MainSizerL, TextSetNumNeurons, [{flag, ?wxALL bor ?wxEXPAND}, {border, 5}]),
  %wxSizer:add(MainSizerL, TextCtrlL, [{flag, ?wxALL bor ?wxEXPAND}, {border, 5}]),

  %% Assign to R
  wxSizer:add(MainSizerR, TextNet, [{flag, ?wxALL bor ?wxALIGN_CENTRE }, {border, 8}]),
  wxSizer:add(MainSizerR, Panel, [{flag, ?wxEXPAND}]),%, {proportion, 1}, {border, 8}]),

  %% Assign to 3
  wxSizer:add(MainSizer3, TextOutput, [{flag, ?wxALL bor ?wxALIGN_CENTRE }, {border, 8}]),

  %wxFrame:connect(Frame, paint, [{callback,
  %  fun(_Evt, _Obj) ->
  %    io:format("paint~n"),
  %    {Width, Height} = wxFrame:getSize(Frame),
  %    wxImage:scale(PictureDraw, Width, Height),
%
  %  end
  %}]),

  wxWindow:setSizer(Frame, MainSizer),
  %%Show Frame
  wxFrame:show(Frame),
  %wxSizer:fitInside(MainSizerR, Panel),
  {wxPanel:isShown(Panel),wxBitmap:ok(Picture)}.

handleButtonStart(WxData,_)->
  %Get the userdata
  Data=WxData#wx.userData,
  wx:set_env(Data#data.env),
  FilePicker = Data#data.file,
  %Use the info
  Frame = wxFrame:new(wx:null(), ?wxID_ANY, "Print"),
  Text=io_lib:format("The file is: ~p~n", [wxFilePickerCtrl:getPath(FilePicker)]),
  wxStaticText:new(Frame, ?wxID_ANY, Text),
  wxFrame:show(Frame).

% upload the picture to the panel
panelPictureUpdate({Frame,PictureDraw}, #wx{obj =Panel} ) ->
  io:format("paint~n"),
  {Width, Height} = wxPanel:getSize(Panel),
  PictureDrawScaled = wxImage:scale(PictureDraw, Width, Height),
  %% display picture
  Picture = wxBitmap:new(PictureDrawScaled),
  DC = wxPaintDC:new(Panel),
  wxDC:drawBitmap(DC, Picture, {0,0}),
  wxPaintDC:destroy(DC),
  ok.


