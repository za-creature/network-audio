unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Windows, Classes, SysUtils, FileUtil, LResources, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, SyncObjs, datagram;

{$i common.inc}

type
  { TUI }

  TUI = class(TForm)
    Console: TMemo;
    StartStopButton: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure StartStopButtonClick(Sender: TObject);
  private
    crit:TCriticalSection;
    FBuffer:pByte;
    FSilenceData:byte;
    FBufferSize, FPacketSize:dword;
    FFrameSize, FWritePointer, FPacketPointer:dword;
    FServerSocket:TDatagramSocket;
    FSync:TCriticalSection;
    FSleep:TEvent;
  public
    procedure ConsolePut(s:ansistring);
    procedure OnDataHeader(numChannels, samplesPerSecond, bytesPerSample:dword);
    procedure OnData(data:pByte; numFrames:dword);
    procedure Flush();
  end;
  TInitCallback=procedure(numChannels, samplesPerSecond, bytesPerSample:dword) of object;
  TDataCallback=procedure(data:pByte; numFrames:dword) of object;
  TFlushCallback=procedure() of object;
  TWASAPIMainProc=procedure(buffSize:dword; ic:pointer; dc:pointer; fc:pointer);cdecl;
  TWASAPIShutdownProc=procedure();cdecl;

  TWASAPIInterface=class(TThread)
    FbuffSize:dword;
    Fic:TInitCallback;
    Fdc:TDataCallback;
    Ffc:TFlushCallback;
    constructor Create(buffSize:dword; ic:TInitCallback; dc:TDataCallback; fc:TFlushCallback);
    procedure Execute();override;
  end;
  TCallback=procedure of object;
  TProcedureRunner=class(TThread)
    FCallback:TCallback;
    public
      constructor Create(Callback:TCallback);
      procedure Execute();override;
  end;

var
  UI: TUI;
  WASAPI:HMODULE;
  WASAPI_Main:TWASAPIMainProc;
  WASAPI_Shutdown:TWASAPIShutdownProc;
  WASAPI_Interface:TWASAPIInterface;
  WASAPI_Init_Called:boolean;

implementation

{ TWASAPIInterface }

procedure _ic(numChannels, samplesPerSecond, bytesPerSample:dword);cdecl;
begin
  WASAPI_Init_Called:=true;
  WASAPI_Interface.Fic(numChannels, samplesPerSecond, bytesPerSample);
end;

procedure _dc(data:pointer; numFrames:dword);cdecl;
begin
  WASAPI_Interface.Fdc(data, numFrames);
end;

procedure _fc();cdecl;
begin
  WASAPI_Interface.Ffc();
end;

constructor TWASAPIInterface.Create(buffSize:dword; ic:TInitCallback; dc:TDataCallback; fc:TFlushCallback);
begin
  inherited Create(false);
  FbuffSize:=buffSize;
  Fic:=ic;
  Fdc:=dc;
  Ffc:=fc;
end;

procedure TWASAPIInterface.Execute();
begin
  WASAPI_Init_Called:=false;
  WASAPI_Main(FBuffSize, @_ic, @_dc, @_fc);
  if(WASAPI_Init_Called=false)then
    UI.ConsolePut('  Failed. Unable to register wasapi client');
end;

{ TUI }

procedure TUI.StartStopButtonClick(Sender: TObject);
begin
  crit.Enter();
  if((Sender as TButton).Caption='Start')then
  begin
    ConsolePut('Loading libwasapi.dll...');
    WASAPI:=LoadLibrary('libwasapi.dll');
    if(WASAPI=0)then
    begin
      ConsolePut('  Failed: Could not load image libwasapi.dll');
      exit();
    end;
    WASAPI_Main:=TWASAPIMainProc(GetProcAddress(WASAPI, 'libwasapimain'));
    if(WASAPI_Main=nil)then
    begin
      ConsolePut('  Failed: Could not load import symbol libwasapimain from libwasapi.dll');
      exit();
    end;
    WASAPI_Shutdown:=TWASAPIShutdownProc(GetProcAddress(WASAPI, 'libwasapishutdown'));
    if(WASAPI_Shutdown=nil)then
    begin
      ConsolePut('  Failed: Could not load import symbol libwasapishutdown from libwasapi.dll');
      exit();
    end;
    ConsolePut('Starting audio capture');
    WASAPI_Interface:=TWASAPIInterface.Create(50, @OnDataHeader, @OnData, @Flush);
    (Sender as TButton).Caption:='Stop';
  end
  else
  begin
    ConsolePut('Releasing libwasapi.dll');
    WASAPI_Shutdown();
    FreeLibrary(WASAPI);
    WASAPI:=0;
    WASAPI_Main:=nil;
    WASAPI_Shutdown:=nil;
    (Sender as TButton).Caption:='Start';
  end;
  crit.Leave();
end;

procedure TUI.FormCreate(Sender: TObject);
begin
  crit:=TCriticalSection.Create();
  FPacketSize:=StrToInt(ParamStr(2));
  FServerSocket:=TDatagramSocket.Create(ParamStr(1), 325);
  FSync:=TCriticalSection.Create();
end;

procedure TUI.FormDestroy(Sender: TObject);
begin
  FServerSocket.Free();
  crit.Free();
  FSync.Free();
end;

procedure TUI.ConsolePut(s:ansistring);
begin
  Console.Lines.Add(s);
end;

procedure TUI.OnDataHeader(numChannels, samplesPerSecond, bytesPerSample:dword);
var
  formatStr:ansistring;
  data:TClientPacket;
begin
  data.packetType:=NAC_PACKET_SYNC;
  FFrameSize:=numChannels*bytesPerSample;
  FBufferSize:=FFrameSize*FPacketSize*samplesPerSecond div 1000;

  data.numChannels:=numChannels;
  data.sampleRate:=samplesPerSecond;
  data.bitsPerSample:=8*bytesPerSample;
  data.packetSize:=FPacketSize;

  FServerSocket.Send(data, sizeof(data));

  getmem(FBuffer, FBufferSize);
  FWritePointer:=0;
  FPacketPointer:=0;

  if(numChannels=1)then
    formatStr:='mono'
  else
    formatStr:='stereo';
  if(bytesPerSample=1)then
    FSilenceData:=$80
  else
    FSilenceData:=0;

  ConsolePut('Incoming data stream: '+formatStr+' '+IntToStr(bytesPerSample*8)+' bits '+IntToStr(samplesPerSecond)+'Hz ');
end;

procedure TUI.OnData(data:pByte; numFrames:dword);
var
  i:dword=0;
  s,j:dword;
begin
  while(i<numFrames*FFrameSize)do
  begin
    FBuffer[FWritePointer]:=data[i];
    inc(FWritePointer);
    inc(i);
    if(FWritePointer-FReadPointer=FPacketSize)or(FBufferSize+FWritePointer-FReadPointer=FPacketSize)then
      OnFlush();
  end;
end;

procedure TUI.OnFlush()
begin
end;

procedure TUI.Flush();
var
  packet:PClientPacket;
begin
  getmem(packet, 5+FBufferSize);

  while(FRunning)do
  begin
    FSleep.WaitFor(INFINITE);

    if(FRunning)then
    begin
      packet^.packetType:=NAC_PACKET_DATA;
      packet^.SyncId:=FPacketPointer;

      while(FWritePointer<FBufferSize)do
      begin
        FBuffer[FWritePointer]:=0;
        inc(FWritePointer);
      end;

      Move(FBuffer^, packet^.data, FBufferSize);
      FServerSocket.Send(packet^, 5+FBufferSize);

      inc(FPacketPointer);
      FWritePointer:=0;
    end;
  end;

  freemem(packet);
end;

{ TProcedureRunner }

constructor TProcedureRunner.Create(Callback:TCallback);
begin
  FCallback:=Callback;
  FreeOnTerminate:=true;
  inherited Create(false);
end;

procedure TProcedureRunner.Execute();
begin
  FCallback();
end;

initialization
  {$I mainform.lrs}

end.

