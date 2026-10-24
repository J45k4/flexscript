package org.flexscript.collie;

import android.graphics.ColorSpace;
import android.hardware.camera2.params.Capability;
import android.hardware.camera2.params.ColorSpaceProfiles;
import android.hardware.camera2.params.DynamicRangeProfiles;
import android.os.Build;
import java.util.*;
import org.json.*;

/** Explicit public SDK profile values. No reflective calls or inferred support. */
final class CameraProfileValues {
    static <T extends Comparable<? super T>> List<T> sorted(Set<T> values,int maximum)throws Exception{
        if(values==null)throw new VmHardware.Failure("invalid_response","Camera SDK returned a null profile set.");
        if(values.size()>maximum)throw new VmHardware.Failure("size_limit","Camera profile set exceeds its bounded size.");
        ArrayList<T> out=new ArrayList<>(values);Collections.sort(out);return out;
    }
    static JSONObject descriptor(String type)throws Exception{return VmHardware.object("sdk_type",type,"use","paged camera_value/camera_result_value");}
    static Object encode(Object value,int depth)throws Exception{
        if(Build.VERSION.SDK_INT>=30&&Api30.matches(value))return Api30.encode(value,depth);
        if(Build.VERSION.SDK_INT>=33&&Api33.matches(value))return descriptor("dynamic_range_profiles");
        if(Build.VERSION.SDK_INT>=34&&Api34.matches(value))return descriptor("color_space_profiles");
        return null;
    }
    static JSONObject page(Object value,int offset,int limit)throws Exception{
        if(Build.VERSION.SDK_INT>=33&&Api33.matches(value))return Api33.page(value,offset,limit);
        if(Build.VERSION.SDK_INT>=34&&Api34.matches(value))return Api34.page(value,offset,limit);
        return null;
    }
    static JSONObject result(String type,JSONArray rows,int total,int end)throws Exception{
        return VmHardware.object("sdk_type",type,"value",rows,"array",true,"total",total,"next",end<total?end:-1);
    }
    static final class Api30 {
        static boolean matches(Object value){return value instanceof Capability;}
        static Object encode(Object value,int depth)throws Exception{
            Capability c=(Capability)value;
            return VmHardware.object("sdk_type","capability","mode",c.getMode(),"maximum_streaming_size",CameraValues.encode(c.getMaxStreamingSize(),depth+1),"zoom_ratio_range",CameraValues.encode(c.getZoomRatioRange(),depth+1));
        }
    }
    static final class Api33 {
        static boolean matches(Object value){return value instanceof DynamicRangeProfiles;}
        static JSONObject page(Object value,int offset,int limit)throws Exception{
            DynamicRangeProfiles profiles=(DynamicRangeProfiles)value;
            List<Long> supported=sorted(profiles.getSupportedProfiles(),64);int end=Math.min(supported.size(),offset+limit);JSONArray rows=new JSONArray();
            for(int i=offset;i<end;i++){
                long profile=supported.get(i);
                rows.put(VmHardware.object("profile",profile,"capture_request_constraints",new JSONArray(sorted(profiles.getProfileCaptureRequestConstraints(profile),64)),"extra_latency",profiles.isExtraLatencyPresent(profile)));
            }
            return result("dynamic_range_profiles",rows,supported.size(),end);
        }
    }
    static final class Api34 {
        static boolean matches(Object value){return value instanceof ColorSpaceProfiles;}
        static final class Entry {
            final ColorSpace.Named color;final int format;
            Entry(ColorSpace.Named color,int format){this.color=color;this.format=format;}
        }
        static JSONObject page(Object value,int offset,int limit)throws Exception{
            ColorSpaceProfiles profiles=(ColorSpaceProfiles)value;
            List<ColorSpace.Named> colors=sorted(profiles.getSupportedColorSpaces(ColorSpaceProfiles.UNSPECIFIED),64);
            ArrayList<Entry> entries=new ArrayList<>();
            for(ColorSpace.Named color:colors){
                List<Integer> formats=sorted(profiles.getSupportedImageFormatsForColorSpace(color),256);
                if(entries.size()+formats.size()>4096)throw new VmHardware.Failure("size_limit","Camera color-space map exceeds4096 format entries.");
                for(int format:formats)entries.add(new Entry(color,format));
            }
            int end=Math.min(entries.size(),offset+limit);JSONArray rows=new JSONArray();
            for(int i=offset;i<end;i++){
                Entry entry=entries.get(i);
                rows.put(VmHardware.object("color_space_id",entry.color.ordinal(),"color_space",entry.color.name(),"image_format",entry.format,"dynamic_ranges",new JSONArray(sorted(profiles.getSupportedDynamicRangeProfiles(entry.color,entry.format),64))));
            }
            return result("color_space_profiles",rows,entries.size(),end);
        }
    }
}
