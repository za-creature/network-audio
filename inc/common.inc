{$packrecords C}

const
  NAS_PACKET_READY=0;//connection set up; awaiting data
  NAS_PACKET_SYNC=1;//awaiting sync package for handshake
  NAS_PACKET_BADSYNC=2;//invalid sync; please change parameters before resending

  NAC_PACKET_DATA=0;//data packet
  NAC_PACKET_SYNC=1;//syncronization packet
  NAC_PACKET_IDENTIFY=2;//identify packet

type
  TClientPacket=record
    packetType:byte;
    case integer of
      0:
      (
        sampleRate:dword;
        bitsPerSample:byte;
        numChannels:byte;
        packetSize:dword;//size (in ms) of a buffer
      );
      1:
      (
        syncId:dword;
        data:byte;//signal begin of data
      );
  end;
  PClientPacket=^TClientPacket;
  TServerPacket=record
    packetType:byte;
  end;
