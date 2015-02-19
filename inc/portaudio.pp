unit
  portaudio;

{$mode objfpc}{$H+}
{$packrecords c}

interface

const
  libName='portaudio_x86.dll';

type
  { base types }
  PaDeviceIndex=integer;
  PaError=integer;
  PaSampleFormat=dword;
  PaStream=pointer;
  PaStreamCallbackFlags=dword;
  PaStreamFlags=dword;
  PaTime=double;

const
  paNoError:PaError=0;
  paNoFlag:PaStreamFlags=0;
  paClipOff:PaStreamFlags=1;
  paDitherOff:PaStreamFlags=2;
  paNeverDropInput:PaStreamFlags=4;
  paPrimeOutputBuffersUsingStreamCallback:PaStreamFlags=8;
  paPlatformSpecificFlags=$ffff0000;

  paFloat32:PaSampleFormat=1;
  paInt32:PaSampleFormat=2;
  paInt24:PaSampleFormat=4;
  paInt16:PaSampleFormat=8;
  paInt8:PaSampleFormat=16;
  paUInt8:PaSampleFormat=32;

type
  PaStreamCallbackTimeInfo=record
    inputBufferAdcTime, currentTime, outputBufferDacTime:PaTime;
  end;
  PPaStreamCallbackTimeInfo=^PaStreamCallbackTimeInfo;
  PaStreamCallback=function(input, output:pointer; frameCount:dword; timeInfo:PPaStreamCallbackTimeInfo; statusFlags:PaStreamCallbackFlags; userData:pointer):integer;cdecl;
  PaStreamParameters=record
    device:PaDeviceIndex;
    channelCount:integer;
    sampleFormat:PaSampleFormat;
    suggestedLatency:PaTime;
    hostApiSpecificStreamInfo:pointer;
  end;
  PPaStreamParameters=^PaStreamParameters;


function Pa_Initialize():PaError;cdecl;external libName;
function Pa_Terminate():PaError;cdecl;external libName;

function Pa_OpenStream(out stream:PaStream; inputParameters, outputParameters:PPaStreamParameters; sampleRate:double; framesPerBuffer:dword; streamFlags:PaStreamFlags; streamCallabck:PaStreamCallback; userData:pointer):PaError;cdecl; external libName;
function Pa_OpenDefaultStream(out stream:PaStream; numInputChannels, numOutputChannels:integer; sampleFormat:PaSampleFormat; sampleRate:double; framesPerBuffer:dword;  streamCallabck:PaStreamCallback; userData:pointer):PaError;cdecl; external libName;
function Pa_CloseStream(stream:PaStream):PaError;cdecl; external libName;
function Pa_GetErrorText(errorCode:PaError):pchar;cdecl; external libName;
function Pa_StartStream(stream:PaStream):PaError;cdecl; external libName;


implementation

end.

