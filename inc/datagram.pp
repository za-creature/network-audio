{

Wrapper class that facilitates datagram communication
(c) 2008 Dan Radu

}

unit
  datagram;

{$mode objfpc}
{$m+}

interface

uses
  {$ifdef win32}winsock{$else}netdb{$endif}, sysutils, classes, sockets, syncobjs;

type
  TDatagramSocket=class(TObject)
    protected
      Faddr:TInetSockAddr;
      Fsock:longint;
    public
      constructor Create(hostname:ansistring; port:word);
      procedure Send(const buffer; count:longint);
      destructor Destroy();override;
  end;
  TDatagramServer=class(TThread)
    protected
      Faddr:TInetSockAddr;
      Fsock:longint;
      Fsync:TCriticalSection;
      FShutdownSync:TCriticalSection;
      FRunning:boolean;
      FPort:word;
    public
      procedure OnDatagram(sender:TInetSockAddr; data:pointer; length:integer);virtual;
      constructor Create(port:word);
      procedure Execute();override;
      destructor Destroy();override;
  end;

implementation

// TDatagramSocket

constructor TDatagramSocket.Create(hostname:ansistring; port:word);
var
  addr:dword;
  h:^hostent;
begin
  //create inet stream socket
  Fsock:=socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if(Fsock=-1)then
    raise Exception.Create('Unable to create socket');

  //lookup remote host
  h:=gethostbyname(pchar(hostname));
  if(h<>nil)then//address is a qualified domain name
    addr:=pdword(h^.h_addr[0])^
  else//could not perform lookup; attempt to use hostname as ip address
    addr:=StrToNetAddr(hostname).s_addr;

  Faddr.sin_family:=AF_INET;
  Faddr.sin_port:=htons(port);
  Faddr.sin_addr.s_addr:=addr;
end;

procedure TDatagramSocket.Send(const buffer; count:longint);
begin
  sendto(Fsock, buffer, count, 0, Faddr, sizeof(Faddr));
end;

destructor TDatagramSocket.Destroy();
begin
  inherited Destroy();
end;

// TDatagramServer

constructor TDatagramServer.Create(port:word);
begin
  FShutdownSync:=TCriticalSection.Create();
  FRunning:=true;
  Fsock:=socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if(Fsock=-1)then
    raise Exception.Create('Unable to create socket');

  Faddr.sin_family:=AF_INET;
  Faddr.sin_port:=htons(port);
  Faddr.sin_addr.s_addr:=INADDR_ANY;

  if(not(bind(Fsock, Faddr, sizeof(Faddr))))then
    raise Exception.Create('Could not bind to address');

  //save stuff for a rainy day
  FPort:=port;

  inherited Create(false);
end;

procedure TDatagramServer.Execute();
var
  buffer:array[0..65535] of char;
  cli:TInetSockAddr;
  count, cli_len:integer;
  running:boolean=true;
begin
  FShutdownSync.Enter();
  Fsync:=TCriticalSection.Create();
  while(running)do
  begin
    cli_len:=sizeof(cli);
    count:=recvfrom(Fsock, buffer, sizeof(buffer), 0, cli, cli_len);

    Fsync.Enter();
    running:=FRunning;
    Fsync.Leave();

    if(running)and(count>0)then
      OnDatagram(cli, @buffer[0], count);
  end;
  Fsync.Free();
  FShutdownSync.Leave();
end;

procedure TDatagramServer.OnDatagram(sender:TInetSockAddr; data:pointer; length:integer);
begin
end;

destructor TDatagramServer.Destroy();
var
  shutdown_msg:TDatagramSocket;
begin
  Fsync.Enter();
  FRunning:=false;
  Fsync.Leave();

  shutdown_msg:=TDatagramSocket.Create('127.0.0.1', FPort);
  shutdown_msg.Send('shutdown', 8);
  shutdown_msg.Free();

  //wait for child thread
  FShutdownSync.Enter();
  FShutdownSync.Leave();

  FshutdownSync.Free();
  inherited Destroy();
end;

end.

