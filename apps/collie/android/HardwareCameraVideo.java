package org.flexscript.collie;

import android.Manifest;
import android.content.pm.PackageManager;
import android.hardware.camera2.*;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.*;
import android.os.*;
import android.util.Size;
import android.view.Surface;
import java.io.*;
import java.util.*;
import java.util.concurrent.Semaphore;
import org.json.*;

/** Bounded MediaRecorder resources and private temporary spools, not guest filesystem paths. */
final class HardwareCameraVideo {
    static final Semaphore SLOTS=new Semaphore(2);
    static final class Lease {
        File file;boolean sdkOwned,sdkFreed,released;
        synchronized void discard()throws IOException{if(released)return;if(sdkOwned&&!sdkFreed)return;if(file!=null&&file.exists()&&!file.delete())throw new IOException("Could not remove the owned camera spool.");released=true;SLOTS.release();}
    }
    private static boolean recovered;
    static synchronized File recover(android.content.Context c)throws Exception{
        File dir=new File(c.getCacheDir(),"camera-captures");if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("Cannot create the private camera spool directory.");
        if(!recovered){File[] files=dir.listFiles();if(files==null)throw new IOException("Cannot inspect private camera spools.");for(File f:files)if(f.getName().matches("collie-camera--?[0-9]+\\.mp4")&&!f.delete())throw new IOException("Cannot remove an interrupted camera spool.");recovered=true;}return dir;
    }
    static final class Options {
        final int width,height,fps,bitrate,duration,codec;final long limit;
        Options(HardwareCamera.Camera camera,JSONArray a,JSONArray settings)throws Exception{
            CameraValues.list(a,7,7);width=VmHardware.integer(a,0,1,32768);height=VmHardware.integer(a,1,1,32768);fps=VmHardware.integer(a,2,1,120);bitrate=VmHardware.integer(a,3,64000,50000000);duration=VmHardware.integer(a,4,500,120000);limit=VmHardware.longInteger(a,5,65536,64L*1024*1024);codec=VmHardware.integer(a,6,0,3);
            StreamConfigurationMap map=camera.ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);Size[] sizes=map==null?null:map.getOutputSizes(MediaRecorder.class);if(sizes==null||!Arrays.asList(sizes).contains(new Size(width,height)))throw new VmHardware.Failure("unsupported_format","Choose an exact MediaRecorder size from camera_output_sizes(camera_id,0,...).");if(codec==3&&Build.VERSION.SDK_INT<34)throw new VmHardware.Failure("unsupported_operation","MediaRecorder AV1 requires Android14+.");
            Set<String> keys=new HashSet<>();for(CaptureRequest.Key<?> key:camera.ch.getAvailableCaptureRequestKeys())keys.add(key.getName());for(int i=0;i<settings.length();i++){JSONArray r=CameraValues.list(settings.get(i),3,3);String name=VmHardware.text(r,0,256);if(!keys.contains(name))throw new VmHardware.Failure("unsupported_key","That request key is not advertised: "+name);CameraValues.decode(VmHardware.text(r,1,32),r.get(2));}
        }
    }
    static boolean supports(String op){return op.equals("camera_video_start")||op.equals("camera_video_audio_start")||op.equals("camera_video_stop")||op.equals("camera_video_pause")||op.equals("camera_video_resume")||op.equals("camera_video_seek");}
    static final class Video extends VmHardware.Handle {
        final VmHardware.Context context;final HardwareCamera.Camera camera;final File file;final MediaRecorder sdk;final Lease lease;final JSONArray settings;final int width,height,fps,bitrate,duration;final long limit;final boolean audio;
        Surface output;RandomAccessFile input;String state="prepared",error="";boolean started,stopping,stopActive,deleteOnStop;volatile boolean starting,released,cleanupQueued;volatile int inFlight;long position;
        Video(VmHardware.Context c,HardwareCamera.Camera camera,Options options,JSONArray settings,boolean audio,Lease lease)throws Exception{
            super(c,"camera","camera_video",audio?"microphone":"");context=c;this.camera=camera;this.settings=settings;this.audio=audio;this.lease=lease;
            width=options.width;height=options.height;fps=options.fps;bitrate=options.bitrate;duration=options.duration;limit=options.limit;int codec=options.codec;
            file=File.createTempFile("collie-camera-",".mp4",recover(c.host));lease.file=file;MediaRecorder recorder=Build.VERSION.SDK_INT>=31?new MediaRecorder(c.host.getApplicationContext()):new MediaRecorder();sdk=recorder;lease.sdkOwned=true;starting=true;boolean prepared=false;
            try{if(audio)recorder.setAudioSource(MediaRecorder.AudioSource.MIC);recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE);recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);recorder.setVideoEncoder(codec==0?MediaRecorder.VideoEncoder.DEFAULT:codec==1?MediaRecorder.VideoEncoder.H264:codec==2?MediaRecorder.VideoEncoder.HEVC:MediaRecorder.VideoEncoder.AV1);recorder.setVideoSize(width,height);recorder.setVideoFrameRate(fps);recorder.setVideoEncodingBitRate(bitrate);if(audio){recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);recorder.setAudioSamplingRate(48000);recorder.setAudioChannels(1);recorder.setAudioEncodingBitRate(64000);}recorder.setMaxDuration(duration);recorder.setMaxFileSize(limit);recorder.setOutputFile(file);recorder.setOnErrorListener((r,what,extra)->{synchronized(Video.this){error="SDK recorder error "+what+"/"+extra;}event("error","sdk_code",what,"extra",extra,"sdk_callback",true);requestStop();});recorder.setOnInfoListener((r,what,extra)->{event("recorder_info","sdk_code",what,"extra",extra,"sdk_callback",true);if(what==MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED||what==MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED)requestStop();});recorder.prepare();output=recorder.getSurface();prepared=true;}
            catch(Exception e){synchronized(this){closed=true;released=true;cleanupQueued=true;}try{recorder.release();if(output!=null)output.release();lease.sdkFreed=true;lease.discard();}catch(Exception cleanup){e.addSuppressed(cleanup);}throw e;}
            finally{synchronized(this){starting=false;if(prepared&&(closed||stopping))queueStop();}}
        }
        void event(String name,Object... values){try{Object[] fields=new Object[values.length+2];fields[0]="event";fields[1]=name;System.arraycopy(values,0,fields,2,values.length);emit(VmHardware.object(fields));}catch(Exception ignored){}}
        Surface surface()throws VmHardware.Failure{if(output==null)throw new VmHardware.Failure("not_ready","The recorder surface is not prepared.");return output;}
        void access(VmHardware.Context c)throws Exception{super.access(c);try{HardwareCamera.captureAccess(c);if(audio&&c.host.checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED)throw new VmHardware.Failure("permission_revoked","Android microphone permission was revoked.");}catch(Exception e){close();throw e;}}
        void startConfigured()throws Exception{
            synchronized(this){check();if(stopping)return;starting=true;}
            try{access(context);camera.capture(CameraDevice.TEMPLATE_RECORD,settings,true);synchronized(this){check();if(stopping)return;}sdk.start();synchronized(this){started=true;state="recording";event("recording","sdk_start_returned",true);}}
            finally{synchronized(this){starting=false;if(closed||stopping)queueStop();}synchronized(camera){if(camera.needsCleanup())camera.cleanup();}}
        }
        int requestStop(){synchronized(this){if(released||stopping)return 0;stopping=true;state="stopping";if(!starting&&inFlight==0)queueStop();return 1;}}
        synchronized void queueStop(){if(cleanupQueued||released)return;cleanupQueued=true;HardwareCamera.CLEANUP.execute(()->{try{stopNow(false);}catch(Exception e){synchronized(Video.this){error=MainActivity.safe(e);state="error";}}});}
        void stopNow(boolean delete)throws Exception{
            boolean wasStarted;synchronized(this){deleteOnStop|=delete;if(released){if(deleteOnStop)discard();return;}if(starting||inFlight>0||stopActive){stopping=true;return;}stopActive=true;wasStarted=started;stopping=true;state="stopping";}
            CameraCaptureSession session;List<HardwareCamera.Reader> readers;synchronized(camera){if(camera.video==this){session=camera.session;camera.session=null;readers=new ArrayList<>(camera.readers.values());camera.readers.clear();if(!camera.closed&&!camera.state.equals("error"))camera.state="open";}else{session=null;readers=new ArrayList<>();}}
            String failure="";if(session!=null){try{session.stopRepeating();}catch(Exception ignored){}try{session.close();}catch(Exception e){failure=MainActivity.safe(e);}}try{camera.clearImages();camera.retire(readers);}catch(Exception e){failure=MainActivity.safe(e);}
            boolean sdkReleased=false;try{if(wasStarted)sdk.stop();}catch(Exception e){failure=MainActivity.safe(e);}try{sdk.release();if(output!=null)output.release();sdkReleased=true;}catch(Exception e){failure=MainActivity.safe(e);}
            synchronized(this){released=sdkReleased;lease.sdkFreed=sdkReleased;started=false;if(file.length()>limit)failure="The recorder exceeded the requested file-byte bound.";if(!failure.isEmpty()){error=failure;state="error";event("error","code","recording_failed","message",failure);}else if(wasStarted){state="stopped";event("stopped","bytes",file.length(),"sdk_stop_returned",true);}else{state="cancelled";}if(sdkReleased&&(deleteOnStop||closed||!failure.isEmpty()))discard();stopActive=false;}
            synchronized(camera){if(released&&camera.video==this)camera.video=null;camera.releaseLease();if(camera.needsCleanup())camera.cleanup();}
        }
        synchronized void invalidateForParent()throws IOException{if(!closed)super.close();stopping=true;deleteOnStop=true;}
        void cleanupNow()throws Exception{invalidateForParent();stopNow(true);}
        synchronized void discard()throws IOException{if(input!=null){input.close();input=null;}lease.discard();}
        synchronized Object read(int count,int timeout)throws Exception{check();if(!state.equals("stopped"))throw new VmHardware.Failure("not_ready","Wait for actual recorder stop/finalization before reading the container.");if(input==null)input=new RandomAccessFile(file,"r");byte[] bytes=new byte[count];int n=input.read(bytes);if(n<0)return JSONObject.NULL;position+=n;return VmHardware.bytes(Arrays.copyOf(bytes,n));}
        synchronized Object seek(long offset)throws Exception{check();if(!state.equals("stopped"))throw new VmHardware.Failure("not_ready","Stop and finalize recording before seeking.");if(offset>file.length())throw new VmHardware.Failure("invalid_argument","Video offset exceeds its finalized length.");if(input==null)input=new RandomAccessFile(file,"r");input.seek(offset);position=offset;return offset;}
        synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"width",width,"height",height,"fps",fps,"bitrate",bitrate,"audio",audio,"duration_limit_ms",duration,"byte_limit",limit,"bytes",released?file.length():JSONObject.NULL,"position",position,"sdk_released",released,"error",error);}
        public void close()throws IOException{boolean active;synchronized(this){if(closed)return;super.close();active=!released;if(!active){discard();return;}stopping=true;state="closed";}boolean attached;synchronized(camera){attached=camera.video==this;}if(attached)camera.close();else synchronized(this){queueStop();}}
    }
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(op.equals("camera_video_start")||op.equals("camera_video_audio_start")){
            HardwareCamera.Camera camera=VmHardware.handle(c,VmHardware.text(a,0,128),HardwareCamera.Camera.class);camera.access(c);JSONArray raw=CameraValues.list(a.get(1),7,7),settings=CameraValues.list(a.get(2),0,64);Options options=new Options(camera,raw,settings);boolean audio=op.equals("camera_video_audio_start");
            synchronized(camera){camera.check();if(!camera.state.equals("open")&&!camera.state.equals("configured"))throw new VmHardware.Failure("not_ready","Wait for an opened camera before recording.");if(camera.video!=null||camera.pendingReaders>0)throw new VmHardware.Failure("busy","Only one recorder and one completed reader configuration may belong to a camera.");}if(audio)VmHardware.require(c,Manifest.permission.RECORD_AUDIO);
            if(!SLOTS.tryAcquire())throw new VmHardware.Failure("resource_limit","At most2 recorders, including SDK cleanup, may be owned.");Video video;
            Lease lease=new Lease();try{video=new Video(c,camera,options,settings,audio,lease);}catch(Exception e){if(!lease.sdkOwned)try{lease.discard();}catch(Exception cleanup){e.addSuppressed(cleanup);}throw e;}
            VmHardware.blocking(video);try{synchronized(video){if(video.stopping||video.released)throw new VmHardware.Failure("recorder_error","The recorder failed or stopped during preparation.");}String handle=VmHardware.add(video);synchronized(camera){camera.check();camera.video=video;}camera.configure(new JSONArray(),10000,video);return handle;}catch(Exception e){video.close();throw e;}finally{VmHardware.unblocking();}
        }
        Video video=VmHardware.handle(c,VmHardware.text(a,0,128),Video.class);video.access(c);VmHardware.blocking(video);
        try{if(op.equals("camera_video_stop"))return video.requestStop();if(op.equals("camera_video_seek"))return video.seek(VmHardware.longInteger(a,1,0,64L*1024*1024));
            synchronized(video){video.check();if(!video.state.equals("recording")&&!video.state.equals("paused"))throw new VmHardware.Failure("not_ready","Only an active recording can pause/resume.");video.inFlight++;}
            try{if(op.equals("camera_video_pause"))video.sdk.pause();else if(op.equals("camera_video_resume"))video.sdk.resume();else throw new VmHardware.Failure("unsupported_operation","Unknown video operation.");synchronized(video){if(!video.stopping)video.state=op.equals("camera_video_pause")?"paused":"recording";}return 1;}finally{synchronized(video){video.inFlight--;if(video.stopping&&video.inFlight==0&&!video.starting)video.queueStop();}synchronized(video.camera){if(video.camera.needsCleanup())video.camera.cleanup();}}
        }finally{VmHardware.unblocking();}
    }
}
