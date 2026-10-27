package org.flexscript.collie;

import android.graphics.ColorSpace;
import android.hardware.camera2.*;
import android.hardware.camera2.params.*;
import android.media.MediaRecorder;
import android.os.*;
import android.util.*;
import java.util.*;
import org.json.*;

/** Public capture-rate and constrained-session SDK transport. No normal-session fallback. */
final class HardwareCameraRates {
    static boolean supports(String op){return op.equals("camera_high_speed_sizes")||op.equals("camera_high_speed_ranges");}
    static boolean supported(CameraCharacteristics ch){int[] values=ch.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES);if(values!=null)for(int value:values)if(value==CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_CONSTRAINED_HIGH_SPEED_VIDEO)return true;return false;}
    static Size[] sizes(CameraCharacteristics ch)throws Exception{Size[] sizes=HardwareCamera.streams(ch).getHighSpeedVideoSizes();if(sizes==null)sizes=new Size[0];if(sizes.length>128)throw new VmHardware.Failure("size_limit","Android returned more than128 high-speed sizes.");return sizes;}
    static Range<Integer>[] ranges(CameraCharacteristics ch,Size size)throws Exception{if(!Arrays.asList(sizes(ch)).contains(size))throw new VmHardware.Failure("unsupported_format","Choose an exact advertised constrained high-speed size.");Range<Integer>[] ranges=HardwareCamera.streams(ch).getHighSpeedVideoFpsRangesFor(size);if(ranges.length>128)throw new VmHardware.Failure("size_limit","Android returned more than128 high-speed ranges.");return ranges;}
    static Object call(VmHardware.Context c,String op,JSONArray args)throws Exception{
        CameraCharacteristics ch=HardwareCamera.characteristics(c,VmHardware.text(args,0,128));JSONArray rows=new JSONArray();boolean size=op.equals("camera_high_speed_sizes");int offset=VmHardware.integer(args,size?1:3,0,128),limit=VmHardware.integer(args,size?2:4,1,16),total,end;
        if(size){Size[] sizes=sizes(ch);total=sizes.length;end=Math.min(total,offset+limit);for(int i=offset;i<end;i++)rows.put(VmHardware.object("width",sizes[i].getWidth(),"height",sizes[i].getHeight()));}
        else{Range<Integer>[] ranges=ranges(ch,new Size(VmHardware.integer(args,1,1,32768),VmHardware.integer(args,2,1,32768)));total=ranges.length;end=Math.min(total,offset+limit);for(int i=offset;i<end;i++)rows.put(VmHardware.object("min",ranges[i].getLower(),"max",ranges[i].getUpper()));}
        return HardwareCamera.page(size?"sizes":"ranges",rows,end,total).put("supported",supported(ch));
    }
    static final class Options {
        final JSONArray base;final int mode,captureFps,playbackFps,bitrate;final double rate;
        Options(JSONArray row,boolean audio)throws Exception{
            if(row.length()==3){CameraValues.list(row,3,3);if(!VmHardware.text(row,0,32).equals("time_lapse"))throw new VmHardware.Failure("invalid_argument","Unknown rate option record.");mode=1;base=CameraValues.list(row.get(1),7,9);rate=CameraValues.number(row.get(2));captureFps=playbackFps=bitrate=0;if(rate<0.001||rate>120)throw new VmHardware.Failure("invalid_argument","Time-lapse capture rate must be finite and0.001..120 FPS.");}
            else if(row.length()==5){if(!VmHardware.text(row,0,32).equals("high_speed"))throw new VmHardware.Failure("invalid_argument","Unknown rate option record.");mode=2;base=CameraValues.list(row.get(1),7,9);captureFps=VmHardware.integer(row,2,120,960);playbackFps=VmHardware.integer(row,3,1,captureFps);bitrate=VmHardware.integer(row,4,64000,50000000);rate=captureFps;}
            else{mode=0;base=CameraValues.list(row,7,9);captureFps=playbackFps=bitrate=0;rate=0;}
            if(audio&&(mode==1||mode==2&&captureFps!=playbackFps))throw new VmHardware.Failure("unsupported_combination","The SDK capture-rate mode ignores audio; use silent recording for time-lapse or slow motion.");
        }
        void validate(HardwareCamera.Camera camera,int width,int height,int fps,JSONArray settings)throws Exception{
            if(mode==1&&rate>=fps)throw new VmHardware.Failure("invalid_argument","Time-lapse capture FPS must be below the selected playback FPS.");
            if(mode==1){Range<Integer>[] normal=camera.ch.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES);int max=0;if(normal!=null)for(Range<Integer> range:normal)max=Math.max(max,range.getUpper());if(rate>max)throw new VmHardware.Failure("unsupported_profile","The camera does not advertise a normal source frame rate at least as high as the requested sample rate.");}
            if(mode==2){if(!supported(camera.ch))throw new VmHardware.Failure("unsupported","The actual camera does not advertise constrained high-speed capture.");Range<Integer> selected=new Range<>(captureFps,captureFps);if(!Arrays.asList(ranges(camera.ch,new Size(width,height))).contains(selected))throw new VmHardware.Failure("unsupported_profile","The exact fixed capture FPS/size is not advertised for constrained high speed.");checkSettings(settings);}
        }
        void checkSettings(JSONArray settings)throws Exception{
            if(mode!=2)return;for(int i=0;i<settings.length();i++){JSONArray r=CameraValues.list(settings.get(i),3,3);if(VmHardware.text(r,0,256).equals(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE.getName())){CameraValues.Setting value=CameraValues.decode(VmHardware.text(r,1,32),r.get(2));if(value.type!=Range.class||!new Range<>(captureFps,captureFps).equals(value.value))throw new VmHardware.Failure("invalid_argument","Request FPS conflicts with the selected fixed high-speed range.");}}
        }
        void apply(MediaRecorder recorder){if(mode==1||mode==2&&captureFps!=playbackFps)recorder.setCaptureRate(rate);if(mode==2){recorder.setVideoFrameRate(playbackFps);recorder.setVideoEncodingBitRate(bitrate);}}
        void request(CaptureRequest.Builder builder,int template,JSONArray settings)throws Exception{if(mode==2){if(template!=CameraDevice.TEMPLATE_RECORD)throw new VmHardware.Failure("unsupported_operation","Constrained recording accepts TEMPLATE_RECORD requests.");checkSettings(settings);builder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE,new Range<>(captureFps,captureFps));}}
        String name(){return mode==0?"regular":mode==1?"time_lapse":captureFps==playbackFps?"high_speed":"slow_motion";}
    }
    static int submit(CameraCaptureSession session,CaptureRequest request,boolean repeat,CameraCaptureSession.CaptureCallback callback,Handler handler)throws Exception{
        if(session instanceof CameraConstrainedHighSpeedCaptureSession){List<CaptureRequest> requests=((CameraConstrainedHighSpeedCaptureSession)session).createHighSpeedRequestList(request);if(requests.isEmpty()||requests.size()>128)throw new VmHardware.Failure("resource_limit","SDK high-speed batches require1..128 requests.");return repeat?session.setRepeatingBurst(requests,callback,handler):session.captureBurst(requests,callback,handler);}
        return repeat?session.setRepeatingRequest(request,callback,handler):session.capture(request,callback,handler);
    }
    static void configure(HardwareCamera.Camera camera,CameraDevice device,List<OutputConfiguration> outputs,CameraCaptureSession.StateCallback callback,int color,HardwareCameraVideo.Video video)throws Exception{
        if(outputs.size()!=1)throw new VmHardware.Failure("unsupported_combination","This recording session owns exactly one encoder surface.");
        if(Build.VERSION.SDK_INT>=28)Api28.configure(camera,device,outputs,callback,color,video);else{video.sessionType=1;device.createConstrainedHighSpeedCaptureSession(Collections.singletonList(video.surface()),callback,HardwareCamera.events());}
    }
    static final class Api28 {
        static void configure(HardwareCamera.Camera camera,CameraDevice device,List<OutputConfiguration> outputs,CameraCaptureSession.StateCallback callback,int color,HardwareCameraVideo.Video video)throws Exception{SessionConfiguration session=new SessionConfiguration(SessionConfiguration.SESSION_HIGH_SPEED,outputs,r->HardwareCamera.events().post(r),callback);if(color>=0)Api34.color(camera,session,color);video.sessionType=session.getSessionType();device.createCaptureSession(session);}
    }
    static final class Api34 {static void color(HardwareCamera.Camera camera,SessionConfiguration session,int color){session.setColorSpace(ColorSpace.Named.values()[color]);ColorSpace value=session.getColorSpace();synchronized(camera){camera.configurationColorSpace=value==null?-1:value.getId();}}}
}
