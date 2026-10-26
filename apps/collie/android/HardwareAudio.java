package org.flexscript.collie;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.*;
import android.os.SystemClock;
import android.os.Build;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.*;
import org.json.*;

/** Android audio devices, PCM objects and callbacks. File/container logic is guest code. */
final class HardwareAudio {
    static AudioManager manager(VmHardware.Context c){return (AudioManager)c.host.getSystemService(Context.AUDIO_SERVICE);}
    static String id(AudioDeviceInfo device){return "audio-"+device.getId();}
    static List<AudioDeviceInfo> devices(VmHardware.Context c){List<AudioDeviceInfo> out=new ArrayList<>(Arrays.asList(manager(c).getDevices(AudioManager.GET_DEVICES_ALL)));out.sort(Comparator.comparingInt(AudioDeviceInfo::getId));return out;}
    static AudioDeviceInfo device(VmHardware.Context c,String selected,boolean input)throws Exception{if(selected.equals("default"))return null;for(AudioDeviceInfo device:devices(c))if(id(device).equals(selected)&& (input?device.isSource():device.isSink()))return device;throw new VmHardware.Failure("unavailable","Selected audio device is unavailable or has the wrong direction.");}
    static JSONArray numbers(int[] values){JSONArray out=new JSONArray();for(int i=0;i<Math.min(values.length,64);i++)out.put(values[i]);return out;}
    static JSONObject info(AudioDeviceInfo device)throws Exception{return VmHardware.object("id",id(device),"type",device.getType(),"name",String.valueOf(device.getProductName()),"input",device.isSource(),"output",device.isSink(),"sample_rates",numbers(device.getSampleRates()),"channel_counts",numbers(device.getChannelCounts()),"encodings",numbers(device.getEncodings()));}
    static boolean supports(String op){switch(op){case "audio_devices":case "audio_watch":case "audio_input_open":case "audio_output_open":case "audio_route":case "audio_control":case "audio_volume":return true;default:return false;}}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{boolean input=false,output=false;for(AudioDeviceInfo device:devices(c)){input|=device.isSource();output|=device.isSink();}out.put(VmHardware.capability("audio_input",true,input,"microphone"));out.put(VmHardware.capability("audio_output",true,output,"audio"));}
    static final class Watch extends VmHardware.Handle {
        final AudioManager manager;final AudioDeviceCallback callback;
        Watch(VmHardware.Context c)throws Exception{super(c,"audio","audio_devices");manager=manager(c);callback=new AudioDeviceCallback(){private void event(String kind,AudioDeviceInfo[] devices){try{for(AudioDeviceInfo device:devices)emit(VmHardware.object("event",kind,"device",HardwareAudio.info(device)));}catch(Exception ignored){}}public void onAudioDevicesAdded(AudioDeviceInfo[] devices){event("added",devices);}public void onAudioDevicesRemoved(AudioDeviceInfo[] devices){event("removed",devices);}};manager.registerAudioDeviceCallback(callback,HardwareSensors.events());emit(VmHardware.object("event","ready"));}
        public synchronized void close()throws IOException{if(closed)return;super.close();manager.unregisterAudioDeviceCallback(callback);}
    }
    static final class Stream extends VmHardware.Handle {
        final VmHardware.Context context;final int rate,channels,frameBytes;final boolean input;final AudioRecord record;final AudioTrack track;final AudioManager manager;AudioDeviceCallback devices;AudioRouting.OnRoutingChangedListener routing;volatile String preferred="default";volatile int gain=1000;
        Stream(VmHardware.Context c,String selected,int rate,int channels,boolean input)throws Exception{
            super(c,input?"microphone":"audio",input?"audio_input":"audio_output");context=c;this.rate=rate;this.channels=channels;this.input=input;frameBytes=channels*2;manager=manager(c);
            AudioRecord recording=null;AudioTrack playing=null;
            try{
                int mask=input?(channels==1?AudioFormat.CHANNEL_IN_MONO:AudioFormat.CHANNEL_IN_STEREO):(channels==1?AudioFormat.CHANNEL_OUT_MONO:AudioFormat.CHANNEL_OUT_STEREO);
                AudioFormat format=new AudioFormat.Builder().setSampleRate(rate).setChannelMask(mask).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build();
                int minimum=input?AudioRecord.getMinBufferSize(rate,mask,AudioFormat.ENCODING_PCM_16BIT):AudioTrack.getMinBufferSize(rate,mask,AudioFormat.ENCODING_PCM_16BIT);
                if(minimum<=0)throw new VmHardware.Failure("unsupported_format","Android does not support this PCM rate/channel layout.");
                int buffer=Math.max(minimum,Math.min(rate*frameBytes/5,65536));buffer=((buffer+frameBytes-1)/frameBytes)*frameBytes;
                if(input){recording=new AudioRecord.Builder().setAudioSource(MediaRecorder.AudioSource.MIC).setAudioFormat(format).setBufferSizeInBytes(buffer).build();if(recording.getState()!=AudioRecord.STATE_INITIALIZED)throw new VmHardware.Failure("unavailable","Android could not initialize microphone recording.");}
                else{playing=new AudioTrack.Builder().setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()).setAudioFormat(format).setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(buffer).build();if(playing.getState()!=AudioTrack.STATE_INITIALIZED)throw new VmHardware.Failure("unavailable","Android could not initialize PCM playback.");}
                record=recording;track=playing;route(selected);
                routing=router->{try{AudioDeviceInfo actual=input?record.getRoutedDevice():track.getRoutedDevice();emit(VmHardware.object("event","routing","preferred",preferred,"routed",actual==null?JSONObject.NULL:id(actual)));}catch(Exception ignored){}};
                devices=new AudioDeviceCallback(){public void onAudioDevicesRemoved(AudioDeviceInfo[] removed){for(AudioDeviceInfo device:removed)if(preferred.equals(id(device)))try{close();}catch(Exception ignored){}}};
                if(input)record.addOnRoutingChangedListener(routing,HardwareSensors.events());else track.addOnRoutingChangedListener(routing,HardwareSensors.events());manager.registerAudioDeviceCallback(devices,HardwareSensors.events());
                if(input){record.startRecording();if(record.getRecordingState()!=AudioRecord.RECORDSTATE_RECORDING)throw new VmHardware.Failure("unavailable","Android refused microphone recording.");}else track.play();
            }catch(Exception error){closed=true;if(devices!=null)manager.unregisterAudioDeviceCallback(devices);if(routing!=null){if(recording!=null)recording.removeOnRoutingChangedListener(routing);if(playing!=null)playing.removeOnRoutingChangedListener(routing);}if(recording!=null){try{recording.stop();}catch(Exception ignored){}recording.release();}if(playing!=null)playing.release();throw error;}
        }
        void check()throws VmHardware.Failure{super.check();if(input&&!context.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Microphone capture requires a visible Collie activity.");}
        void access(VmHardware.Context c)throws Exception{super.access(c);if(input && (c.host.checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED || !c.host.hardwareVisible)){close();throw new VmHardware.Failure("permission_revoked","Microphone permission or foreground visibility was lost. Reopen after approval.");}}
        void route(String selected)throws Exception{AudioDeviceInfo device=device(context,selected,input);boolean accepted=input?record.setPreferredDevice(device):track.setPreferredDevice(device);if(!accepted)throw new VmHardware.Failure("unavailable","Android refused the preferred audio route.");preferred=selected;}
        Object info()throws Exception{check();AudioDeviceInfo actual=input?record.getRoutedDevice():track.getRoutedDevice();AudioRecordingConfiguration configuration=input&&Build.VERSION.SDK_INT>=29?record.getActiveRecordingConfiguration():null;AudioTimestamp timestamp=new AudioTimestamp();int timestampResult=input?record.getTimestamp(timestamp,AudioTimestamp.TIMEBASE_MONOTONIC):track.getTimestamp(timestamp)?AudioRecord.SUCCESS:AudioRecord.ERROR;return VmHardware.object("kind",kind,"sample_rate",input?record.getSampleRate():track.getSampleRate(),"channels",channels,"encoding","pcm_s16le","frame_bytes",frameBytes,"preferred",preferred,"routed",actual==null?JSONObject.NULL:id(actual),"silenced",configuration==null?JSONObject.NULL:configuration.isClientSilenced(),"active",input?record.getRecordingState()==AudioRecord.RECORDSTATE_RECORDING:track.getPlayState()==AudioTrack.PLAYSTATE_PLAYING,"volume_permille",gain,"position_frames",timestampResult==AudioRecord.SUCCESS?timestamp.framePosition:JSONObject.NULL,"timestamp_ns",timestampResult==AudioRecord.SUCCESS?timestamp.nanoTime:JSONObject.NULL,"underruns",input?JSONObject.NULL:track.getUnderrunCount());}
        Object read(int limit,int timeout)throws Exception{
            if(!input)throw new VmHardware.Failure("wrong_direction","Read from an audio input handle.");if(limit<frameBytes)throw new VmHardware.Failure("invalid_argument","Audio read limit must contain at least one complete PCM frame.");if(record.getRecordingState()!=AudioRecord.RECORDSTATE_RECORDING)throw new VmHardware.Failure("not_running","Start the paused microphone before reading.");
            int bytes=(limit/frameBytes)*frameBytes;ByteBuffer buffer=ByteBuffer.allocateDirect(bytes).order(ByteOrder.LITTLE_ENDIAN);long deadline=SystemClock.elapsedRealtime()+timeout;
            for(;;){access(context);VmHardware.check();int count=record.read(buffer,bytes,AudioRecord.READ_NON_BLOCKING);if(count>0){byte[] data=new byte[count];buffer.position(0);buffer.get(data);return VmHardware.bytes(data);}if(count<0)throw io(count);if(SystemClock.elapsedRealtime()>=deadline)throw new VmHardware.Failure("timeout","No PCM input arrived before the deadline.");Thread.sleep(5);}
        }
        Object write(byte[] bytes)throws Exception{
            if(input)throw new VmHardware.Failure("wrong_direction","Write to an audio output handle.");if(bytes.length%frameBytes!=0)throw new VmHardware.Failure("invalid_argument","PCM writes must contain complete sample frames.");if(track.getPlayState()!=AudioTrack.PLAYSTATE_PLAYING)throw new VmHardware.Failure("not_running","Start the paused audio output before writing.");ByteBuffer data=ByteBuffer.allocateDirect(bytes.length).order(ByteOrder.LITTLE_ENDIAN);data.put(bytes);data.flip();long deadline=SystemClock.elapsedRealtime()+8000;
            for(;;){check();VmHardware.check();int count=track.write(data,bytes.length,AudioTrack.WRITE_NON_BLOCKING);if(count>0 || bytes.length==0)return count;if(count<0)throw io(count);if(SystemClock.elapsedRealtime()>=deadline)throw new VmHardware.Failure("timeout","Audio output buffer remained full.");Thread.sleep(5);}
        }
        VmHardware.Failure io(int code)throws IOException{if(code==AudioRecord.ERROR_DEAD_OBJECT)close();return new VmHardware.Failure(code==AudioRecord.ERROR_DEAD_OBJECT?"disconnected":"io_error","Android PCM operation failed with code "+code+".");}
        Object control(String action)throws Exception{if(action.equals("start")){if(input)record.startRecording();else track.play();}else if(action.equals("pause")){if(input)record.stop();else track.pause();}else if(action.equals("flush")&&!input){if(track.getPlayState()==AudioTrack.PLAYSTATE_PLAYING)throw new VmHardware.Failure("busy","Pause playback before flushing queued PCM.");track.flush();}else throw new VmHardware.Failure("invalid_argument","Audio action must be start, pause, or playback-only flush.");return 1;}
        Object volume(int value)throws Exception{if(input)throw new VmHardware.Failure("wrong_direction","Volume applies only to an output stream.");if(track.setVolume(value/1000.0f)!=AudioTrack.SUCCESS)throw new VmHardware.Failure("unavailable","Android rejected stream volume.");gain=value;return 1;}
        public synchronized void close()throws IOException{if(closed)return;super.close();manager.unregisterAudioDeviceCallback(devices);if(input){record.removeOnRoutingChangedListener(routing);try{record.stop();}catch(Exception ignored){}record.release();}else{track.removeOnRoutingChangedListener(routing);try{track.pause();track.flush();track.stop();}catch(Exception ignored){}track.release();}}
    }
    static Object call(VmHardware.Context c,String op,JSONArray args)throws Exception{
        if(op.equals("audio_devices")){int offset=VmHardware.integer(args,0,0,100000),limit=VmHardware.integer(args,1,1,16);List<AudioDeviceInfo> devices=devices(c);int end=Math.min(devices.size(),offset+limit);JSONArray out=new JSONArray();for(int i=offset;i<end;i++)out.put(info(devices.get(i)));return VmHardware.object("devices",out,"next",end<devices.size()?end:-1,"total",devices.size());}
        if(op.equals("audio_watch"))return VmHardware.add(new Watch(c));
        if(op.equals("audio_input_open")||op.equals("audio_output_open")){String selected=VmHardware.text(args,0,128);int rate=VmHardware.integer(args,1,8000,192000),channels=VmHardware.integer(args,2,1,2);boolean input=op.equals("audio_input_open");device(c,selected,input);if(input){VmHardware.require(c,Manifest.permission.RECORD_AUDIO);if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Microphone capture requires the Collie activity to remain visible.");}return VmHardware.add(new Stream(c,selected,rate,channels,input));}
        Stream stream=VmHardware.handle(c,VmHardware.text(args,0,128),Stream.class);stream.access(c);if(op.equals("audio_route")){stream.route(VmHardware.text(args,1,128));return 1;}if(op.equals("audio_control"))return stream.control(VmHardware.text(args,1,16));if(op.equals("audio_volume"))return stream.volume(VmHardware.integer(args,1,0,1000));throw new VmHardware.Failure("unsupported_operation","Unknown audio operation.");
    }
}
