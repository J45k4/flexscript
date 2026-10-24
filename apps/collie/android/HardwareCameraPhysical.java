package org.flexscript.collie;

import android.hardware.camera2.*;
import android.os.Build;
import java.util.*;
import org.json.*;

/** Public logical/physical Camera2 metadata; every result belongs to its parent handle. */
final class HardwareCameraPhysical {
    static boolean inventory(String op){return op.equals("camera_physical_info")||op.equals("camera_physical_keys")||op.equals("camera_physical_value")||op.equals("camera_physical_formats")||op.equals("camera_physical_output_sizes");}
    static boolean resultOperation(String op){return op.equals("camera_result_physical")||op.equals("camera_physical_result_keys")||op.equals("camera_physical_result_value");}
    static void requireApi()throws Exception{if(Build.VERSION.SDK_INT<28)throw new VmHardware.Failure("unsupported_operation","Physical camera metadata and controls require Android9+.");}
    static Object inventory(VmHardware.Context c,String op,JSONArray a)throws Exception{
        requireApi();String logical=VmHardware.text(a,0,128),id=VmHardware.text(a,1,128);
        CameraCharacteristics parent=HardwareCamera.characteristics(c,logical);
        if(id.isEmpty()||!parent.getPhysicalCameraIds().contains(id))throw new VmHardware.Failure("invalid_argument","Choose a physical camera ID advertised by this logical camera.");
        CameraCharacteristics ch=HardwareCamera.manager(c).getCameraCharacteristics(id);
        if(op.equals("camera_physical_info"))return HardwareCamera.info(c,id,ch).put("logical_camera",logical);
        if(op.equals("camera_physical_keys"))return HardwareCamera.keys(ch,VmHardware.integer(a,2,0,10000),VmHardware.integer(a,3,1,32));
        if(op.equals("camera_physical_value"))return HardwareCamera.value(ch,VmHardware.text(a,2,256),VmHardware.integer(a,3,0,1000000),VmHardware.integer(a,4,1,32));
        if(op.equals("camera_physical_formats"))return HardwareCamera.formats(ch,VmHardware.integer(a,2,0,10000),VmHardware.integer(a,3,1,32));
        return HardwareCamera.sizes(ch,VmHardware.integer(a,2,0,Integer.MAX_VALUE),VmHardware.integer(a,3,0,10000),VmHardware.integer(a,4,1,16));
    }
    static final class Setting {
        final String camera,name;final CameraValues.Setting value;
        Setting(String camera,String name,CameraValues.Setting value){this.camera=camera;this.name=name;this.value=value;}
    }
    static List<Setting> settings(CameraCharacteristics ch,Set<String> targets,boolean logicalTarget,JSONArray rows)throws Exception{
        ArrayList<Setting> parsed=new ArrayList<>();HashSet<String> allowed=new HashSet<>(),physicalKeys=new HashSet<>(),seen=new HashSet<>();
        for(CaptureRequest.Key<?> key:ch.getAvailableCaptureRequestKeys())allowed.add(key.getName());
        boolean loaded=false;
        for(int i=0;i<rows.length();i++){
            JSONArray row=CameraValues.list(rows.get(i),3,4);String name=VmHardware.text(row,0,256),type=VmHardware.text(row,1,32),physical="";
            if(row.length()==4){
                requireApi();physical=VmHardware.text(row,3,128);
                if(physical.isEmpty()||!ch.getPhysicalCameraIds().contains(physical)||!targets.contains(physical))throw new VmHardware.Failure("invalid_argument","A physical override must select an advertised physical camera with a configured output target.");
                if(logicalTarget)throw new VmHardware.Failure("invalid_argument","Physical overrides require physical-only outputs; Android leaves mixed logical stream results undefined.");
                if(!loaded){List<CaptureRequest.Key<?>> keys=ch.getAvailablePhysicalCameraRequestKeys();if(keys!=null)for(CaptureRequest.Key<?> key:keys)physicalKeys.add(key.getName());loaded=true;}
                if(!physicalKeys.contains(name))throw new VmHardware.Failure("unsupported_key","That key is not advertised for physical-camera overrides: "+name);
                if(!seen.add(physical+'\0'+name))throw new VmHardware.Failure("invalid_argument","A physical camera/key pair may occur only once in a request.");
            }else if(!allowed.contains(name))throw new VmHardware.Failure("unsupported_key","That request key is not advertised by this camera: "+name);
            parsed.add(new Setting(physical,name,CameraValues.decode(type,row.get(2))));
        }
        return parsed;
    }
    @SuppressWarnings({"unchecked","rawtypes"})
    static void apply(CaptureRequest.Builder builder,List<Setting> settings){
        // Global settings first so physical overrides do not depend on row order.
        for(Setting s:settings)if(s.camera.isEmpty())builder.set(new CaptureRequest.Key(s.name,s.value.type),s.value.value);
        for(Setting s:settings)if(!s.camera.isEmpty())builder.setPhysicalCameraKey(new CaptureRequest.Key(s.name,s.value.type),s.value.value,s.camera);
    }
    static Map<String,CaptureResult> results(TotalCaptureResult parent)throws Exception{
        requireApi();Map<String,? extends CaptureResult> actual=Build.VERSION.SDK_INT>=31?Api31.results(parent):parent.getPhysicalCameraResults();
        if(actual==null||actual.size()>128)throw new VmHardware.Failure("invalid_response","Invalid or oversized SDK physical result map.");
        TreeMap<String,CaptureResult> rows=new TreeMap<>();
        for(Map.Entry<String,? extends CaptureResult> row:actual.entrySet()){
            String id=row.getKey();if(id==null||id.isEmpty()||id.length()>128||id.indexOf('\0')>=0||row.getValue()==null)throw new VmHardware.Failure("invalid_response","Invalid SDK physical result record.");
            rows.put(id,row.getValue());
        }
        return rows;
    }
    static Object result(HardwareCamera.Camera camera,String op,JSONArray a)throws Exception{
        String token=VmHardware.text(a,1,128);TotalCaptureResult parent;
        synchronized(camera){parent=camera.results.get(token);}
        if(parent==null)throw new VmHardware.Failure("stale_result","Unknown or evicted actual SDK capture result.");
        Map<String,CaptureResult> records=results(parent);
        if(op.equals("camera_result_physical")){
            int offset=VmHardware.integer(a,2,0,128),limit=VmHardware.integer(a,3,1,16),end=Math.min(records.size(),offset+limit);JSONArray rows=new JSONArray();
            List<String> ids=new ArrayList<>(records.keySet());
            for(int i=offset;i<end;i++){String id=ids.get(i);CaptureResult r=records.get(id);rows.put(VmHardware.object("id",id,"frame_number",r.getFrameNumber(),"sequence_id",r.getSequenceId(),"total_result",r instanceof TotalCaptureResult));}
            return HardwareCamera.page("cameras",rows,end,records.size()).put("total_results_api",Build.VERSION.SDK_INT>=31);
        }
        String id=VmHardware.text(a,2,128);CaptureResult selected=records.get(id);
        if(selected==null)throw new VmHardware.Failure("unavailable","This retained SDK result contains no metadata for that physical camera.");
        if(op.equals("camera_physical_result_keys"))return HardwareCamera.keys(selected,VmHardware.integer(a,3,0,10000),VmHardware.integer(a,4,1,32));
        return HardwareCamera.value(selected,VmHardware.text(a,3,256),VmHardware.integer(a,4,0,1000000),VmHardware.integer(a,5,1,32));
    }
    private static final class Api31 {
        static Map<String,TotalCaptureResult> results(TotalCaptureResult result){return result.getPhysicalCameraTotalResults();}
    }
}
