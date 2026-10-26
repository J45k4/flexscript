package org.flexscript.collie;

import android.hardware.camera2.*;
import android.hardware.camera2.params.*;
import android.os.Build;
import android.util.Size;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;

/** Public SDK getters are the oracle; constructed calibration is not HAL data. */
final class HardwareCameraMetadataChecks {
    final HardwareCameraChecks t;int combinations,streams,sizes,maps,intrinsics;final JSONArray actualKeys=new JSONArray();
    final StringBuilder batch=new StringBuilder();int pending,batches,queries;
    HardwareCameraMetadataChecks(HardwareCameraChecks t){this.t=t;}
    static String q(String s){return HardwareCameraChecks.q(s);}
    static JSONObject descriptor(String type)throws Exception{return new JSONObject().put("sdk_type",type).put("use","camera_value_path/camera_result_value_path");}
    static JSONObject scalar(Object value)throws Exception{return new JSONObject().put("value",value).put("array",false).put("total",value==JSONObject.NULL?0:1).put("next",-1);}
    static JSONArray path(Object... segments)throws Exception{return new JSONArray(Arrays.asList(segments));}
    static String setup(JSONArray path)throws Exception{String s="let path=db_list();";for(int i=0;i<path.length();i++){Object v=path.get(i);s+="db_add(path,"+(v instanceof String?"db_text("+q((String)v)+")":"db_int("+v+")")+");";}return s;}
    void actual(String id,String key,JSONArray path,int offset,int limit,JSONObject expected)throws Exception{
        StringBuilder code=new StringBuilder("{"+setup(path));t.wire("camera_value_path("+q(id)+","+q(key)+",path,"+offset+","+limit+")",expected,code,new int[]{0});code.append("}");
        if(batch.length()+code.length()>40000)flush();if(code.length()>60000)throw new IOException("A metadata oracle query exceeds its source bound");
        batch.append(code);pending++;if(pending==6)flush();
    }
    void flush()throws Exception{
        if(pending==0)return;t.vm("fn main(){"+batch+"return 0;}");queries+=pending;batches++;batch.setLength(0);pending=0;
        JSONObject progress=new JSONObject().put("vm_batches_completed",batches).put("vm_rpc_queries_completed",queries).put("sdk_enumerated_combinations",combinations).put("sdk_enumerated_streams",streams).put("sdk_enumerated_sizes",sizes);
        File temporary=new File(t.root,"camera-metadata-progress.tmp"),target=new File(t.root,"camera-metadata-progress.json");try(FileOutputStream file=new FileOutputStream(temporary)){file.write(progress.toString().getBytes(StandardCharsets.UTF_8));}if(!temporary.renameTo(target))throw new IOException("Cannot publish metadata progress");
    }
    void fixture(Object value,JSONArray path,int offset,int limit,JSONObject expected)throws Exception{t.metadataFixture(value,path,offset,limit,expected);}
    void rejects(Object value,JSONArray path)throws Exception{try{CameraValues.page(value,0,1,path);throw new AssertionError("Invalid metadata path accepted");}catch(VmHardware.Failure error){t.check(error.code.equals("invalid_argument"),"fixed metadata selectors reject malformed fields/indices without dispatching Java methods");}}
    void fixtures()throws Exception{
        float[] calibration={1200.5f,1199.25f,640.125f,359.875f,-0.0f};long timestamp=9007199254740993L;
        LensIntrinsicsSample sample=new LensIntrinsicsSample(timestamp,calibration);JSONArray expected=new JSONArray();for(float v:sample.getLensIntrinsics())expected.put(new JSONObject().put("$real",Double.doubleToRawLongBits((double)v)));
        Object encoded=new JSONObject().put("sdk_type","lens_intrinsics_sample").put("timestamp_ns",timestamp).put("intrinsics",expected);
        fixture(sample,path(),0,1,scalar(encoded));fixture(new LensIntrinsicsSample[]{sample},path(),0,1,HardwareCameraChecks.expectedPage(new JSONArray().put(encoded),1,1,null));fixture(new LensIntrinsicsSample[]{sample},path(0),0,1,scalar(encoded));
        t.check(true,"constructed public LensIntrinsicsSample objects retain timestamps above2^53, all five exact float-to-double values and negative zero through real VM scalar/array/path transport");intrinsics++;
        DeviceStateSensorOrientationMap map=new DeviceStateSensorOrientationMap.Builder().addOrientationForState(DeviceStateSensorOrientationMap.NORMAL,90).addOrientationForState(DeviceStateSensorOrientationMap.FOLDED,270).build();
        for(long state:new long[]{DeviceStateSensorOrientationMap.NORMAL,DeviceStateSensorOrientationMap.FOLDED})fixture(map,path(state),0,1,scalar(map.getSensorOrientation(state)));
        JSONArray rows=new JSONArray().put(new JSONObject().put("device_state",DeviceStateSensorOrientationMap.NORMAL).put("supported",true).put("orientation_degrees",90)).put(new JSONObject().put("device_state",DeviceStateSensorOrientationMap.FOLDED).put("supported",true).put("orientation_degrees",270));
        for(int i=0;i<=2;i++)fixture(map,path(),i,1,HardwareCameraChecks.expectedPage(i<2?new JSONArray().put(rows.get(i)):new JSONArray(),2,Math.min(i+1,2),"device_state_sensor_orientation_map").put("enumeration","documented_NORMAL_FOLDED_queries"));
        DeviceStateSensorOrientationMap partial=new DeviceStateSensorOrientationMap.Builder().addOrientationForState(DeviceStateSensorOrientationMap.NORMAL,180).build();
        fixture(partial,path(),1,1,HardwareCameraChecks.expectedPage(new JSONArray().put(new JSONObject().put("device_state",DeviceStateSensorOrientationMap.FOLDED).put("supported",false).put("orientation_degrees",JSONObject.NULL)),2,2,"device_state_sensor_orientation_map").put("enumeration","documented_NORMAL_FOLDED_queries"));
        t.check(true,"public orientation builders and independent getters agree with selected state queries, both documented state pages, absent folded state and exact EOF; this is not physical folding");
        MultiResolutionStreamInfo info=new MultiResolutionStreamInfo(4032,3024,"physical-fixture");Object stream=new JSONObject().put("sdk_type","multi_resolution_stream_info").put("width",4032).put("height",3024).put("physical_camera_id","physical-fixture");
        fixture(Arrays.asList(info,info),path(),1,1,HardwareCameraChecks.expectedPage(new JSONArray().put(stream),2,2,null));fixture(Arrays.asList(info),path(0),0,1,scalar(stream));
        fixture(Arrays.asList((Object)null),path(0),0,1,scalar(JSONObject.NULL));t.check(true,"constructed public multi-resolution stream info retains size/physical identity through bounded SDK lists and path selection; a selected null remains typed null");
        rejects(sample,path("getTimestampNanos"));rejects(map,path("java.lang.Runtime"));rejects(partial,path(DeviceStateSensorOrientationMap.FOLDED));rejects(new Object[]{sample},path(-1));rejects(new Object[]{sample},path(1));rejects(new Object[]{sample},path(0.0));rejects(new Object[]{sample},path(new JSONObject()));rejects(sample,path(0,0,0,0,0,0,0,0,0));
        ArrayList<Integer> large=new ArrayList<>();for(int i=0;i<1100;i++)large.add(i);JSONArray end=new JSONArray();for(int i=1088;i<1100;i++)end.put(i);fixture(large,path(),1088,32,HardwareCameraChecks.expectedPage(end,1100,1100,null));t.check(true,"a nested collection above the inline1024-element bound remains readable through bounded pages rather than truncation");
    }
    JSONObject stream(MandatoryStreamCombination.MandatoryStreamInformation s)throws Exception{return descriptor("mandatory_stream_information").put("format",s.getFormat()).put("input",s.isInput()).put("size_count",s.getAvailableSizes().size()).put("maximum_size",s.isMaximumSize()).put("ultra_high_resolution",s.isUltraHighResolution()).put("ten_bit_capable",s.is10BitCapable()).put("ten_bit_format",s.is10BitCapable()?s.get10BitFormat():JSONObject.NULL).put("stream_use_case",s.getStreamUseCase());}
    void combinations(String id,String key,MandatoryStreamCombination[] values)throws Exception{
        for(int i=0;i<values.length;i++){
            MandatoryStreamCombination c=values[i];List<MandatoryStreamCombination.MandatoryStreamInformation> records=c.getStreamsInformation();
            JSONObject expected=descriptor("mandatory_stream_combination").put("description",c.getDescription().toString()).put("reprocessable",c.isReprocessable()).put("stream_count",records.size());
            actual(id,key,path(i),0,1,scalar(expected));combinations++;
            for(int j=0;j<records.size();j++){
                MandatoryStreamCombination.MandatoryStreamInformation record=records.get(j);actual(id,key,path(i,"streams"),j,1,HardwareCameraChecks.expectedPage(new JSONArray().put(stream(record)),records.size(),j+1,null));streams++;
                List<Size> available=record.getAvailableSizes();for(int at=0;at<available.size();at+=32){JSONArray page=new JSONArray();int end=Math.min(at+32,available.size());for(int k=at;k<end;k++)page.put(new JSONArray().put(available.get(k).getWidth()).put(available.get(k).getHeight()));actual(id,key,path(i,"streams",j,"sizes"),at,32,HardwareCameraChecks.expectedPage(page,available.size(),end,null));sizes+=page.length();}
                actual(id,key,path(i,"streams",j,"sizes"),available.size(),1,HardwareCameraChecks.expectedPage(new JSONArray(),available.size(),available.size(),null));
            }
            actual(id,key,path(i,"streams"),records.size(),1,HardwareCameraChecks.expectedPage(new JSONArray(),records.size(),records.size(),null));
        }
        flush();t.check(true,"every SDK mandatory combination/stream/size for"+key+" matches actual logical-camera path pages, including descriptions, flags, guarded10-bit formats, use cases and every EOF");
    }
    void multi(String id,String key,MultiResolutionStreamConfigurationMap map)throws Exception{
        for(String direction:new String[]{"inputs","outputs"}){
            int[] formats=direction.equals("inputs")?map.getInputFormats():map.getOutputFormats();for(int at=0;at<formats.length;at+=32){JSONArray values=new JSONArray();int end=Math.min(at+32,formats.length);for(int i=at;i<end;i++)values.put(formats[i]);actual(id,key,path(direction),at,32,HardwareCameraChecks.expectedPage(values,formats.length,end,null));}actual(id,key,path(direction),formats.length,1,HardwareCameraChecks.expectedPage(new JSONArray(),formats.length,formats.length,null));
            for(int format:formats){Collection<MultiResolutionStreamInfo> original=direction.equals("inputs")?map.getInputInfo(format):map.getOutputInfo(format);ArrayList<MultiResolutionStreamInfo> infos=new ArrayList<>(original);infos.sort(Comparator.comparing(MultiResolutionStreamInfo::getPhysicalCameraId).thenComparingInt(MultiResolutionStreamInfo::getWidth).thenComparingInt(MultiResolutionStreamInfo::getHeight));
                for(int at=0;at<infos.size();at+=32){JSONArray rows=new JSONArray();int end=Math.min(at+32,infos.size());for(int i=at;i<end;i++){MultiResolutionStreamInfo info=infos.get(i);rows.put(new JSONObject().put("sdk_type","multi_resolution_stream_info").put("width",info.getWidth()).put("height",info.getHeight()).put("physical_camera_id",info.getPhysicalCameraId()));}actual(id,key,path(direction,format),at,32,HardwareCameraChecks.expectedPage(rows,infos.size(),end,null));}
                actual(id,key,path(direction,format),infos.size(),1,HardwareCameraChecks.expectedPage(new JSONArray(),infos.size(),infos.size(),null));
            }
        }flush();maps++;t.check(true,"actual multi-resolution SDK input/output formats and complete stream groups match bounded VM path pages");
    }
    void run(CameraCharacteristics ch,String id)throws Exception{
        fixtures();
        for(CameraCharacteristics.Key<?> key:ch.getKeys()){
            Object value=ch.get(key);
            if(value instanceof MandatoryStreamCombination[]){actualKeys.put(key.getName());combinations(id,key.getName(),(MandatoryStreamCombination[])value);}
            if(value instanceof MultiResolutionStreamConfigurationMap){actualKeys.put(key.getName());multi(id,key.getName(),(MultiResolutionStreamConfigurationMap)value);}
            if(value instanceof DeviceStateSensorOrientationMap){DeviceStateSensorOrientationMap map=(DeviceStateSensorOrientationMap)value;for(long state:new long[]{DeviceStateSensorOrientationMap.NORMAL,DeviceStateSensorOrientationMap.FOLDED})try{actual(id,key.getName(),path(state),0,1,scalar(map.getSensorOrientation(state)));}catch(IllegalArgumentException absent){}actualKeys.put(key.getName());}
        }
        flush();t.check(combinations>0&&streams>0&&sizes>0,"the selected actual emulator camera supplies mandatory combinations and nonempty SDK stream-size lists; constructed values cannot satisfy this positive gate");
        t.vm("fn main(){let p=db_list();db_add(p,db_text(\"getClass\"));if camera_value_path("+q(id)+",\"android.sensor.info.exposureTimeRange\",p,0,1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}if !camera_info("+q(id)+"){return 3;}return 0;}");
        t.check(true,"actual metadata dispatch rejects unsupported method-like path fields without invalidating ordinary camera inventory");
        t.outputProfiles.put("structured_metadata",new JSONObject().put("actual_keys",actualKeys).put("sdk_mandatory_combinations",combinations).put("sdk_streams",streams).put("sdk_sizes",sizes).put("sdk_multi_resolution_maps",maps).put("constructed_lens_intrinsics",intrinsics).put("vm_batches_completed",batches).put("vm_rpc_queries_completed",queries).put("physical_intrinsics_verified",false).put("physical_fold_orientation_verified",false));
    }
}
