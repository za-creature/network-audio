unit paudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, portaudio, syncobjs;

type
  TPortAudioStreamer=class(TObject)
    protected
      FBuffer:pByte;
      FBufferSize:dword;
      FBufferReadPosition:dword;
      FBufferWritePosition:dword;
      FFrameSize:dword;
      FSilenceData:byte;
      FStream:PaStream;
      FBufferSizeStart:dword;
      FStarted:boolean;
      FSync:TCriticalSection;
      FCFC:dword;// protected client frame count
    public
      constructor Create(buffSize, sampleRate, bytesPerSample, numChannels:dword);
      procedure OnData(data:pointer; length:dword);
      destructor Destroy();override;
  end;

implementation

function _callback(input, output:pointer; frameCount:dword; timeInfo:PPaStreamCallbackTimeInfo; statusFlags:PaStreamCallbackFlags; userData:pointer):integer;cdecl;
var
  this:TPortAudioStreamer;
  peak, pos, i, dataAvail:dword;
  silence:byte;
  p, bOut:pByte;
begin
  bOut:=pByte(output);
  this:=TPortAudioStreamer(userData);
  this.FSync.Enter();

  if(this.FBufferWritePosition>this.FBufferReadPosition)then
    dataAvail:=this.FBufferWritePosition-this.FBufferReadPosition
  else
    dataAvail:=this.FBufferWritePosition-this.FBufferReadPosition+this.FBufferSize;

  if((dataAvail div this.FFrameSize)>frameCount)then
  begin
    //copy data from buffer
    pos:=this.FBufferReadPosition;
    peak:=this.FBufferSize;
    p:=this.FBuffer;

    for i:=0 to frameCount*this.FFrameSize-1 do
    begin
      bOut[i]:=p[pos];
      inc(pos);
      if(pos=peak)then
        pos:=0;
    end;
    //update buffer position
    this.FBufferReadPosition:=pos;
  end
  else
  begin
    //return silence data
    silence:=this.FSilenceData;
    for i:=0 to frameCount*this.FFrameSize-1 do
      bOut[i]:=silence;
  end;
  this.FSync.Leave();

  Result:=0;
end;

constructor TPortAudioStreamer.Create(buffSize, sampleRate, bytesPerSample, numChannels:dword);
var
  err:PaError;
  format:PaSampleFormat;
begin
  inherited Create();
  FSync:=TCriticalSection.Create();

  FFrameSize:=numChannels*bytesPerSample;
  FBufferSize:=buffSize*sampleRate*FFrameSize div 100;//allocate data for 10*buffSize ms
  FBufferSizeStart:=FBufferSize div 5;//wait for 2 full buffers before starting to play
  FStarted:=false;

  getmem(FBuffer, FBufferSize);

  FSilenceData:=0;
  if(bytesPerSample=1)then
  begin
    //wasapi returns unsigned byte
    format:=PaUInt8;
    FSilenceData:=$80;
  end
  else if(bytesPerSample=2)then
    format:=PaInt16
  else if(bytesPerSample=3)then
    format:=PaInt24
  else
    format:=PaInt32;

  err:=Pa_OpenDefaultStream(FStream, 0, numChannels, format, sampleRate, buffSize*sampleRate div 1000, @_callback, self);
  if(err<>PaNoError)then
    raise Exception.Create(Pa_GetErrorText(err));
end;

procedure TPortAudioStreamer.OnData(data:pointer; length:dword);
var
  i, j, p:dword;
  bData:pByte;
begin
  FSync.Enter();
  j:=FBufferWritePosition;
  p:=FBufferSize;
  bData:=pByte(data);

  for i:=0 to length-1 do
  begin
    FBuffer[j]:=bData[i];
    inc(j);
    if(j=p)then
      j:=0;
  end;
  FBufferWritePosition:=j;
  if((not FStarted)and(FBufferWritePosition>FBufferSizeStart))then
  begin
    FStarted:=true;
    writeln('Prebuffer complete. Starting stream');
    Pa_StartStream(FStream);
  end;
  FSync.Leave();
end;

destructor TPortAudioStreamer.Destroy();
begin
  Pa_CloseStream(FStream);
  freemem(FBuffer);
  FSync.Free();
  inherited Destroy();
end;

initialization
  Pa_Initialize();

finalization
  Pa_Terminate();
end.

