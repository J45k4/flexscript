package org.flexscript.collie;

import android.media.midi.MidiDeviceService;
import android.media.midi.MidiReceiver;
import java.io.IOException;

/** Debug-only framework peer; no physical MIDI device or synthesizer is used. */
public final class MidiLoopbackFixture extends MidiDeviceService {
    private final MidiReceiver receiver=new MidiReceiver(){
        @Override public void onSend(byte[] data,int offset,int count,long timestamp)throws IOException{
            getOutputPortReceivers()[0].send(data,offset,count,timestamp);
        }
        @Override public void onFlush()throws IOException{getOutputPortReceivers()[0].flush();}
    };
    @Override public MidiReceiver[] onGetInputPortReceivers(){return new MidiReceiver[]{receiver};}
}
