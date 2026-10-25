package org.flexscript.collie;

import android.hardware.camera2.params.*;
import android.os.Build;
import android.util.Size;
import java.util.*;
import org.json.*;

/** Explicit SDK metadata selection, never reflection or arbitrary host methods. */
final class CameraStructuredValues {
    private static final Object NONE=new Object();
    static JSONObject descriptor(String type)throws Exception{return VmHardware.object("sdk_type",type,"use","camera_value_path/camera_result_value_path");}
    static int bounded(int count)throws Exception{if(count<0||count>4096)throw new VmHardware.Failure("size_limit","Camera metadata collection exceeds4096 entries.");return count;}
    static Object encode(Object value,int depth)throws Exception{
        if(Build.VERSION.SDK_INT>=29&&Api29.matches(value))return Api29.encode(value,depth);
        if(Build.VERSION.SDK_INT>=31&&Api31.matches(value))return Api31.encode(value,depth);
        if(Build.VERSION.SDK_INT>=32&&Api32.matches(value))return descriptor("device_state_sensor_orientation_map");
        if(Build.VERSION.SDK_INT>=35&&Api35.matches(value))return Api35.encode(value,depth);
        return null;
    }
    static Object select(Object value,JSONArray path)throws Exception{
        if(path==null)return value;if(path.length()>8)throw new VmHardware.Failure("invalid_argument","Camera metadata paths have at most8 segments.");
        for(int i=0;i<path.length();i++){
            Object segment=path.get(i);boolean number=segment instanceof Integer||segment instanceof Long;
            if(!number&&!(segment instanceof String))throw new VmHardware.Failure("invalid_argument","Camera metadata path segments are integers or fixed field names.");
            if(segment instanceof String)VmHardware.text(path,i,32);
            Object next=NONE;
            if(Build.VERSION.SDK_INT>=29&&Api29.matches(value))next=Api29.select(value,segment);
            else if(Build.VERSION.SDK_INT>=31&&Api31.matches(value))next=Api31.select(value,segment);
            else if(Build.VERSION.SDK_INT>=32&&Api32.matches(value))next=Api32.select(value,segment);
            else if(number){int n=CameraValues.length(value);long index=CameraValues.integer(segment,0,Integer.MAX_VALUE);if(n<0||index>=n)throw new VmHardware.Failure("invalid_argument","Camera metadata index is outside the selected collection.");next=CameraValues.at(value,(int)index);}
            if(next==NONE)throw new VmHardware.Failure("invalid_argument","That field or index is not supported by the selected camera metadata type.");value=next;
        }
        return value;
    }
    static JSONObject page(Object value,int offset,int limit)throws Exception{
        if(Build.VERSION.SDK_INT>=31&&value instanceof Api31.Formats)return CameraValues.page(((Api31.Formats)value).values(),offset,limit);
        if(Build.VERSION.SDK_INT>=32&&Api32.matches(value))return Api32.page(value,offset,limit);
        return null;
    }
    static final class Api29 {
        static boolean matches(Object value){return value instanceof MandatoryStreamCombination||value instanceof MandatoryStreamCombination.MandatoryStreamInformation;}
        static Object encode(Object value,int depth)throws Exception{
            if(value instanceof MandatoryStreamCombination){MandatoryStreamCombination c=(MandatoryStreamCombination)value;return descriptor("mandatory_stream_combination").put("description",CameraValues.encode(c.getDescription().toString(),depth+1)).put("reprocessable",c.isReprocessable()).put("stream_count",bounded(c.getStreamsInformation().size()));}
            MandatoryStreamCombination.MandatoryStreamInformation s=(MandatoryStreamCombination.MandatoryStreamInformation)value;
            JSONObject out=descriptor("mandatory_stream_information").put("format",s.getFormat()).put("input",s.isInput()).put("size_count",bounded(s.getAvailableSizes().size()));
            if(Build.VERSION.SDK_INT>=31)Api31.stream(out,s);
            else out.put("maximum_size",JSONObject.NULL).put("ultra_high_resolution",JSONObject.NULL);
            if(Build.VERSION.SDK_INT>=33)Api33.stream(out,s);
            else out.put("ten_bit_capable",JSONObject.NULL).put("ten_bit_format",JSONObject.NULL).put("stream_use_case",JSONObject.NULL);
            return out;
        }
        static Object select(Object value,Object segment)throws Exception{
            if(value instanceof MandatoryStreamCombination&&"streams".equals(segment)){List<?> values=((MandatoryStreamCombination)value).getStreamsInformation();bounded(values.size());return values;}
            if(value instanceof MandatoryStreamCombination.MandatoryStreamInformation&&"sizes".equals(segment)){List<Size> values=((MandatoryStreamCombination.MandatoryStreamInformation)value).getAvailableSizes();bounded(values.size());return values;}
            return NONE;
        }
    }
    static final class Api31 {
        static final class Formats {
            final MultiResolutionStreamConfigurationMap map;final boolean input;
            Formats(MultiResolutionStreamConfigurationMap map,boolean input){this.map=map;this.input=input;}
            int[] values()throws Exception{int[] values=input?map.getInputFormats():map.getOutputFormats();bounded(values.length);return values;}
        }
        static boolean matches(Object value){return value instanceof MultiResolutionStreamConfigurationMap||value instanceof MultiResolutionStreamInfo||value instanceof Formats;}
        static void stream(JSONObject out,MandatoryStreamCombination.MandatoryStreamInformation s)throws Exception{out.put("maximum_size",s.isMaximumSize()).put("ultra_high_resolution",s.isUltraHighResolution());}
        static Object encode(Object value,int depth)throws Exception{
            if(value instanceof MultiResolutionStreamInfo){MultiResolutionStreamInfo info=(MultiResolutionStreamInfo)value;return VmHardware.object("sdk_type","multi_resolution_stream_info","width",info.getWidth(),"height",info.getHeight(),"physical_camera_id",CameraValues.encode(info.getPhysicalCameraId(),depth+1));}
            if(value instanceof Formats){Formats formats=(Formats)value;return descriptor(formats.input?"multi_resolution_input_formats":"multi_resolution_output_formats").put("total",formats.values().length);}
            MultiResolutionStreamConfigurationMap map=(MultiResolutionStreamConfigurationMap)value;
            return descriptor("multi_resolution_stream_configuration_map").put("input_format_count",new Formats(map,true).values().length).put("output_format_count",new Formats(map,false).values().length);
        }
        static Object select(Object value,Object segment)throws Exception{
            if(value instanceof MultiResolutionStreamConfigurationMap){if("inputs".equals(segment))return new Formats((MultiResolutionStreamConfigurationMap)value,true);if("outputs".equals(segment))return new Formats((MultiResolutionStreamConfigurationMap)value,false);return NONE;}
            if(value instanceof Formats&&(segment instanceof Integer||segment instanceof Long)){
                Formats formats=(Formats)value;int format=(int)CameraValues.integer(segment,0,Integer.MAX_VALUE);boolean found=false;for(int supported:formats.values())if(supported==format)found=true;
                if(!found)throw new VmHardware.Failure("invalid_argument","Choose a format advertised by the selected multi-resolution direction.");
                Collection<MultiResolutionStreamInfo> actual=formats.input?formats.map.getInputInfo(format):formats.map.getOutputInfo(format);bounded(actual.size());ArrayList<MultiResolutionStreamInfo> rows=new ArrayList<>(actual);
                rows.sort(Comparator.comparing(MultiResolutionStreamInfo::getPhysicalCameraId).thenComparingInt(MultiResolutionStreamInfo::getWidth).thenComparingInt(MultiResolutionStreamInfo::getHeight));return rows;
            }
            return NONE;
        }
    }
    static final class Api32 {
        static boolean matches(Object value){return value instanceof DeviceStateSensorOrientationMap;}
        static Object select(Object value,Object segment)throws Exception{if(!(segment instanceof Integer||segment instanceof Long))return NONE;long state=CameraValues.integer(segment,Long.MIN_VALUE,Long.MAX_VALUE);try{return ((DeviceStateSensorOrientationMap)value).getSensorOrientation(state);}catch(IllegalArgumentException error){throw new VmHardware.Failure("invalid_argument","The SDK orientation map has no entry for that device state.");}}
        static JSONObject page(Object value,int offset,int limit)throws Exception{
            DeviceStateSensorOrientationMap map=(DeviceStateSensorOrientationMap)value;long[] states={DeviceStateSensorOrientationMap.NORMAL,DeviceStateSensorOrientationMap.FOLDED};int end=Math.min(2,offset+limit);JSONArray rows=new JSONArray();
            for(int i=offset;i<end;i++){Object angle=JSONObject.NULL;try{angle=map.getSensorOrientation(states[i]);}catch(IllegalArgumentException absent){}rows.put(VmHardware.object("device_state",states[i],"supported",angle!=JSONObject.NULL,"orientation_degrees",angle));}
            return VmHardware.object("sdk_type","device_state_sensor_orientation_map","value",rows,"array",true,"total",2,"next",end<2?end:-1,"enumeration","documented_NORMAL_FOLDED_queries");
        }
    }
    static final class Api33 {
        static void stream(JSONObject out,MandatoryStreamCombination.MandatoryStreamInformation s)throws Exception{boolean ten=s.is10BitCapable();out.put("ten_bit_capable",ten).put("ten_bit_format",ten?s.get10BitFormat():JSONObject.NULL).put("stream_use_case",s.getStreamUseCase());}
    }
    static final class Api35 {
        static boolean matches(Object value){return value instanceof LensIntrinsicsSample;}
        static Object encode(Object value,int depth)throws Exception{LensIntrinsicsSample sample=(LensIntrinsicsSample)value;float[] intrinsics=sample.getLensIntrinsics();if(intrinsics.length!=5)throw new VmHardware.Failure("invalid_response","SDK lens-intrinsics samples must contain5 calibration values.");return VmHardware.object("sdk_type","lens_intrinsics_sample","timestamp_ns",sample.getTimestampNanos(),"intrinsics",CameraValues.encode(intrinsics,depth+1));}
    }
}
