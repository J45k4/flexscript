package org.flexscript.collie;

import android.graphics.ColorSpace;
import android.graphics.ImageFormat;
import android.hardware.camera2.*;
import android.hardware.camera2.params.*;
import android.media.Image;
import android.os.Build;
import android.util.Size;
import java.util.*;
import org.json.*;

/** Explicit Camera2 output/session parameters and actual SDK configuration getters. */
final class HardwareCameraOutput {
    static final class Spec {
        final int format,width,height;final String physical;final long profile,useCase;final CameraCharacteristics source;
        Spec(CameraManager manager,CameraCharacteristics logical,Object value)throws Exception{
            JSONArray row=CameraValues.list(value,3,6);
            if(row.length()==5)throw new VmHardware.Failure("invalid_argument","Camera outputs have3/4 legacy fields or6 profile fields.");
            format=VmHardware.integer(row,0,1,Integer.MAX_VALUE);width=VmHardware.integer(row,1,1,32768);height=VmHardware.integer(row,2,1,32768);
            physical=row.length()>=4?VmHardware.text(row,3,128):"";profile=row.length()==6?VmHardware.longInteger(row,4,0,Long.MAX_VALUE):0;useCase=row.length()==6?VmHardware.longInteger(row,5,0,Long.MAX_VALUE):0;
            if(format==ImageFormat.PRIVATE)throw new VmHardware.Failure("unsupported_format","PRIVATE images do not expose CPU-readable planes; use a recorder surface.");
            CameraCharacteristics selected=logical;
            if(!physical.isEmpty()){
                if(Build.VERSION.SDK_INT<28||!logical.getPhysicalCameraIds().contains(physical))throw new VmHardware.Failure("invalid_argument","Choose a physical camera ID belonging to this logical camera.");
                selected=manager.getCameraCharacteristics(physical);
            }
            source=selected;StreamConfigurationMap map=source.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);Size[] sizes=map==null?null:map.getOutputSizes(format);
            if(sizes==null||!Arrays.asList(sizes).contains(new Size(width,height)))throw new VmHardware.Failure("unsupported_format","The SDK does not advertise that exact format/size; no resolution is silently substituted.");
            int bits=ImageFormat.getBitsPerPixel(format);
            if(bits>0&&((long)width*height*bits+7)/8>HardwareCamera.MAX_FRAME_BYTES)throw new VmHardware.Failure("resource_limit","That uncompressed output exceeds the128MiB image byte budget before allocation.");
            if((profile!=0||useCase!=0)&&Build.VERSION.SDK_INT<33)throw new VmHardware.Failure("unsupported_operation","Explicit output profiles/use cases require Android13+.");
            if(Build.VERSION.SDK_INT>=33)Api33.validate(this);
        }
        long actualProfile(){return profile==0?1:profile;}
        void apply(OutputConfiguration output){if(Build.VERSION.SDK_INT>=33)Api33.apply(this,output);}
    }
    static int color(JSONArray arguments,int index)throws Exception{
        int value=arguments.length()>index?VmHardware.integer(arguments,index,-1,ColorSpace.Named.values().length-1):-1;
        if(value>=0&&Build.VERSION.SDK_INT<34)throw new VmHardware.Failure("unsupported_operation","Explicit camera color space requires Android14+.");return value;
    }
    static void validateColor(List<Spec> specs,int color)throws Exception{
        if(color< -1||color>=ColorSpace.Named.values().length)throw new VmHardware.Failure("invalid_argument","Choose a public SDK color-space ID or-1 for default.");
        if(color>=0){if(Build.VERSION.SDK_INT<34)throw new VmHardware.Failure("unsupported_operation","Explicit camera color space requires Android14+.");Api34.validate(specs,color);}
    }
    static void validateTargets(Collection<HardwareCamera.Reader> readers,boolean recording)throws Exception{
        if(Build.VERSION.SDK_INT>=33)Api33.targets(readers,recording);
    }
    static Object profile(OutputConfiguration output){return Build.VERSION.SDK_INT>=33?Api33.profile(output):JSONObject.NULL;}
    static Object useCase(OutputConfiguration output){return Build.VERSION.SDK_INT>=33?Api33.useCase(output):JSONObject.NULL;}
    static Object dataSpace(Image image){return Build.VERSION.SDK_INT>=33?Api33.dataSpace(image):JSONObject.NULL;}
    static void configure(HardwareCamera.Camera camera,CameraDevice device,List<OutputConfiguration> outputs,CameraCaptureSession.StateCallback callback,int color)throws Exception{
        if(Build.VERSION.SDK_INT<34)throw new VmHardware.Failure("unsupported_operation","Explicit camera color space requires Android14+.");
        Api34.configure(camera,device,outputs,callback,color);
    }
    static final class Api33 {
        static void validate(Spec s)throws Exception{
            DynamicRangeProfiles profiles=s.source.get(CameraCharacteristics.REQUEST_AVAILABLE_DYNAMIC_RANGE_PROFILES);
            // STANDARD is the documented SDK default even when the optional
            // ten-bit capability map is absent. No HDR support is inferred.
            if(s.profile!=0&&s.profile!=DynamicRangeProfiles.STANDARD&&(profiles==null||!profiles.getSupportedProfiles().contains(s.profile)))throw new VmHardware.Failure("unsupported_profile","The camera does not advertise that dynamic-range profile.");
            if(s.useCase!=0){long[] cases=s.source.get(CameraCharacteristics.SCALER_AVAILABLE_STREAM_USE_CASES);boolean found=false;if(cases!=null)for(long value:cases)if(value==s.useCase)found=true;if(!found)throw new VmHardware.Failure("unsupported_profile","The camera does not advertise that stream use case.");}
        }
        static void apply(Spec s,OutputConfiguration output){if(s.profile!=0)output.setDynamicRangeProfile(s.profile);if(s.useCase!=0)output.setStreamUseCase(s.useCase);}
        static void constraints(DynamicRangeProfiles profiles,long own,Collection<Long> targets)throws Exception{
            if(profiles==null)return;Set<Long> allowed=profiles.getProfileCaptureRequestConstraints(own);
            if(allowed.isEmpty())return;
            for(long profile:targets)if(profile!=own&&!allowed.contains(profile))throw new VmHardware.Failure("unsupported_combination","Selected capture targets violate the actual SDK dynamic-range constraints.");
        }
        static void targets(Collection<HardwareCamera.Reader> readers,boolean recording)throws Exception{
            ArrayList<Long> targets=new ArrayList<>();for(HardwareCamera.Reader reader:readers)targets.add(reader.options.actualProfile());if(recording)targets.add(DynamicRangeProfiles.STANDARD);
            for(HardwareCamera.Reader reader:readers){Spec spec=reader.options;constraints(spec.source.get(CameraCharacteristics.REQUEST_AVAILABLE_DYNAMIC_RANGE_PROFILES),spec.actualProfile(),targets);}
        }
        static long profile(OutputConfiguration output){return output.getDynamicRangeProfile();}
        static long useCase(OutputConfiguration output){return output.getStreamUseCase();}
        static int dataSpace(Image image){return image.getDataSpace();}
    }
    static final class Api34 {
        static void validate(List<Spec> specs,int color)throws Exception{
            ColorSpace.Named named=ColorSpace.Named.values()[color];
            for(Spec spec:specs){ColorSpaceProfiles profiles=spec.source.get(CameraCharacteristics.REQUEST_AVAILABLE_COLOR_SPACE_PROFILES);
                if(profiles==null||!profiles.getSupportedColorSpaces(spec.format).contains(named)||!profiles.getSupportedDynamicRangeProfiles(named,spec.format).contains(spec.actualProfile()))throw new VmHardware.Failure("unsupported_profile","The camera does not advertise that color-space/format/dynamic-range combination.");}
        }
        static SessionConfiguration session(List<OutputConfiguration> outputs,CameraCaptureSession.StateCallback callback,int color){
            SessionConfiguration session=new SessionConfiguration(SessionConfiguration.SESSION_REGULAR,outputs,command->HardwareCamera.events().post(command),callback);
            session.setColorSpace(ColorSpace.Named.values()[color]);return session;
        }
        static void configure(HardwareCamera.Camera camera,CameraDevice device,List<OutputConfiguration> outputs,CameraCaptureSession.StateCallback callback,int color)throws Exception{
            SessionConfiguration selected=session(outputs,callback,color);ColorSpace value=selected.getColorSpace();
            synchronized(camera){camera.configurationColorSpace=value==null?-1:value.getId();}
            device.createCaptureSession(selected);
        }
    }
}
