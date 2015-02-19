program NetworkAudioClient;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Interfaces,
  Forms
  { you can add units after this }, MainForm;

{$IFDEF WINDOWS}{$R manifest.rc}{$ENDIF}

{$IFDEF WINDOWS}{$R NetworkAudioClient.rc}{$ENDIF}

begin
  Application.Title:='Network Audio Client';
  Application.Initialize;
  Application.CreateForm(TUI, UI);
  Application.Run;
end.

