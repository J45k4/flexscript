package org.flexscript.collie;

import android.Manifest;
import android.content.pm.PackageManager;
import android.graphics.ImageFormat;
import android.hardware.camera2.*;
import android.hardware.camera2.params.*;
import android.media.*;
import android.os.*;
import android.util.Size;
import android.view.Surface;
import java.io.*;
import java.nio.ByteBuffer;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Public Camera2 objects, retained image planes and copied callbacks. Policy stays in Flexscript. */
final class HardwareCamera {
    static final Object LOCK=new Object();
    static final Map<String,VmHardware.Handle> OWNERS=new HashMap<>();
    static final Semaphore WATCHES=new Semaphore(8);
    static final long MAX_FRAME_BYTES=128L*1024*1024;static long frameBytes;
    static final ThreadPoolExecutor CLEANUP=new ThreadPoolExecutor(2,2,30,TimeUnit.SECONDS,new ArrayBlockingQueue<Runnable>(64),r->{Thread t=new Thread(r,"collie-camera-cleanup");t.setDaemon(true);return t;});
    static final ThreadPoolExecutor IMAGE_CLEANUP=new ThreadPoolExecutor(2,2,30,TimeUnit.SECONDS,new ArrayBlockingQueue<Runnable>(32),r->{Thread t=new Thread(r,"collie-camera-images");t.setDaemon(true);return t;});
    private static HandlerThread thread;private static Handler handler;
    static synchronized Handler events(){if(thread==null){thread=new HandlerThread("collie-camera-events");thread.setDaemon(true);thread.start();handler=new Handler(thread.getLooper());}return handler;}
    static CameraManager manager(VmHardware.Context c)throws Exception{CameraManager m=c.host.getSystemService(CameraManager.class);if(m==null)throw new VmHardware.Failure("unsupported","Android's camera service is unavailable.");return m;}
    static boolean supports(String op){return op.startsWith("camera_");}
    static String[] ids(VmHardware.Context c)throws Exception{String[] ids=manager(c).getCameraIdList();if(ids.length>128)throw new VmHardware.Failure("size_limit","Android returned more than128 camera IDs.");Arrays.sort(ids);return ids;}
    static CameraCharacteristics characteristics(VmHardware.Context c,String id)throws Exception{if(!Arrays.asList(ids(c)).contains(id))throw new VmHardware.Failure("unavailable","Choose a current camera ID from camera_list.");return manager(c).getCameraCharacteristics(id);}
    static Object nullable(Object value){return value==null?JSONObject.NULL:value;}
    static boolean granted(VmHardware.Context c){return c.host.checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED;}
    static void captureAccess(VmHardware.Context c)throws Exception{if(!granted(c))throw new VmHardware.Failure("permission_revoked","Android camera permission was revoked. Reopen after approval.");if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Camera capture requires a visible Collie Activity.");}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{boolean supported=c.host.getSystemService(CameraManager.class)!=null&&c.host.getPackageManager().hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY);out.put(VmHardware.object("id","camera_capture","implemented",true,"supported",supported,"available",JSONObject.NULL,"permission","camera","foreground_required",true,"android_camera_granted",granted(c),"max_owned_devices_and_torches",4,"image_byte_budget",MAX_FRAME_BYTES,"dng_export_implemented",true,"dng_requires_raw_sensor",true,"max_dng_exports",1,"dng_input_byte_limit",HardwareCameraDng.MAX_INPUT,"dng_file_byte_limit",HardwareCameraDng.MAX_FILE));}
    static JSONObject info(VmHardware.Context c,String id,CameraCharacteristics ch)throws Exception{
        Set<String> physical=Build.VERSION.SDK_INT>=28?ch.getPhysicalCameraIds():Collections.emptySet();if(physical.size()>128)throw new VmHardware.Failure("size_limit","More than128 physical camera IDs.");
        return VmHardware.object("id",id,"lens_facing",nullable(ch.get(CameraCharacteristics.LENS_FACING)),"hardware_level",nullable(ch.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL)),"sensor_orientation",nullable(ch.get(CameraCharacteristics.SENSOR_ORIENTATION)),"flash_available",Boolean.TRUE.equals(ch.get(CameraCharacteristics.FLASH_INFO_AVAILABLE)),"capabilities",CameraValues.encode(ch.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES),0),"physical_ids",new JSONArray(new TreeSet<>(physical)),"physical_controls_api",Build.VERSION.SDK_INT>=28,"physical_request_overrides_implemented",true,"physical_results_implemented",true,"android_camera_granted",granted(c),"characteristic_keys",ch.getKeys().size(),"request_keys",ch.getAvailableCaptureRequestKeys().size(),"result_keys",ch.getAvailableCaptureResultKeys().size());
    }
    static JSONObject page(String name,JSONArray rows,int end,int total)throws Exception{return VmHardware.object(name,rows,"next",end<total?end:-1,"total",total);}
    static StreamConfigurationMap streams(CameraCharacteristics ch)throws Exception{StreamConfigurationMap map=ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);if(map==null)throw new VmHardware.Failure("unavailable","No stream configuration map is exposed by the SDK.");return map;}
    static Object formats(CameraCharacteristics ch,int offset,int limit)throws Exception{int[] formats=streams(ch).getOutputFormats();JSONArray rows=new JSONArray();int end=Math.min(formats.length,offset+limit);for(int i=offset;i<end;i++)rows.put(formats[i]);return page("formats",rows,end,formats.length);}
    static Object sizes(CameraCharacteristics ch,int format,int offset,int limit)throws Exception{
        StreamConfigurationMap map=streams(ch);Size[] sizes=format==0?map.getOutputSizes(MediaRecorder.class):map.getOutputSizes(format);
        if(sizes==null)throw new VmHardware.Failure("unsupported_format","That output format is not advertised by the camera.");
        JSONArray rows=new JSONArray();int end=Math.min(sizes.length,offset+limit);
        for(int i=offset;i<end;i++){Size s=sizes[i];rows.put(VmHardware.object("width",s.getWidth(),"height",s.getHeight(),"minimum_frame_duration_ns",format==0?map.getOutputMinFrameDuration(MediaRecorder.class,s):map.getOutputMinFrameDuration(format,s),"stall_duration_ns",format==0?map.getOutputStallDuration(MediaRecorder.class,s):map.getOutputStallDuration(format,s)));}
        return page("sizes",rows,end,sizes.length);
    }
    static void reserve(String id,VmHardware.Handle owner)throws Exception{synchronized(LOCK){if(OWNERS.containsKey(id))throw new VmHardware.Failure("busy","This camera is owned or awaiting SDK cleanup.");if(OWNERS.size()>=4)throw new VmHardware.Failure("resource_limit","At most4 camera/torch leases, including pending cleanup, may be owned.");OWNERS.put(id,owner);}}
    static void release(String id,VmHardware.Handle owner){synchronized(LOCK){if(OWNERS.get(id)==owner)OWNERS.remove(id);}}
    static final class Watch extends VmHardware.Handle {
        final CameraManager manager;boolean starting,registered,queued;final LinkedHashMap<String,JSONObject> status=new LinkedHashMap<>();
        Watch(VmHardware.Context c)throws Exception{super(c,"camera","camera_watch");manager=manager(c);}
        void status(String id,String kind,Object value){try{synchronized(this){if(closed)return;if(!status.containsKey(id)&&status.size()>=128){emit(VmHardware.object("event","inventory_limit"));return;}JSONObject row=status.get(id);if(row==null){row=VmHardware.object("id",id);status.put(id,row);}row.put(kind,value);emit(VmHardware.object("event",kind,"camera",id,"value",value,"sdk_callback",true));}}catch(Exception ignored){}}
        final CameraManager.AvailabilityCallback availability=new CameraManager.AvailabilityCallback(){public void onCameraAvailable(String id){status(id,"available",true);}public void onCameraUnavailable(String id){status(id,"available",false);}};
        final CameraManager.TorchCallback torch=new CameraManager.TorchCallback(){public void onTorchModeChanged(String id,boolean enabled){status(id,"torch",enabled);}public void onTorchModeUnavailable(String id){status(id,"torch",JSONObject.NULL);}};
        void start()throws Exception{synchronized(this){check();starting=true;}try{manager.registerAvailabilityCallback(availability,events());manager.registerTorchCallback(torch,events());synchronized(this){registered=true;}}finally{synchronized(this){starting=false;if(closed)cleanup();}}}
        synchronized void cleanup(){if(starting||queued)return;queued=true;CLEANUP.execute(()->{try{manager.unregisterAvailabilityCallback(availability);manager.unregisterTorchCallback(torch);WATCHES.release();}catch(Exception ignored){}});}
        synchronized Object info()throws Exception{check();JSONArray rows=new JSONArray();for(JSONObject r:status.values())rows.put(new JSONObject(r.toString()));return VmHardware.object("kind",kind,"cameras",rows);}
        public synchronized void close()throws IOException{if(closed)return;super.close();status.clear();cleanup();}
    }
    static final class Frame {
        final String id="frame-"+UUID.randomUUID();final Reader reader;Image image;ByteBuffer[] planes;final int[] rows,pixels,lengths;final int width,height,format;final long timestamp,bytes;final Object crop,dataSpace;boolean closed,reserved;
        Frame(Reader reader,Image image)throws Exception{this.reader=reader;this.image=image;width=image.getWidth();height=image.getHeight();format=image.getFormat();timestamp=image.getTimestamp();crop=CameraValues.encode(image.getCropRect(),0);dataSpace=HardwareCameraOutput.dataSpace(image);Image.Plane[] source=image.getPlanes();if(source.length<1||source.length>4)throw new VmHardware.Failure("unsupported_format","This image does not expose1..4 CPU-readable planes.");planes=new ByteBuffer[source.length];rows=new int[source.length];pixels=new int[source.length];lengths=new int[source.length];long total=0;for(int i=0;i<source.length;i++){planes[i]=source[i].getBuffer().duplicate().slice().asReadOnlyBuffer();rows[i]=source[i].getRowStride();pixels[i]=source[i].getPixelStride();lengths[i]=planes[i].remaining();total+=lengths[i];}bytes=total;if(total>MAX_FRAME_BYTES)throw new VmHardware.Failure("size_limit","A camera frame exceeds the128MiB image budget.");}
        synchronized JSONObject info()throws Exception{if(closed)throw new VmHardware.Failure("stale_frame","The frame was closed or evicted; acquire a current frame ID.");JSONArray p=new JSONArray();for(int i=0;i<lengths.length;i++)p.put(VmHardware.object("plane",i,"bytes",lengths[i],"row_stride",rows[i],"pixel_stride",pixels[i]));return VmHardware.object("id",id,"output",reader.id,"physical_camera",reader.physical,"width",width,"height",height,"format",format,"timestamp_ns",timestamp,"crop",crop,"data_space",dataSpace,"planes",p);}
        synchronized Object read(int plane,int offset,int limit)throws Exception{if(closed)throw new VmHardware.Failure("stale_frame","The frame was closed or evicted.");if(plane>=planes.length||offset>lengths[plane])throw new VmHardware.Failure("invalid_argument","Invalid image plane or byte offset.");int n=Math.min(limit,lengths[plane]-offset);byte[] data=new byte[n];ByteBuffer b=planes[plane].duplicate();b.position(offset);b.get(data);return VmHardware.object("value",VmHardware.bytes(data),"total",lengths[plane],"next",offset+n<lengths[plane]?offset+n:-1);}
        synchronized byte[] copy(int plane,int offset,int count)throws Exception{if(closed)throw new VmHardware.Failure("stale_frame","The source image closed during DNG copy.");if(plane<0||plane>=planes.length||offset<0||count<0||count>32768||count>lengths[plane]-offset)throw new VmHardware.Failure("invalid_argument","Invalid bounded SDK plane copy.");byte[] data=new byte[count];ByteBuffer bytes=planes[plane].duplicate();bytes.position(offset);bytes.get(data);return data;}
        void close(){synchronized(this){if(closed)return;closed=true;planes=null;}IMAGE_CLEANUP.execute(()->{try{closeNow();}catch(Exception e){reader.camera.error("image_cleanup_failed",e);}});}
        void closeNow()throws Exception{Image closing;synchronized(this){closed=true;planes=null;closing=image;if(closing==null)return;image=null;}try{closing.close();synchronized(LOCK){if(reserved){frameBytes-=bytes;reserved=false;}}synchronized(reader){reader.held.remove(this);}}catch(Exception e){synchronized(this){image=closing;}throw e;}}
    }
    static final class Reader {
        final Camera camera;final HardwareCameraOutput.Spec options;OutputConfiguration configuration;final String id="output-"+UUID.randomUUID(),physical;final ImageReader sdk;final Set<Frame> held=new HashSet<>();volatile boolean closed;
        Reader(Camera camera,HardwareCameraOutput.Spec options){this.camera=camera;this.options=options;this.physical=options.physical;sdk=ImageReader.newInstance(options.width,options.height,options.format,4);try{sdk.setOnImageAvailableListener(this::available,events());}catch(Exception e){sdk.close();throw e;}}
        void available(ImageReader source){if(closed)return;Image image=null;Frame frame=null;try{image=source.acquireLatestImage();if(image==null)return;frame=new Frame(this,image);synchronized(camera){if(closed||camera.closed||!camera.readers.containsKey(id)){return;}int own=0;for(Frame old:camera.frames.values())if(old.reader==this)own++;if(own>=2){Iterator<Frame> it=camera.frames.values().iterator();while(it.hasNext()){Frame old=it.next();if(old.reader==this){it.remove();old.close();camera.event("frame_evicted","frame",old.id);break;}}}if(camera.frames.size()>=6){Frame old=camera.frames.values().iterator().next();camera.frames.remove(old.id);old.close();camera.event("frame_evicted","frame",old.id);}synchronized(LOCK){if(frameBytes+frame.bytes>MAX_FRAME_BYTES)throw new VmHardware.Failure("resource_limit","Camera image byte budget is occupied, including pending SDK image cleanup.");frameBytes+=frame.bytes;frame.reserved=true;}synchronized(this){held.add(frame);}camera.frames.put(frame.id,frame);camera.event("frame","frame",frame.id,"output",id,"timestamp_ns",frame.timestamp,"sdk_callback",true);image=null;}}
            catch(Exception error){camera.error("frame_error",error);}finally{if(image!=null)try{image.close();}catch(Exception ignored){}}}
        void closeNow()throws Exception{List<Frame> images;synchronized(this){closed=true;images=new ArrayList<>(held);}Exception failure=null;for(Frame f:images)try{f.closeNow();}catch(Exception e){failure=e;}try{sdk.setOnImageAvailableListener(null,null);sdk.close();}catch(Exception e){failure=e;}if(failure!=null)throw failure;}
    }
    static final class Camera extends VmHardware.Handle {
        final VmHardware.Context context;final CameraManager manager;final String cameraId;final CameraCharacteristics ch;int configurationColorSpace=-1;
        final LinkedHashMap<String,Reader> readers=new LinkedHashMap<>();final LinkedHashMap<String,Frame> frames=new LinkedHashMap<>();final LinkedHashMap<String,TotalCaptureResult> results=new LinkedHashMap<>();final Set<Integer> pendingSequences=new HashSet<>(),earlyTerminals=new HashSet<>();int reservations;
        CameraDevice sdk;CameraCaptureSession session;HardwareCameraVideo.Video video;String state="opening",cleanupError="";boolean starting,requested,terminal,cleanupQueued,cleaned,released;int inFlight,generation,pendingReaders;long deadlineElapsed;final int timeout;
        final Runnable deadline=this::expired;
        Camera(VmHardware.Context c,String id,CameraCharacteristics ch,int timeout)throws Exception{super(c,"camera","camera");context=c;cameraId=id;this.ch=ch;this.timeout=timeout;manager=manager(c);}
        void event(String name,Object... values){try{Object[] all=new Object[values.length+2];all[0]="event";all[1]=name;System.arraycopy(values,0,all,2,values.length);emit(VmHardware.object(all));}catch(Exception ignored){}}
        void error(String code,Exception error){event("error","code",error instanceof VmHardware.Failure?((VmHardware.Failure)error).code:code,"message",MainActivity.safe(error));}
        synchronized void expired(){if(!closed&&(state.equals("opening")||state.equals("configuring"))&&SystemClock.elapsedRealtime()>=deadlineElapsed){state="error";event("error","code","timeout","message","Camera startup/configuration exceeded its elapsed-time deadline.");cleanup();}}
        void access(VmHardware.Context c)throws Exception{super.access(c);try{captureAccess(c);}catch(Exception error){close();throw error;}}
        synchronized CameraDevice use()throws Exception{check();expired();if(sdk==null||terminal||state.equals("closed")||state.equals("stopping")||state.equals("opening")||state.equals("error"))throw new VmHardware.Failure("not_ready","Wait for the real SDK opened/configured event before using this camera.");inFlight++;return sdk;}
        synchronized boolean needsCleanup(){return closed||state.equals("error")||state.equals("stopping")||state.equals("closed");}
        synchronized void end(){inFlight--;if(needsCleanup())cleanup();}
        void start()throws Exception{
            synchronized(this){check();deadlineElapsed=SystemClock.elapsedRealtime()+timeout;events().postDelayed(deadline,timeout);starting=true;requested=true;}
            try{captureAccess(context);synchronized(this){expired();if(closed||!state.equals("opening")){requested=false;terminal=true;return;}}manager.openCamera(cameraId,new CameraDevice.StateCallback(){
                public void onOpened(CameraDevice device){synchronized(Camera.this){sdk=device;expired();if(closed||!state.equals("opening")){cleanup();return;}state="open";events().removeCallbacks(deadline);event("opened","camera",cameraId,"sdk_callback",true);}}
                public void onDisconnected(CameraDevice device){synchronized(Camera.this){sdk=device;if(!closed){state="error";event("disconnected","sdk_callback",true);}cleanup();}}
                public void onError(CameraDevice device,int reason){synchronized(Camera.this){sdk=device;if(!closed){state="error";event("error","code","sdk_error","reason",reason,"sdk_callback",true);}cleanup();}}
                public void onClosed(CameraDevice device){synchronized(Camera.this){terminal=true;if(!closed){state="closed";event("closed","sdk_callback",true);}cleanup();releaseLease();}}
            },events());}catch(Exception error){synchronized(this){state="error";requested=false;terminal=true;}throw error;}
            finally{synchronized(this){starting=false;if(needsCleanup())cleanup();}}
        }
        synchronized void releaseLease(){if(!released&&terminal&&cleaned&&(video==null||video.released)){released=true;events().removeCallbacks(deadline);release(cameraId,this);}}
        synchronized void cleanup(){if(starting||inFlight>0||cleanupQueued||video!=null&&(video.starting||video.inFlight>0))return;if(requested&&sdk==null&&!terminal)return;cleanupQueued=true;final CameraDevice device=sdk;final CameraCaptureSession current=session;final HardwareCameraVideo.Video recording=video;final ArrayList<Reader> outputs=new ArrayList<>(readers.values());final ArrayList<Frame> images=new ArrayList<>(frames.values());for(Reader reader:outputs)reader.closed=true;readers.clear();frames.clear();results.clear();pendingSequences.clear();earlyTerminals.clear();session=null;CLEANUP.execute(()->{String failure="";if(current!=null){try{current.stopRepeating();}catch(Exception ignored){}try{current.close();}catch(Exception e){failure=MainActivity.safe(e);}}if(device!=null)try{device.close();}catch(Exception e){failure=MainActivity.safe(e);}if(recording!=null)try{recording.cleanupNow();}catch(Exception e){failure=MainActivity.safe(e);}for(Frame image:images)try{image.closeNow();}catch(Exception e){failure=MainActivity.safe(e);}for(Reader reader:outputs)try{reader.closeNow();}catch(Exception e){failure=MainActivity.safe(e);}synchronized(Camera.this){cleanupError=failure;cleaned=failure.isEmpty();if(!requested)terminal=true;releaseLease();}});}

        synchronized Object info()throws Exception{check();expired();JSONArray outputs=new JSONArray();for(Reader r:readers.values())outputs.put(VmHardware.object("id",r.id,"width",r.sdk.getWidth(),"height",r.sdk.getHeight(),"format",r.sdk.getImageFormat(),"physical_camera",r.physical,"dynamic_range_profile",HardwareCameraOutput.profile(r.configuration),"stream_use_case",HardwareCameraOutput.useCase(r.configuration)));long used;synchronized(LOCK){used=frameBytes;}return VmHardware.object("kind",kind,"camera",cameraId,"state",state,"configuration_color_space_id",configurationColorSpace<0?JSONObject.NULL:configurationColorSpace,"outputs",outputs,"frames",frames.size(),"results",results.size(),"pending_capture_sequences",pendingSequences.size()+reservations,"sdk_requested",requested,"sdk_terminal",terminal,"lease_released",released,"cleanup_pending",cleanupQueued&&!cleaned,"cleanup_error",cleanupError,"image_bytes_including_cleanup",used);}
        synchronized int shutdown()throws Exception{check();if(state.equals("closed")||state.equals("stopping"))return 0;state="stopping";if(video!=null)video.invalidateForParent();events().removeCallbacks(deadline);cleanup();return 1;}
        public synchronized void close()throws IOException{if(closed)return;super.close();state="closed";if(video!=null)video.invalidateForParent();events().removeCallbacks(deadline);cleanup();}
        Frame frame(String id)throws Exception{synchronized(this){check();Frame f=frames.get(id);if(f==null)throw new VmHardware.Failure("stale_frame","Unknown or evicted frame ID for this camera.");return f;}}
        void clearImages(){ArrayList<Frame> old;synchronized(this){old=new ArrayList<>(frames.values());frames.clear();results.clear();pendingSequences.clear();earlyTerminals.clear();}for(Frame f:old)f.close();}
        void retire(List<Reader> old){if(old.isEmpty())return;synchronized(this){pendingReaders+=old.size();for(Reader r:old)r.closed=true;}CLEANUP.execute(()->{for(Reader r:old)try{r.closeNow();synchronized(Camera.this){pendingReaders--;}}catch(Exception e){synchronized(Camera.this){cleanupError=MainActivity.safe(e);}}});}
        void configure(JSONArray options,int timeout,HardwareCameraVideo.Video recording)throws Exception{configure(options,timeout,recording,-1);}
        void configure(JSONArray options,int timeout,HardwareCameraVideo.Video recording,int colorSpace)throws Exception{
            CameraDevice device=use();ArrayList<Reader> outputs=new ArrayList<>();int token=0;
            try{
                synchronized(this){if(state.equals("configuring")||pendingReaders>0||video!=null&&video!=recording)throw new VmHardware.Failure("busy","Finish the current configuration/recording and SDK reader cleanup before reconfiguring.");}
                ArrayList<OutputConfiguration> configs=new ArrayList<>();
                ArrayList<HardwareCameraOutput.Spec> specs=new ArrayList<>();
                for(int i=0;i<options.length();i++)specs.add(new HardwareCameraOutput.Spec(manager,ch,options.get(i)));
                HardwareCameraOutput.validateColor(specs,colorSpace);
                for(HardwareCameraOutput.Spec spec:specs){Reader reader=new Reader(this,spec);outputs.add(reader);OutputConfiguration config=new OutputConfiguration(reader.sdk.getSurface());if(!spec.physical.isEmpty())config.setPhysicalCameraId(spec.physical);spec.apply(config);reader.configuration=config;configs.add(config);}
                if(recording!=null){OutputConfiguration config=new OutputConfiguration(recording.surface());recording.configure(config);configs.add(config);}
                List<Reader> old;synchronized(this){check();captureAccess(context);old=new ArrayList<>(readers.values());readers.clear();for(Reader r:outputs)readers.put(r.id,r);video=recording;configurationColorSpace=-1;token=++generation;state="configuring";deadlineElapsed=SystemClock.elapsedRealtime()+timeout;events().removeCallbacks(deadline);events().postDelayed(deadline,timeout);}clearImages();retire(old);final int version=token;
                CameraCaptureSession.StateCallback callback=new CameraCaptureSession.StateCallback(){
                    public void onConfigured(CameraCaptureSession value){synchronized(Camera.this){expired();if(closed||generation!=version||!state.equals("configuring")){CLEANUP.execute(value::close);return;}session=value;state="configured";events().removeCallbacks(deadline);event("configured","generation",version,"sdk_callback",true);}if(recording!=null)try{recording.startConfigured();}catch(Exception e){error("video_start_failed",e);synchronized(Camera.this){state="error";cleanup();}}}
                    public void onConfigureFailed(CameraCaptureSession value){value.close();synchronized(Camera.this){if(!closed&&generation==version){state="error";event("error","code","configuration_failed","sdk_callback",true);cleanup();}}}
                    public void onClosed(CameraCaptureSession value){synchronized(Camera.this){if(!closed&&session==value){session=null;if(state.equals("configured"))state="open";event("session_closed","sdk_callback",true);}}}
                };
                if(colorSpace>=0)HardwareCameraOutput.configure(this,device,configs,callback,colorSpace);else device.createCaptureSessionByOutputConfigurations(configs,callback,events());
            }catch(Exception e){if(token==0){for(Reader r:outputs)try{r.closeNow();}catch(Exception cleanup){e.addSuppressed(cleanup);}}else synchronized(this){state="error";cleanup();}throw e;}finally{end();}
        }
        @SuppressWarnings({"unchecked","rawtypes"}) CaptureRequest request(CameraDevice device,int template,JSONArray settings,HardwareCameraVideo.Video recording)throws Exception{
            HashSet<String> physical=new HashSet<>();ArrayList<Surface> targets=new ArrayList<>();boolean logical=false;synchronized(this){for(Reader r:readers.values()){targets.add(r.sdk.getSurface());if(!r.physical.isEmpty())physical.add(r.physical);else logical=true;}if(recording!=null){targets.add(recording.surface());logical=true;}}
            synchronized(this){HardwareCameraOutput.validateTargets(readers.values(),recording);}
            List<HardwareCameraPhysical.Setting> parsed=HardwareCameraPhysical.settings(ch,physical,logical,settings);
            CaptureRequest.Builder b=physical.isEmpty()?device.createCaptureRequest(template):device.createCaptureRequest(template,physical);
            HardwareCameraPhysical.apply(b,parsed);
            for(Surface surface:targets)b.addTarget(surface);return b.build();
        }
        synchronized void finished(int sequence){if(!pendingSequences.remove(sequence)&&reservations>0&&earlyTerminals.size()<16)earlyTerminals.add(sequence);}
        final CameraCaptureSession.CaptureCallback captures=new CameraCaptureSession.CaptureCallback(){
            public void onCaptureStarted(CameraCaptureSession s,CaptureRequest request,long timestamp,long frame){synchronized(Camera.this){if(!closed&&s==session)event("capture_started","frame_number",frame,"timestamp_ns",timestamp,"sdk_callback",true);}}
            public void onCaptureCompleted(CameraCaptureSession s,CaptureRequest request,TotalCaptureResult result){synchronized(Camera.this){if(closed||s!=session)return;String id="result-"+UUID.randomUUID();if(results.size()>=8)results.remove(results.keySet().iterator().next());results.put(id,result);event("capture_completed","result",id,"sequence_id",result.getSequenceId(),"frame_number",result.getFrameNumber(),"timestamp_ns",nullable(result.get(CaptureResult.SENSOR_TIMESTAMP)),"sdk_callback",true);}}
            public void onCaptureFailed(CameraCaptureSession s,CaptureRequest r,CaptureFailure f){synchronized(Camera.this){if(!closed&&s==session)event("capture_failed","reason",f.getReason(),"frame_number",f.getFrameNumber(),"sequence_id",f.getSequenceId(),"image_captured",f.wasImageCaptured(),"sdk_callback",true);}}
            public void onCaptureSequenceCompleted(CameraCaptureSession s,int sequence,long frame){synchronized(Camera.this){finished(sequence);if(!closed&&s==session)event("sequence_completed","sequence_id",sequence,"last_frame_number",frame,"sdk_callback",true);}}
            public void onCaptureSequenceAborted(CameraCaptureSession s,int sequence){synchronized(Camera.this){finished(sequence);if(!closed&&s==session)event("sequence_aborted","sequence_id",sequence,"sdk_callback",true);}}
        };
        int capture(int template,JSONArray settings,boolean repeat)throws Exception{CameraDevice device=use();boolean reserved=false;try{CameraCaptureSession target;HardwareCameraVideo.Video recording;synchronized(this){if(!state.equals("configured")||session==null)throw new VmHardware.Failure("not_ready","Wait for an actual configured callback.");if(pendingSequences.size()+reservations>=16)throw new VmHardware.Failure("resource_limit","At most16 submitted capture sequences may await actual SDK completion/abort.");reservations++;reserved=true;target=session;recording=video;}CaptureRequest request=request(device,template,settings,recording);int sequence=repeat?target.setRepeatingRequest(request,captures,events()):target.capture(request,captures,events());synchronized(this){if(!earlyTerminals.remove(sequence)&&!needsCleanup())pendingSequences.add(sequence);}return sequence;}finally{synchronized(this){if(reserved)reservations--;}end();}}
    }
    static Object keys(Object metadata,int offset,int limit)throws Exception{ArrayList<String> keys=new ArrayList<>();if(metadata instanceof CameraCharacteristics)for(CameraCharacteristics.Key<?> k:((CameraCharacteristics)metadata).getKeys())keys.add(k.getName());else if(metadata instanceof CaptureResult)for(CaptureResult.Key<?> k:((CaptureResult)metadata).getKeys())keys.add(k.getName());Collections.sort(keys);JSONArray rows=new JSONArray();int end=Math.min(keys.size(),offset+limit);for(int i=offset;i<end;i++)rows.put(keys.get(i));return page("keys",rows,end,keys.size());}
    static Object value(Object metadata,String key,int offset,int limit)throws Exception{if(metadata instanceof CameraCharacteristics){CameraCharacteristics c=(CameraCharacteristics)metadata;for(CameraCharacteristics.Key<?> k:c.getKeys())if(k.getName().equals(key))return CameraValues.page(c.get(k),offset,limit);}else{CaptureResult c=(CaptureResult)metadata;for(CaptureResult.Key<?> k:c.getKeys())if(k.getName().equals(key))return CameraValues.page(c.get(k),offset,limit);}throw new VmHardware.Failure("unsupported_key","That metadata key is not present in the actual SDK snapshot.");}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        try{return dispatch(c,op,a);}catch(CameraAccessException e){throw new VmHardware.Failure(e.getReason()==CameraAccessException.CAMERA_DISABLED?"camera_disabled":e.getReason()==CameraAccessException.CAMERA_DISCONNECTED?"disconnected":"camera_error",MainActivity.safe(e));}
    }
    static Object dispatch(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(HardwareCameraEncoderProfiles.supports(op))return HardwareCameraEncoderProfiles.call(c,op,a);
        if(op.equals("camera_dng")||op.equals("camera_dng_seek"))return HardwareCameraDng.call(c,op,a);
        if(HardwareCameraPhysical.inventory(op))return HardwareCameraPhysical.inventory(c,op,a);
        if(op.equals("camera_list")){int offset=VmHardware.integer(a,0,0,128),limit=VmHardware.integer(a,1,1,16);String[] ids=ids(c);int end=Math.min(ids.length,offset+limit);JSONArray rows=new JSONArray();for(int i=offset;i<end;i++)rows.put(info(c,ids[i],manager(c).getCameraCharacteristics(ids[i])));return page("cameras",rows,end,ids.length);}
        if(op.equals("camera_watch")){if(!WATCHES.tryAcquire())throw new VmHardware.Failure("resource_limit","At most8 camera observers including cleanup.");Watch watch;try{watch=new Watch(c);}catch(Exception e){WATCHES.release();throw e;}VmHardware.blocking(watch);try{String id=VmHardware.add(watch);watch.start();return id;}catch(Exception e){watch.close();throw e;}finally{VmHardware.unblocking();}}
        if(op.equals("camera_info")||op.equals("camera_keys")||op.equals("camera_value")||op.equals("camera_formats")||op.equals("camera_output_sizes")||op.equals("camera_open")||op.equals("camera_torch_open")){
            String id=VmHardware.text(a,0,128);CameraCharacteristics ch=characteristics(c,id);
            if(op.equals("camera_info"))return info(c,id,ch);
            if(op.equals("camera_keys")){int kind=VmHardware.integer(a,1,0,3),offset=VmHardware.integer(a,2,0,10000),limit=VmHardware.integer(a,3,1,32);if(kind==0)return keys(ch,offset,limit);ArrayList<String> names=new ArrayList<>();if(kind==1)for(CaptureRequest.Key<?> k:ch.getAvailableCaptureRequestKeys())names.add(k.getName());else if(kind==2)for(CaptureResult.Key<?> k:ch.getAvailableCaptureResultKeys())names.add(k.getName());else{if(Build.VERSION.SDK_INT<28)throw new VmHardware.Failure("unsupported_operation","Physical request keys require Android9+.");List<CaptureRequest.Key<?>> physical=ch.getAvailablePhysicalCameraRequestKeys();if(physical!=null)for(CaptureRequest.Key<?> k:physical)names.add(k.getName());}Collections.sort(names);JSONArray rows=new JSONArray();int end=Math.min(names.size(),offset+limit);for(int i=offset;i<end;i++)rows.put(names.get(i));return page("keys",rows,end,names.size());}
            if(op.equals("camera_value"))return value(ch,VmHardware.text(a,1,256),VmHardware.integer(a,2,0,1000000),VmHardware.integer(a,3,1,32));
            if(op.equals("camera_formats"))return formats(ch,VmHardware.integer(a,1,0,10000),VmHardware.integer(a,2,1,32));
            if(op.equals("camera_output_sizes"))return sizes(ch,VmHardware.integer(a,1,0,Integer.MAX_VALUE),VmHardware.integer(a,2,0,10000),VmHardware.integer(a,3,1,16));
            if(op.equals("camera_torch_open"))return HardwareCameraTorch.open(c,id,ch,VmHardware.integer(a,1,0,1000));
            int timeout=VmHardware.integer(a,1,500,30000);VmHardware.require(c,Manifest.permission.CAMERA);captureAccess(c);Camera camera=new Camera(c,id,ch,timeout);reserve(id,camera);VmHardware.blocking(camera);try{String handle=VmHardware.add(camera);camera.start();return handle;}catch(Exception e){camera.close();throw e;}finally{VmHardware.unblocking();}
        }
        if(HardwareCameraVideo.supports(op))return HardwareCameraVideo.call(c,op,a);
        Camera camera=VmHardware.handle(c,VmHardware.text(a,0,128),Camera.class);camera.access(c);VmHardware.blocking(camera);
        try{
            if(HardwareCameraPhysical.resultOperation(op))return HardwareCameraPhysical.result(camera,op,a);
            if(op.equals("camera_shutdown"))return camera.shutdown();
            if(op.equals("camera_configure")){JSONArray outputs=CameraValues.list(a.get(1),1,3);int timeout=VmHardware.integer(a,2,500,30000);camera.configure(outputs,timeout,null,HardwareCameraOutput.color(a,3));return 1;}
            if(op.equals("camera_capture"))return camera.capture(VmHardware.integer(a,1,1,6),CameraValues.list(a.get(2),0,64),VmHardware.integer(a,3,0,1)==1);
            if(op.equals("camera_stop")){CameraDevice sdk=camera.use();try{CameraCaptureSession s;synchronized(camera){s=camera.session;}if(s!=null)s.stopRepeating();return 1;}finally{camera.end();}}
            if(op.equals("camera_frames")){int offset=VmHardware.integer(a,1,0,6),limit=VmHardware.integer(a,2,1,6);synchronized(camera){ArrayList<Frame> frames=new ArrayList<>(camera.frames.values());JSONArray rows=new JSONArray();int end=Math.min(frames.size(),offset+limit);for(int i=offset;i<end;i++)rows.put(frames.get(i).info());return page("frames",rows,end,frames.size());}}
            if(op.equals("camera_frame_info"))return camera.frame(VmHardware.text(a,1,128)).info();
            if(op.equals("camera_frame_read"))return camera.frame(VmHardware.text(a,1,128)).read(VmHardware.integer(a,2,0,3),VmHardware.integer(a,3,0,Integer.MAX_VALUE),VmHardware.integer(a,4,1,32768));
            if(op.equals("camera_frame_close")){Frame frame;String id=VmHardware.text(a,1,128);synchronized(camera){frame=camera.frames.remove(id);}if(frame==null)throw new VmHardware.Failure("stale_frame","Unknown or evicted camera frame.");frame.close();return 1;}
            if(op.equals("camera_result_keys")||op.equals("camera_result_value")){String id=VmHardware.text(a,1,128);TotalCaptureResult result;synchronized(camera){result=camera.results.get(id);}if(result==null)throw new VmHardware.Failure("stale_result","Unknown or evicted actual SDK capture result.");if(op.equals("camera_result_keys"))return keys(result,VmHardware.integer(a,2,0,10000),VmHardware.integer(a,3,1,32));return value(result,VmHardware.text(a,2,256),VmHardware.integer(a,3,0,1000000),VmHardware.integer(a,4,1,32));}
            throw new VmHardware.Failure("unsupported_operation","Unknown camera operation.");
        }finally{VmHardware.unblocking();}
    }
}
