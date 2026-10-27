package org.flexscript.collie;

import android.Manifest;
import android.content.pm.PackageManager;
import android.hardware.display.VirtualDisplay;
import android.media.MediaRecorder;
import android.os.Build;
import android.view.Surface;
import java.io.*;
import java.util.Arrays;
import org.json.*;

/** Recorder surfaces and bounded private MP4 resources for an existing projection. */
final class HardwareScreenVideo {
    private static boolean recovered;
    static synchronized File directory(android.content.Context c)throws IOException{
        File dir=new File(c.getCacheDir(),"screen-captures");if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("Cannot create the private screen spool directory.");
        if(!recovered){File[] files=dir.listFiles();if(files==null)throw new IOException("Cannot inspect private screen spools.");for(File f:files)if(f.getName().matches("collie-screen--?[0-9]+\\.mp4")&&!f.delete())throw new IOException("Cannot remove an interrupted screen spool.");recovered=true;}return dir;
    }
    static boolean supports(String op){return op.startsWith("screen_video_");}
    static final class Options {
        final int width,height,fps,bitrate,duration,codec;final long limit;
        Options(JSONArray a)throws Exception{CameraValues.list(a,7,7);width=VmHardware.integer(a,0,1,8192);height=VmHardware.integer(a,1,1,8192);HardwareScreenCapture.geometry(width,height,160);fps=VmHardware.integer(a,2,1,120);bitrate=VmHardware.integer(a,3,64000,50000000);duration=VmHardware.integer(a,4,500,120000);limit=VmHardware.longInteger(a,5,65536,64L*1024*1024);codec=VmHardware.integer(a,6,0,3);if(codec==3&&Build.VERSION.SDK_INT<34)throw new VmHardware.Failure("unsupported_operation","MediaRecorder AV1 requires Android14+.");}
    }
    static final class Video extends VmHardware.Handle {
        final VmHardware.Context context;final HardwareScreenCapture.Session session;final Options options;final boolean audio;final HardwareCameraVideo.Lease lease;final File file;final MediaRecorder sdk;final Object io=new Object();
        Surface output;RandomAccessFile input;long position;String state="prepared",error="";boolean started,stopping,deleteOnStop;volatile boolean released;
        Video(VmHardware.Context c,HardwareScreenCapture.Session s,Options options,boolean audio,HardwareCameraVideo.Lease lease)throws Exception{
            super(c,"screen_capture","screen_video",audio?"microphone":"");context=c;session=s;this.options=options;this.audio=audio;this.lease=lease;
            file=File.createTempFile("collie-screen-",".mp4",directory(c.host));lease.file=file;sdk=Build.VERSION.SDK_INT>=31?new MediaRecorder(c.host.getApplicationContext()):new MediaRecorder();lease.sdkOwned=true;
            try{if(audio)sdk.setAudioSource(MediaRecorder.AudioSource.MIC);sdk.setVideoSource(MediaRecorder.VideoSource.SURFACE);sdk.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);sdk.setVideoEncoder(options.codec==0?MediaRecorder.VideoEncoder.DEFAULT:options.codec==1?MediaRecorder.VideoEncoder.H264:options.codec==2?MediaRecorder.VideoEncoder.HEVC:MediaRecorder.VideoEncoder.AV1);sdk.setVideoSize(options.width,options.height);sdk.setVideoFrameRate(options.fps);sdk.setVideoEncodingBitRate(options.bitrate);if(audio){sdk.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);sdk.setAudioSamplingRate(48000);sdk.setAudioChannels(1);sdk.setAudioEncodingBitRate(64000);}sdk.setMaxDuration(options.duration);sdk.setMaxFileSize(options.limit);sdk.setOutputFile(file);
                sdk.setOnErrorListener((r,what,extra)->{synchronized(Video.this){error="SDK recorder error "+what+"/"+extra;}event("error","sdk_code",what,"extra",extra,"sdk_callback",true);requestStop();});
                sdk.setOnInfoListener((r,what,extra)->{event("recorder_info","sdk_code",what,"extra",extra,"sdk_callback",true);if(what==MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED||what==MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED)requestStop();});sdk.prepare();output=sdk.getSurface();
            }catch(Exception e){try{sdk.release();if(output!=null)output.release();lease.sdkFreed=true;released=true;lease.discard();}catch(Exception cleanup){e.addSuppressed(cleanup);}throw e;}
        }
        void event(String name,Object... fields){HardwareBle.event(this,name,fields);}
        void access(VmHardware.Context c)throws Exception{super.access(c);if(audio&&!released&&c.host.checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED){close();throw new VmHardware.Failure("permission_revoked","Android microphone permission was revoked.");}}
        void start(VirtualDisplay display)throws Exception{
            synchronized(io){synchronized(this){check();if(stopping)throw new VmHardware.Failure("cancelled","The recorder was cancelled before start.");}session.clearFrames();display.resize(options.width,options.height,session.dpi);display.setSurface(output);sdk.start();synchronized(this){started=true;state="recording";event("recording","sdk_start_returned",true);}}
        }
        int requestStop(){
            synchronized(session){synchronized(this){if(released||stopping)return 0;stopping=true;state="stopping";}if(session.stopping()){session.cleanup();return 1;}session.inFlight++;}
            HardwareScreenCapture.SDK.execute(()->{try{stopNow(false);}catch(Exception e){synchronized(Video.this){error=MainActivity.safe(e);state="error";}}finally{session.end();}});return 1;
        }
        void stopNow(boolean delete)throws Exception{
            synchronized(io){boolean active;synchronized(this){deleteOnStop|=delete;if(released){if(deleteOnStop||closed)discard();return;}stopping=true;state="stopping";active=started;}
                String failure="";VirtualDisplay display;HardwareScreenCapture.Reader reader;boolean restore;
                synchronized(session){display=session.display;reader=session.reader;restore=!session.stopping();}
                try{if(display!=null)display.setSurface(null);}catch(Exception e){failure=MainActivity.safe(e);}
                try{if(active)sdk.stop();}catch(Exception e){failure=MainActivity.safe(e);}
                boolean freed=false;try{sdk.release();if(output!=null)output.release();freed=true;}catch(Exception e){failure=MainActivity.safe(e);}
                if(restore&&display!=null&&reader!=null)try{display.resize(session.width,session.height,session.dpi);display.setSurface(reader.sdk.getSurface());}catch(Exception e){failure=MainActivity.safe(e);}
                if(audio&&session.service!=null&&restore)try{session.service.microphone(session,false);}catch(Exception e){failure=MainActivity.safe(e);}
                synchronized(this){released=freed;lease.sdkFreed=freed;started=false;if(file.length()>options.limit)failure="The recorder exceeded the requested file-byte bound.";if(!error.isEmpty()&&failure.isEmpty())failure=error;if(!failure.isEmpty()){error=failure;state="error";event("error","code","recording_failed","message",failure);}else if(active){state="stopped";event("stopped","bytes",file.length(),"sdk_stop_returned",true);}else state="cancelled";if(freed&&(closed||deleteOnStop||!failure.isEmpty()))discard();}
                synchronized(session){if(freed&&session.video==this)session.video=null;session.release();}
            }
        }
        int control(boolean pause)throws Exception{session.begin();try{synchronized(io){synchronized(this){check();if(stopping||(!state.equals("recording")&&!state.equals("paused")))throw new VmHardware.Failure("not_ready","Only an active screen recorder can pause/resume.");}if(pause)sdk.pause();else sdk.resume();synchronized(this){state=pause?"paused":"recording";}return 1;}}finally{session.end();}}
        synchronized void discard()throws IOException{if(input!=null){input.close();input=null;}lease.discard();}
        synchronized Object read(int count,int timeout)throws Exception{check();if(!state.equals("stopped"))throw new VmHardware.Failure("not_ready","Wait for recorder stop and finalization before reading MP4 bytes.");if(input==null)input=new RandomAccessFile(file,"r");byte[] b=new byte[count];int n=input.read(b);if(n<0)return JSONObject.NULL;position+=n;return VmHardware.bytes(Arrays.copyOf(b,n));}
        synchronized Object seek(long offset)throws Exception{check();if(!state.equals("stopped"))throw new VmHardware.Failure("not_ready","Finalize the recording before seeking.");if(offset>file.length())throw new VmHardware.Failure("invalid_argument","Video offset exceeds its finalized length.");if(input==null)input=new RandomAccessFile(file,"r");input.seek(offset);position=offset;return offset;}
        synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"width",options.width,"height",options.height,"fps",options.fps,"bitrate",options.bitrate,"audio",audio,"duration_limit_ms",options.duration,"byte_limit",options.limit,"bytes",released?file.length():JSONObject.NULL,"position",position,"sdk_released",released,"error",error);}
        public void close()throws IOException{synchronized(this){if(closed)return;super.close();deleteOnStop=true;if(released){discard();return;}}requestStop();}
    }
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(op.equals("screen_video_start")||op.equals("screen_video_audio_start")){
            HardwareScreenCapture.Session session=VmHardware.handle(c,VmHardware.text(a,0,128),HardwareScreenCapture.Session.class);Options options=new Options(CameraValues.list(a.get(1),7,7));boolean audio=op.equals("screen_video_audio_start");
            if(audio){VmHardware.require(c,Manifest.permission.RECORD_AUDIO);if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Start microphone recording while Collie is visible.");}
            VirtualDisplay display=session.begin();Video video=null;HardwareCameraVideo.Lease lease=null;boolean ownsStartup=false;
            try{synchronized(session){if(session.video!=null||session.videoStarting||session.pendingReaders>0)throw new VmHardware.Failure("busy","Only one recorder and completed reader cleanup may belong to a projection.");session.videoStarting=true;ownsStartup=true;}
                if(!HardwareCameraVideo.SLOTS.tryAcquire())throw new VmHardware.Failure("resource_limit","At most2 camera/screen recorders or finalized files, including SDK cleanup, may be owned.");lease=new HardwareCameraVideo.Lease();video=new Video(c,session,options,audio,lease);VmHardware.blocking(video);String handle=VmHardware.add(video);synchronized(session){session.check();if(session.stopping())throw new VmHardware.Failure("disconnected","The projection has ended.");session.video=video;}if(audio)session.service.microphone(session,true);video.start(display);return handle;
            }catch(Exception e){if(video!=null){synchronized(video){video.deleteOnStop=true;video.closed=true;}try{video.stopNow(true);}catch(Exception cleanup){e.addSuppressed(cleanup);}}else if(lease!=null&&!lease.sdkOwned)try{lease.discard();}catch(Exception cleanup){e.addSuppressed(cleanup);}throw e;}
            finally{VmHardware.unblocking();synchronized(session){if(ownsStartup)session.videoStarting=false;}session.end();}
        }
        Video video=VmHardware.handle(c,VmHardware.text(a,0,128),Video.class);video.access(c);VmHardware.blocking(video);
        try{if(op.equals("screen_video_stop"))return video.requestStop();if(op.equals("screen_video_seek"))return video.seek(VmHardware.longInteger(a,1,0,64L*1024*1024));if(op.equals("screen_video_pause"))return video.control(true);if(op.equals("screen_video_resume"))return video.control(false);throw new VmHardware.Failure("unsupported_operation","Unknown screen recorder operation.");}finally{VmHardware.unblocking();}
    }
}
