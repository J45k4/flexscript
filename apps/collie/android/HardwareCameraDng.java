package org.flexscript.collie;

import android.graphics.ImageFormat;
import android.hardware.camera2.*;
import android.location.Location;
import android.os.SystemClock;
import android.util.Size;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Public DngCreator transport. SDK image rows are copied through short bounded reads. */
final class HardwareCameraDng {
    static final int MAX_INPUT=128*1024*1024,MAX_FILE=129*1024*1024;
    static final Set<Export> OWNED=new HashSet<>();
    static final ThreadPoolExecutor SDK=new ThreadPoolExecutor(1,1,30,TimeUnit.SECONDS,new ArrayBlockingQueue<Runnable>(1),r->{Thread t=new Thread(r,"collie-camera-dng");t.setDaemon(true);return t;});
    static boolean recovered;
    static synchronized File directory(android.content.Context c)throws Exception{
        File dir=new File(c.getCacheDir(),"camera-dng");if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("Cannot create private DNG spool directory.");
        if(!recovered){File[] files=dir.listFiles();if(files==null)throw new IOException("Cannot inspect interrupted DNG spools.");for(File f:files)if(f.getName().matches("collie-dng--?[0-9]+\\.dng")&&!f.delete())throw new IOException("Cannot remove interrupted DNG spool.");recovered=true;}return dir;
    }
    static final class Options {
        final int orientation,timeout;final String description;final Location location;
        Options(Object value)throws Exception{JSONArray row=CameraValues.list(value,4,4);orientation=VmHardware.integer(row,0,0,8);description=VmHardware.text(row,1,1024);JSONArray gps=row.get(2)==JSONObject.NULL?null:CameraValues.list(row.get(2),3,3);location=gps==null?null:(Location)CameraValues.decode("location",new JSONArray().put(gps.get(0)).put(gps.get(1)).put(JSONObject.NULL).put(gps.get(2)).put("collie")).value;timeout=VmHardware.integer(row,3,500,30000);}
    }
    static final class Export extends VmHardware.Handle {
        final VmHardware.Context context;final HardwareCamera.Camera camera;final HardwareCamera.Frame frame;final String resultId;final TotalCaptureResult parent;final CaptureResult result;final CameraCharacteristics characteristics;final Options options;final int generation,width,height,rowStride;final long deadline;
        String state="queued",error="",errorCode="";boolean running,queued,cleanupQueued,released,sdkRequested,sdkReleased=true;File file;DngCreator creator;RandomAccessFile input;long position;
        final Runnable deadlineCheck=this::expired;
        Export(VmHardware.Context c,HardwareCamera.Camera camera,String frameId,String resultId,Options options)throws Exception{
            super(c,"camera","camera_dng");context=c;this.camera=camera;this.resultId=resultId;this.options=options;deadline=SystemClock.elapsedRealtime()+options.timeout;
            synchronized(camera){camera.check();frame=camera.frame(frameId);parent=camera.results.get(resultId);if(parent==null)throw new VmHardware.Failure("stale_result","Choose a retained capture result belonging to this camera.");generation=camera.generation;}
            if(frame.format!=ImageFormat.RAW_SENSOR||frame.lengths.length!=1||frame.pixels[0]!=2)throw new VmHardware.Failure("unsupported_format","DNG export requires one actual RAW_SENSOR16-bit plane.");
            width=frame.width;height=frame.height;rowStride=frame.rows[0];long bytes=(long)width*height*2,last=(long)(height-1)*rowStride+width*2;
            if(bytes>MAX_INPUT)throw new VmHardware.Failure("resource_limit","Packed DNG input exceeds the128MiB image budget.");
            if(rowStride<width*2||last>frame.lengths[0])throw new VmHardware.Failure("invalid_response","SDK RAW plane does not contain all advertised16-bit rows.");
            if(frame.reader.physical.isEmpty()){result=parent;characteristics=camera.ch;}
            else{result=HardwareCameraPhysical.results(parent).get(frame.reader.physical);if(result==null)throw new VmHardware.Failure("unavailable","No matching physical capture result is retained for this RAW output.");characteristics=camera.manager.getCameraCharacteristics(frame.reader.physical);}
            Long timestamp=result.get(CaptureResult.SENSOR_TIMESTAMP);if(timestamp==null||timestamp.longValue()!=frame.timestamp)throw new VmHardware.Failure("invalid_argument","RAW image and selected capture metadata have different sensor timestamps.");
        }
        void event(String name,Object... fields){HardwareBle.event(this,name,fields);}
        synchronized void failed(Exception failure){
            if(state.equals("error"))return;
            state="error";error=MainActivity.safe(failure);errorCode="sdk_error";
            Throwable cause=failure;for(int i=0;cause!=null&&i<8;i++,cause=cause.getCause())if(cause instanceof VmHardware.Failure){errorCode=((VmHardware.Failure)cause).code;break;}
            event("error","code",errorCode,"message",error);
        }
        void source()throws Exception{camera.check();synchronized(camera){if(camera.generation!=generation||camera.frames.get(frame.id)!=frame||camera.results.get(resultId)!=parent)throw new VmHardware.Failure("stale_frame","The source frame/result was closed, evicted or reconfigured during DNG export.");}}
        void guard()throws Exception{check();HardwareCamera.captureAccess(context);if(SystemClock.elapsedRealtime()>=deadline)throw new VmHardware.Failure("timeout","DNG copy/write exceeded its elapsed deadline.");source();}
        void start()throws Exception{
            synchronized(this){check();queued=true;}HardwareCamera.events().postDelayed(deadlineCheck,Math.max(0,deadline-SystemClock.elapsedRealtime()));
            try{SDK.execute(this::run);}catch(RejectedExecutionException error){HardwareCamera.events().removeCallbacks(deadlineCheck);synchronized(this){queued=false;}throw new VmHardware.Failure("busy","DNG SDK worker is busy; no export was submitted.");}
        }
        void run(){
            synchronized(this){queued=false;running=true;state="copying";}
            Exception failure=null;
            try{
                guard();InputStream packed=new InputStream(){int position;final int bytes=width*height*2;
                    public int read()throws IOException{byte[] value=new byte[1];return read(value,0,1)<0?-1:value[0]&255;}
                    public int read(byte[] target,int offset,int count)throws IOException{
                        if(count==0)return 0;if(position==bytes)return -1;
                        try{guard();int row=position/(width*2),x=position%(width*2),n=Math.min(Math.min(count,32768),width*2-x);byte[] part=frame.copy(0,row*rowStride+x,n);System.arraycopy(part,0,target,offset,n);position+=n;return n;}
                        catch(IOException error){throw error;}catch(Exception error){throw new IOException(error);}
                    }
                };
                guard();file=File.createTempFile("collie-dng-",".dng",directory(context.host));synchronized(this){state="writing";sdkRequested=true;sdkReleased=false;}
                creator=new DngCreator(characteristics,result);creator.setOrientation(options.orientation);creator.setDescription(options.description);if(options.location!=null)creator.setLocation(options.location);
                try(FileOutputStream output=new FileOutputStream(file)){
                    OutputStream bounded=new OutputStream(){long bytes;public void write(int b)throws IOException{write(new byte[]{(byte)b},0,1);}public void write(byte[] b,int offset,int count)throws IOException{try{guard();if(count>MAX_FILE-bytes)throw new VmHardware.Failure("size_limit","DNG output exceeds129MiB.");output.write(b,offset,count);bytes+=count;}catch(IOException error){throw error;}catch(Exception error){throw new IOException(error);}}};
                    creator.writeInputStream(bounded,new Size(width,height),packed,0);output.getFD().sync();
                }
                guard();
            }catch(Exception error){failure=error;}
            finally{
                try{if(creator!=null)creator.close();creator=null;sdkReleased=true;}catch(Exception cleanup){if(failure!=null)failure.addSuppressed(cleanup);else failure=cleanup;}
                HardwareCamera.events().removeCallbacks(deadlineCheck);
                synchronized(this){running=false;if(failure!=null)failed(failure);}
                if(failure==null)try{guard();synchronized(camera){source();synchronized(this){check();if(SystemClock.elapsedRealtime()>=deadline)throw new VmHardware.Failure("timeout","DNG deadline expired before publication.");state="ready";event("ready","bytes",file.length(),"sdk_write_returned",true);}}}catch(Exception error){failed(error);}
                synchronized(this){if(closed||state.equals("error"))cleanup();}
            }
        }
        synchronized void expired(){if(!state.equals("ready")&&!state.equals("error")&&SystemClock.elapsedRealtime()>=deadline){state="error";errorCode="timeout";error="DNG operation exceeded its elapsed deadline.";event("error","code",errorCode,"message",error);cleanup();}}
        void access(VmHardware.Context c)throws Exception{super.access(c);HardwareCamera.captureAccess(c);expired();check();}
        synchronized Object info()throws Exception{check();expired();return VmHardware.object("kind",kind,"state",state,"width",width,"height",height,"orientation",options.orientation,"bytes",state.equals("ready")?file.length():JSONObject.NULL,"position",position,"sdk_requested",sdkRequested,"sdk_released",sdkReleased,"cleanup_pending",(closed||state.equals("error"))&&!released,"lease_released",released,"deadline_elapsed_ms",deadline,"code",errorCode,"error",error);}
        synchronized Object read(int limit,int timeout)throws Exception{check();if(!state.equals("ready"))throw new VmHardware.Failure("not_ready","Wait for DNG ready before reading its container.");if(input==null)input=new RandomAccessFile(file,"r");byte[] bytes=new byte[limit];int count=input.read(bytes);if(count<0)return JSONObject.NULL;position+=count;return VmHardware.bytes(Arrays.copyOf(bytes,count));}
        synchronized long seek(long at)throws Exception{check();if(!state.equals("ready"))throw new VmHardware.Failure("not_ready","Wait for DNG ready before seeking.");if(at>file.length())throw new VmHardware.Failure("invalid_argument","DNG offset exceeds the actual file length.");if(input==null)input=new RandomAccessFile(file,"r");input.seek(at);position=at;return at;}
        void cleanup(){
            synchronized(this){if(running||queued||cleanupQueued||released)return;cleanupQueued=true;}
            try{SDK.execute(()->{
                Exception failure=null;
                try{if(creator!=null){creator.close();creator=null;sdkReleased=true;}if(!sdkReleased)throw new IOException("SDK DNG cleanup has not completed.");if(input!=null){input.close();input=null;}if(file!=null&&file.exists()&&!file.delete())throw new IOException("Cannot remove owned DNG spool.");}
                catch(Exception error){failure=error;}
                synchronized(Export.this){cleanupQueued=false;if(failure==null){if(!released){released=true;synchronized(OWNED){OWNED.remove(this);}}}else{error=MainActivity.safe(failure);errorCode="cleanup_failed";}}
            });}catch(RejectedExecutionException error){synchronized(this){cleanupQueued=false;this.error="DNG cleanup is pending; its lease remains owned.";errorCode="busy";}}
        }
        public void close()throws IOException{synchronized(this){if(closed)return;super.close();}HardwareCamera.events().removeCallbacks(deadlineCheck);cleanup();}
    }
    static Object call(VmHardware.Context c,String op,JSONArray args)throws Exception{
        if(op.equals("camera_dng_seek")){Export file=VmHardware.handle(c,VmHardware.text(args,0,128),Export.class);file.access(c);return file.seek(VmHardware.longInteger(args,1,0,MAX_FILE));}
        HardwareCamera.Camera camera=VmHardware.handle(c,VmHardware.text(args,0,128),HardwareCamera.Camera.class);camera.access(c);Export export=new Export(c,camera,VmHardware.text(args,1,128),VmHardware.text(args,2,128),new Options(args.get(3)));
        synchronized(OWNED){if(!OWNED.isEmpty())throw new VmHardware.Failure("resource_limit","Only one DNG export, including retained file and pending cleanup, may be owned.");OWNED.add(export);}
        VmHardware.blocking(export);try{String id=VmHardware.add(export);export.start();return id;}catch(Exception error){export.close();throw error;}finally{VmHardware.unblocking();}
    }
}
