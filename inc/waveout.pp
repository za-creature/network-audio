unit WaveOut;

{$mode objfpc}{$H+}

interface

uses
  windows, mmsystem, Classes, SysUtils, syncobjs;

type
  TWaveSource=class(TObject)
    protected
      FSampleRate, FBitsPerSample, FNumChannels:dword;
    public
      property SampleRate:dword read FSampleRate;
      property BitsPerSample:dword read FBitsPerSample;
      property NumChannels:dword read FNumChannels;
      procedure Read(var buffer; numFrames:dword);virtual;
  end;

  TPCMFile=class(TWaveSource)
    protected
      FFileHandle:integer;
    public
      constructor Create(filename:ansistring; _sampleRate, _bitsPerSample, _numChannels:dword);
      procedure Read(var buffer; numFrames:dword);override;
      destructor Destroy();override;
  end;

  TWaveOutStreamer=class(TThread)
    protected
      FWorking:boolean;
      FDevice:HWaveOut;
      FWaveSource:TWaveSource;
      FBufferSize:dword;
      FFrontBuffer, FBackBuffer:PWaveHdr;
      FSync, FRunningSync:TEvent;
      FInternalSync:TCriticalSection;
    public
      constructor Create(buffSize:dword; WaveSource:TWaveSource);
      procedure Execute();override;
      destructor Destroy();override;
  end;

implementation

{ Helper functions }

function WaveHeader(numChannels, bitsPerSample, sampleRate:dword):PWaveFormatEx;
begin
  getmem(Result, sizeof(WaveFormatEx));
  fillByte(Result^, sizeof(WaveFormatEx), 0);

  Result^.nChannels:=numChannels;
  Result^.nSamplesPerSec:=sampleRate;
  Result^.wBitsPerSample:=bitsPerSample;

  Result^.cbSize:=0;
  Result^.wFormatTag:=WAVE_FORMAT_PCM;
  Result^.nBlockAlign:=Result^.nChannels*Result^.wBitsPerSample div 8;
  Result^.nAvgBytesPerSec:=Result^.nBlockAlign*Result^.nSamplesPerSec;
end;

function CreateBuffer(size:dword):PWaveHdr;
begin
  getmem(Result, sizeof(WaveHdr));
  fillByte(Result^, sizeof(WaveHdr), 0);

  Result^.dwBufferLength:=size;
  getmem(Result^.lpData, size);
end;

procedure FreeBuffer(var p:PWaveHdr);
begin
  freemem(p^.lpData);
  freemem(p);
  p:=nil;
end;

{ win32 callback }

procedure _waveOutProc(hwo:HWaveOut; msg:UINT; dwInstance, dwParam1, dwParam2:DWORD);stdcall;
begin
  if(msg=WOM_DONE)then
  begin
    //writeln('buffer done');
    TWaveOutStreamer(dwInstance).FSync.SetEvent();
  end;
end;

{ TWaveOutStreamer }

constructor TWaveOutStreamer.Create(buffSize:dword; WaveSource:TWaveSource);
var
  wfex:PWaveFormatEx;
begin
  //create thread-safe objects
  FSync:=TEvent.Create(nil, false, false, 'SyncObj::WaveOutStreamer.FSync@'+IntToStr(dword(@self)));
  FRunningSync:=TEvent.Create(nil, false, false, 'SyncObj::WaveOutStreamer.FRunningSync@'+IntToStr(dword(@self)));
  FInternalSync:=TCriticalSection.Create();
  FWorking:=true;

  //initialize device
  FBufferSize:=buffSize;
  FWaveSource:=WaveSource;
  wfex:=WaveHeader(FWaveSource.NumChannels, FWaveSource.BitsPerSample, FWaveSource.SampleRate);
  waveOutOpen(@FDevice, WAVE_MAPPER, wfex, dword(@_waveOutProc), dword(self), CALLBACK_FUNCTION);
  freemem(wfex);

  //create buffers
  FFrontBuffer:=CreateBuffer(FWaveSource.NumChannels*FWaveSource.BitsPerSample*FWaveSource.SampleRate*FBufferSize div 8000);
  FBackBuffer:=CreateBuffer(FWaveSource.NumChannels*FWaveSource.BitsPerSample*FWaveSource.SampleRate*FBufferSize div 8000);

  inherited Create(false);
end;

procedure TWaveOutStreamer.Execute();
var
  framesPerBuffer:dword;
  working:boolean=true;
  aux:PWaveHdr;
begin
  //read-ahead two buffers of data
  framesPerBuffer:=FWaveSource.SampleRate*FBufferSize div 1000;
  FWaveSource.Read(FFrontBuffer^.lpData^, framesPerBuffer);
  FWaveSource.Read(FBackBuffer^.lpData^, framesPerBuffer);

  //prepare the buffers
  waveOutPrepareHeader(FDevice, FFrontBuffer, sizeof(WaveHdr));
  waveOutPrepareHeader(FDevice, FBackBuffer, sizeof(WaveHdr));

  //send them to the playback queue
  waveOutWrite(FDevice, FFrontBuffer, sizeof(WaveHdr));
  waveOutWrite(FDevice, FBackBuffer, sizeof(WaveHdr));

  while(working)do
  begin
    //wait for buffer-swap event
    FSync.WaitFor(INFINITE);

    //check state
    FInternalSync.Enter();
    working:=FWorking;
    FInternalSync.Leave();

    //if we're still up and running
    if(working)then
    begin
      aux:=FFrontBuffer;
      FFrontBuffer:=FBackBuffer;
      FBackBuffer:=aux;

      waveOutUnprepareHeader(FDevice, FBackBuffer, sizeof(WaveHdr));

      FWaveSource.Read(FBackBuffer^.lpData^, framesPerBuffer);

      waveOutPrepareHeader(FDevice, FBackBuffer, sizeof(WaveHdr));
      waveOutWrite(FDevice, FBackBuffer, sizeof(WaveHdr));
      //swap buffers
    end;
  end;

  //notify main that we're done here
  FRunningSync.SetEvent();
end;

destructor TWaveOutStreamer.Destroy();
begin
  //notify child thread to shutdown
  FInternalSync.Enter();
  FWorking:=false;
  FinternalSync.Leave();
  FSync.SetEvent();

  //wait for child thread to shutdown
  FRunningSync.WaitFor(INFINITE);

  //release internal buffers
  FreeBuffer(FFrontBuffer);
  FreeBuffer(FBackBuffer);

  //release device
  waveOutClose(FDevice);

  //release thread-safe objects
  FSync.Free();
  FRunningSync.Free();
  FInternalSync.Free();

  inherited Destroy();
end;

{ TWaveSource }

procedure TWaveSource.Read(var buffer; numFrames:dword);
begin
end;

{ TPCMFile }

constructor TPCMFile.Create(filename:ansistring; _sampleRate, _bitsPerSample, _numChannels:dword);
begin
  inherited Create();
  FSampleRate:=_sampleRate;
  FBitsPerSample:=_bitsPerSample;
  FNumChannels:=_numChannels;
  FFileHandle:=FileOpen(filename, fmOpenRead);
end;

destructor TPCMFile.Destroy();
begin
  FileClose(FFileHandle);
  inherited Destroy();
end;

procedure TPCMFile.Read(var Buffer; numFrames:dword);
var
  maxBytesPerChunk:dword=1024;
  bytesRead:dword=0;
  bytesTotal:dword;
  buff:pByte;
  silenceData:byte=0;
  br:integer;
begin
  buff:=pByte(@Buffer);
  bytesTotal:=numFrames*FBitsPerSample*FNumChannels div 8;
  while(bytesRead<bytesTotal)do
  begin
    //attempt to read from handle
    br:=FileRead(FFileHandle, buff[bytesRead], min(bytesTotal-bytesRead, maxBytesPerChunk));

    if(br>0)then//if bytes are available in the file
      bytesRead+=br//update stream position
    else
    begin
      //fill stream with silence data
      if(FBitsPerSample=8)then
        silenceData:=$80;
      fillByte(buff[bytesRead], bytesTotal-bytesRead, silenceData);
      //finalize loop
      bytesRead:=bytesTotal;
    end;
  end;
end;

end.

