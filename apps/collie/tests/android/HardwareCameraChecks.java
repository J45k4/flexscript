package org.flexscript.collie;

import android.content.*;
import android.graphics.*;
import android.hardware.camera2.*;
import android.media.*;
import android.os.*;
import android.util.Size;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import java.util.zip.Adler32;
import org.json.*;

/** Independent SDK/decoder checks. No successful camera callbacks are fabricated. */
public final class HardwareCameraChecks {
    final MainActivity host;final File root;final VmHardware.Context context;final JSONArray checks=new JSONArray();final JSONObject outputProfiles=new JSONObject();int sequence;
    HardwareCameraChecks(MainActivity host,File root){this.host=host;this.root=root;context=new VmHardware.Context(host,root);}
    public static JSONObject run(MainActivity host,File root)throws Exception{return new HardwareCameraChecks(host,root).run();}
    public static JSONObject runVideo(MainActivity host,File root)throws Exception{return new HardwareCameraChecks(host,root).video();}
    public static JSONObject runYuv(MainActivity host,File root)throws Exception{return new HardwareCameraChecks(host,root).yuv();}
    public static JSONObject runPhysical(MainActivity host,File root)throws Exception{return new HardwareCameraChecks(host,root).physical();}
    public static JSONObject runLifecycle(MainActivity host,File root)throws Exception{return new HardwareCameraChecks(host,root).lifecycle();}
    public static JSONObject runManual(MainActivity host,File root)throws Exception{HardwareCameraChecks t=new HardwareCameraChecks(host,root);t.ui(()->host.uiEffect(new JSONObjectHolder().value));return new JSONObject().put("ok",true).put("manual_action_requested",true);}
    static final class JSONObjectHolder {final JSONObject value;JSONObjectHolder(){try{value=new JSONObject().put("kind","camera");}catch(JSONException e){throw new RuntimeException(e);}}}
    void check(boolean ok,String label)throws Exception{if(!ok)throw new IOException(label);checks.put(label);}
    static String q(String s){return JSONObject.quote(s).replace("\\/","/");}
    JSONObject vm(File workspace,String source)throws Exception{source="fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}"+source.replaceAll("return ([1-9][0-9]*);","return fail($1);");JSONObject o=host.engineAt(workspace,3,new JSONObject().put("config",host.workerConfig(workspace,0)).put("source",source).put("call_id","camera-check-"+(++sequence)).put("history",new JSONArray()));if(!o.optString("state").equals("continue")||o.optInt("exit_code")!=0)throw new IOException("Camera scenario "+sequence+": "+o);return o;}
    JSONObject vm(String source)throws Exception{return vm(root,source);}
    String state(String key)throws Exception{return vm("fn main(){let v=state_get("+q(key)+");if db_kind(v)!=2{return 1;}db_io(0,1,db_word(v),db_bytes(v));return 0;}").getString("stdout");}
    void ui(Runnable action)throws Exception{CountDownLatch ready=new CountDownLatch(1);AtomicReference<Throwable> error=new AtomicReference<>();host.runOnUiThread(()->{try{action.run();}catch(Throwable e){error.set(e);}finally{ready.countDown();}});if(!ready.await(5,TimeUnit.SECONDS))throw new IOException("Camera UI fixture timed out");if(error.get()!=null)throw new IOException(error.get());}
    JSONObject report()throws Exception{return new JSONObject().put("ok",true).put("checks",checks).put("physical_devices_verified",false).put("output_profiles",outputProfiles);}
    JSONObject run()throws Exception{
        String id=state("camera_id");CameraManager manager=host.getSystemService(CameraManager.class);check(Arrays.asList(manager.getCameraIdList()).contains(id),"the selected VM camera ID belongs to an independent Android CameraManager inventory");CameraCharacteristics ch=manager.getCameraCharacteristics(id);
        vm("fn main(){let d=camera_info("+q(id)+");if db_word(device_field(d,\"lens_facing\"))!="+ch.get(CameraCharacteristics.LENS_FACING)+"||db_word(device_field(d,\"hardware_level\"))!="+ch.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL)+"||db_word(device_field(d,\"sensor_orientation\"))!="+ch.get(CameraCharacteristics.SENSOR_ORIENTATION)+"{return 1;}return 0;}");
        check(true,"VM lens facing, hardware level and sensor orientation exactly match the independent SDK query");
        List<String> names=new ArrayList<>();for(CaptureRequest.Key<?> k:ch.getAvailableCaptureRequestKeys())names.add(k.getName());Collections.sort(names);
        for(int offset=0;offset<names.size();offset+=32){int end=Math.min(names.size(),offset+32);StringBuilder code=new StringBuilder("fn main(){let p=camera_keys("+q(id)+",1,"+offset+",32);let a=device_field(p,\"keys\");if db_word(device_field(p,\"total\"))!="+names.size()+"||db_count(a)!="+(end-offset)+"{return 1;}");for(int i=offset;i<end;i++)code.append("if !worker_equal(db_word(db_at(a,").append(i-offset).append(")),").append(q(names.get(i))).append("){return 2;}");code.append("return 0;}");vm(code.toString());}
        check(true,"every advertised SDK request-key name survives sorted bounded VM pages without additions or omissions");
        android.util.Range<Long> exposure=ch.get(CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE);if(exposure!=null)vm("fn main(){let p=camera_value("+q(id)+",\"android.sensor.info.exposureTimeRange\",0,1);let v=device_field(p,\"value\");if db_word(db_at(v,0))!="+exposure.getLower()+"||db_word(db_at(v,1))!="+exposure.getUpper()+"{return 1;}return 0;}");
        check(exposure!=null,"the SDK's full integer64 exposure range crosses VM metadata without floating-point coercion");
        vm("fn main(){if camera_list(-1,16)||camera_keys("+q(id)+",1,0,33)||camera_output_sizes("+q(id)+",256,0,17)||camera_open("+q(id)+",499){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}if camera_value("+q(id)+",\"not.a.real.camera.key\",0,1){return 3;}return 0;}");check(true,"invalid inventory/size/key pages, absent metadata keys and startup deadlines fail with typed errors");
        // These explicit codec fixtures construct only documented SDK values;
        // they are not evidence that a physical sensor applies those controls.
        CameraValues.Setting rational=CameraValues.decode("rational",new JSONArray().put(7).put(13));check(rational.type==android.util.Rational.class&&rational.value.equals(new android.util.Rational(7,13)),"an explicitly SDK-constructed rational setting retains its numerator and denominator");
        CameraValues.Setting real=CameraValues.decode("float",VmHardware.real(.625));check(real.type==Float.class&&Float.floatToRawIntBits((Float)real.value)==Float.floatToRawIntBits(.625f),"an explicitly constructed real setting preserves the exact finite binary32 value");
        try{CameraValues.decode("float",VmHardware.real(Double.NaN));throw new IOException("NaN accepted");}catch(VmHardware.Failure expected){check(expected.code.equals("invalid_argument"),"nonfinite control values fail before a Camera2 request is submitted");}
        metadata(ch,id);
        String handle=vm("fn main(){let h=camera_open("+q(id)+",5000);if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");HardwareCamera.Camera owned=VmHardware.handle(context,handle,HardwareCamera.Camera.class);
        try{
            vm("fn main(){let h="+q(handle)+";let i=0;while i<20{let e=device_wait(h,1000);if db_kind(e)==5&&worker_equal(db_word(device_field(e,\"event\")),\"opened\"){return 0;}i=i+1;}return 1;}");
            File other=new File(root,"camera-foreign");if(!new File(other,"files").mkdirs())throw new IOException("Cannot create camera ownership fixture");vm(other,"fn main(){if device_info("+q(handle)+")||camera_frame_info("+q(handle)+",\"frame-unknown\"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 2;}return 0;}");check(true,"another actual VM workspace cannot inspect or use the owned camera");
            vm("fn main(){if camera_open("+q(id)+",5000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"busy\"){return 2;}if camera_frame_info("+q(handle)+",\"frame-unknown\"){return 3;}let outputs=db_list();db_add(outputs,camera_output(256,123,457));if camera_configure("+q(handle)+",outputs,5000){return 4;}if !worker_equal(db_word(db_at(device_error(),0)),\"unsupported_format\"){return 5;}return 0;}");check(true,"overlapping opens, unknown frames and non-advertised sizes fail without silently changing output geometry");
            profileOutputs(handle,owned);
            vm("fn main(){if db_word(camera_shutdown("+q(handle)+"))!=1{return 1;}let i=0;while i<20{let info=device_info("+q(handle)+");if db_word(device_field(info,\"sdk_terminal\"))&&db_word(device_field(info,\"lease_released\")){return 0;}device_wait("+q(handle)+",1000);i=i+1;}return 2;}");check(owned.terminal&&owned.cleaned&&owned.released,"the actual SDK terminal callback and completed component teardown release the owned camera lease");
        }finally{VmHardware.close(context,handle);}
        return report();
    }
    void profileOutputs(String handle,HardwareCamera.Camera owned)throws Exception{
        if(Build.VERSION.SDK_INT<33)return;
        Size[] sizes=owned.ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP).getOutputSizes(android.graphics.ImageFormat.JPEG);
        if(sizes==null||sizes.length==0)throw new IOException("Owned JPEG fixture has no advertised size");
        Size size=sizes[0];for(Size candidate:sizes)if((long)candidate.getWidth()*candidate.getHeight()<(long)size.getWidth()*size.getHeight())size=candidate;
        String basic="let rows=db_list();db_add(rows,camera_profile_output(256,"+size.getWidth()+","+size.getHeight()+",PROFILE,USE_CASE));";
        int generation=owned.generation;
        vm("fn main(){"+basic.replace("PROFILE","1152921504606846976").replace("USE_CASE","0")+"if camera_configure("+q(handle)+",rows,5000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"unsupported_profile\"){return 2;}return 0;}");
        check(owned.generation==generation&&owned.readers.isEmpty(),"a non-advertised dynamic-range profile fails in the actual VM before any output allocation or SDK session submission");
        vm("fn main(){"+basic.replace("PROFILE","0").replace("USE_CASE","-1")+"if camera_configure("+q(handle)+",rows,5000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}return 0;}");
        vm("fn main(){"+basic.replace("PROFILE","-1").replace("USE_CASE","0")+"if camera_configure("+q(handle)+",rows,5000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}return 0;}");
        check(owned.generation==generation&&owned.readers.isEmpty(),"negative profile/use-case values fail without changing the live camera or allocating SDK readers");
        vm("fn main(){let r=camera_output(256,"+size.getWidth()+","+size.getHeight()+");db_add(r,db_int(1));let rows=db_list();db_add(rows,r);if camera_configure("+q(handle)+",rows,5000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}return 0;}");
        check(owned.generation==generation&&owned.readers.isEmpty(),"an incomplete five-field profile record is rejected before a configuration generation changes");
        long useCase=0;long[] actualCases=owned.ch.get(CameraCharacteristics.SCALER_AVAILABLE_STREAM_USE_CASES);if(actualCases!=null)for(long value:actualCases)if(value==CameraMetadata.SCALER_AVAILABLE_STREAM_USE_CASES_STILL_CAPTURE)useCase=value;
        long absentUseCase=Long.MAX_VALUE;boolean found=true;while(found){found=false;if(actualCases!=null)for(long value:actualCases)if(value==absentUseCase){found=true;absentUseCase--;break;}}
        vm("fn main(){"+basic.replace("PROFILE","0").replace("USE_CASE",Long.toString(absentUseCase))+"if camera_configure("+q(handle)+",rows,5000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"unsupported_profile\"){return 2;}return 0;}");
        check(owned.generation==generation&&owned.readers.isEmpty(),"an actual non-advertised positive64-bit stream-use-case ID is rejected without silently selecting a default");
        vm("fn main(){let rows=db_list();db_add(rows,camera_physical_profile_output(256,"+size.getWidth()+","+size.getHeight()+",\"not-a-child\",1,0));if camera_configure("+q(handle)+",rows,5000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}return 0;}");
        check(owned.generation==generation&&owned.readers.isEmpty(),"the extended six-field output record still rejects physical routing outside its actual logical camera");
        int color=-1;if(Build.VERSION.SDK_INT>=34){android.hardware.camera2.params.ColorSpaceProfiles colors=owned.ch.get(CameraCharacteristics.REQUEST_AVAILABLE_COLOR_SPACE_PROFILES);if(colors!=null)for(android.graphics.ColorSpace.Named named:colors.getSupportedColorSpaces(256))if(colors.getSupportedDynamicRangeProfiles(named,256).contains(1L)){color=named.ordinal();if(named==android.graphics.ColorSpace.Named.SRGB)break;}}
        vm("fn main(){"+basic.replace("PROFILE","1").replace("USE_CASE",Long.toString(useCase))+"if camera_configure_color_space("+q(handle)+",rows,2147483647,5000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}return 0;}");
        check(owned.generation==generation&&owned.readers.isEmpty(),"unknown SDK color-space IDs fail through the owned VM path before session construction");
        if(Build.VERSION.SDK_INT>=34){
            android.hardware.camera2.params.ColorSpaceProfiles colors=owned.ch.get(CameraCharacteristics.REQUEST_AVAILABLE_COLOR_SPACE_PROFILES);
            for(android.graphics.ColorSpace.Named named:android.graphics.ColorSpace.Named.values())if(colors==null||!colors.getSupportedColorSpaces(256).contains(named)||!colors.getSupportedDynamicRangeProfiles(named,256).contains(1L)){
                vm("fn main(){"+basic.replace("PROFILE","1").replace("USE_CASE","0")+"if camera_configure_color_space("+q(handle)+",rows,"+named.ordinal()+",5000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"unsupported_profile\"){return 2;}return 0;}");
                check(owned.generation==generation&&owned.readers.isEmpty(),"a valid SDK color-space ID with an unsupported actual format/profile combination is rejected before session mutation");break;
            }
        }
        android.hardware.camera2.params.DynamicRangeProfiles constrained=new android.hardware.camera2.params.DynamicRangeProfiles(new long[]{2,2,0,4,4,0});
        HardwareCameraOutput.Api33.constraints(constrained,2,Collections.singletonList(2L));
        try{HardwareCameraOutput.Api33.constraints(constrained,2,Arrays.asList(2L,4L));throw new IOException("Incompatible profiles accepted");}catch(VmHardware.Failure expected){check(expected.code.equals("unsupported_combination"),"constructed public SDK capture constraints reject incompatible targets while allowing the profile by itself");}
        HardwareCameraOutput.Api33.constraints(new android.hardware.camera2.params.DynamicRangeProfiles(new long[]{2,0,0}),2,Arrays.asList(1L,2L));
        check(true,"an actual empty SDK capture-constraint set means unrestricted targets rather than no targets");
        String configured=basic.replace("PROFILE","1").replace("USE_CASE",Long.toString(useCase));
        vm("fn main(){"+configured+"if !camera_configure_color_space("+q(handle)+",rows,"+color+",5000){return 1;}return 0;}");
        vm("fn main(){let i=0;while i<20{let e=device_wait("+q(handle)+",1000);if db_kind(e)==5&&worker_equal(db_word(device_field(e,\"event\")),\"configured\"){if !db_word(device_field(e,\"sdk_callback\")){return 1;}return 0;}i=i+1;}return 2;}");
        HardwareCamera.Reader output;synchronized(owned){check(owned.readers.size()==1&&owned.state.equals("configured"),"explicit profile output receives an actual SDK configured callback");output=owned.readers.values().iterator().next();}
        check(output.configuration.getDynamicRangeProfile()==1&&output.configuration.getStreamUseCase()==useCase,"the exact retained SDK OutputConfiguration contains the requested STANDARD profile and advertised/default stream use case");
        vm("fn main(){let d=device_info("+q(handle)+");let o=db_at(device_field(d,\"outputs\"),0);if db_kind(device_field(o,\"dynamic_range_profile\"))!=1||db_kind(device_field(o,\"stream_use_case\"))!=1||db_word(device_field(o,\"dynamic_range_profile\"))!=1||db_word(device_field(o,\"stream_use_case\"))!="+useCase+"{return 1;}return 0;}");
        check(true,"actual SDK profile/use-case getters cross the VM result transport without claiming an effective image change");
        if(color>=0){vm("fn main(){if db_kind(device_field(device_info("+q(handle)+"),\"configuration_color_space_id\"))!=1||db_word(device_field(device_info("+q(handle)+"),\"configuration_color_space_id\"))!="+color+"{return 1;}return 0;}");check(owned.configurationColorSpace==color,"the actual SessionConfiguration color-space getter is retained independently of output profile metadata");}
        vm("fn main(){if !camera_capture("+q(handle)+",2,db_list(),0){return 2;}let i=0;while i<30{let e=device_wait("+q(handle)+",1000);if db_kind(e)==5&&worker_equal(db_word(device_field(e,\"event\")),\"frame\"){state_set(\"profile_frame\",device_field(e,\"frame\"));return 0;}i=i+1;}return 1;}");
        String frame=state("profile_frame");HardwareCamera.Frame actual=owned.frame(frame);int dataSpace=actual.image.getDataSpace();
        vm("fn main(){let f=camera_frame_info("+q(handle)+","+q(frame)+");if db_kind(device_field(f,\"data_space\"))!=1||db_word(device_field(f,\"data_space\"))!="+dataSpace+"{return 1;}return db_word(camera_frame_close("+q(handle)+","+q(frame)+"))-1;}");
        check(true,"a real JPEG from the explicit-profile session exposes the independent actual SDK image data-space value through the VM");
        android.hardware.camera2.params.DynamicRangeProfiles actualProfiles=owned.ch.get(CameraCharacteristics.REQUEST_AVAILABLE_DYNAMIC_RANGE_PROFILES);
        Size[] p010=owned.ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP).getOutputSizes(android.graphics.ImageFormat.YCBCR_P010);
        outputProfiles.put("standard_session_verified",true).put("color_space_verified",color>=0).put("selected_color_space_id",color<0?JSONObject.NULL:color).put("selected_stream_use_case",useCase).put("nondefault_stream_use_case_verified",useCase!=0).put("dynamic_range_profile_map_present",actualProfiles!=null).put("advertised_dynamic_ranges",actualProfiles==null?new JSONArray():new JSONArray(new TreeSet<>(actualProfiles.getSupportedProfiles()))).put("p010_sizes",p010==null?0:p010.length).put("hdr_capture_verified",false).put("hdr_accuracy_verified",false);
        if(actualProfiles!=null&&actualProfiles.getSupportedProfiles().contains(2L)&&p010!=null&&p010.length>0)hdrOutput(handle,owned,p010);

    }
    void hdrOutput(String handle,HardwareCamera.Camera owned,Size[] sizes)throws Exception{
        Size size=sizes[0];for(Size candidate:sizes)if((long)candidate.getWidth()*candidate.getHeight()<(long)size.getWidth()*size.getHeight())size=candidate;
        int color=-1;
        if(Build.VERSION.SDK_INT>=34){android.hardware.camera2.params.ColorSpaceProfiles profiles=owned.ch.get(CameraCharacteristics.REQUEST_AVAILABLE_COLOR_SPACE_PROFILES);if(profiles!=null)for(android.graphics.ColorSpace.Named candidate:new TreeSet<>(profiles.getSupportedColorSpacesForDynamicRange(android.graphics.ImageFormat.YCBCR_P010,2))){color=candidate.ordinal();if(candidate==android.graphics.ColorSpace.Named.BT2020_HLG)break;}}
        vm("fn main(){let rows=db_list();db_add(rows,camera_profile_output(54,"+size.getWidth()+","+size.getHeight()+",2,0));if !camera_configure_color_space("+q(handle)+",rows,"+color+",10000){return 1;}let i=0;while i<20{let e=device_wait("+q(handle)+",1000);if db_kind(e)==5&&worker_equal(db_word(device_field(e,\"event\")),\"configured\"){return 0;}i=i+1;}return 2;}");
        synchronized(owned){HardwareCamera.Reader output=owned.readers.values().iterator().next();check(output.configuration.getDynamicRangeProfile()==2&&owned.state.equals("configured"),"a real HLG10/P010 session receives an actual configured callback with exact SDK profile2");}
        vm("fn main(){if !camera_capture("+q(handle)+",1,db_list(),0){return 1;}let i=0;while i<30{let e=device_wait("+q(handle)+",1000);if db_kind(e)==5&&worker_equal(db_word(device_field(e,\"event\")),\"frame\"){state_set(\"hdr_frame\",device_field(e,\"frame\"));return 0;}i=i+1;}return 2;}");
        String id=state("hdr_frame");HardwareCamera.Frame actual=owned.frame(id);int dataSpace=actual.image.getDataSpace();
        check(actual.image.getFormat()==android.graphics.ImageFormat.YCBCR_P010&&actual.image.getWidth()==size.getWidth()&&actual.image.getHeight()==size.getHeight(),"the HLG session delivers a real SDK P010 image at the exact advertised dimensions");
        check(android.hardware.DataSpace.getStandard(dataSpace)==android.hardware.DataSpace.STANDARD_BT2020&&android.hardware.DataSpace.getTransfer(dataSpace)==android.hardware.DataSpace.TRANSFER_HLG,"the actual captured P010 image reports BT2020/HLG in its SDK data-space metadata: "+dataSpace);
        boolean large=verifyFramePlanes(handle,id,actual);
        check(true,"every HDR/P010 plane byte and stride crosses bounded VM pages and agrees with the independent actual SDK buffers");
        vm("fn main(){let f=camera_frame_info("+q(handle)+","+q(id)+");if db_kind(device_field(f,\"data_space\"))!=1||db_word(device_field(f,\"data_space\"))!="+dataSpace+"||db_word(device_field(f,\"format\"))!=54{return 1;}return db_word(camera_frame_close("+q(handle)+","+q(id)+"))-1;}");
        outputProfiles.put("hdr_capture_verified",true).put("hdr_profile",2).put("hdr_format",54).put("hdr_width",size.getWidth()).put("hdr_height",size.getHeight()).put("hdr_data_space",dataSpace).put("hdr_color_space_id",color<0?JSONObject.NULL:color).put("hdr_plane_paging_verified",true).put("hdr_has_plane_above32k",large);
    }
    void wire(String expression,Object expected,StringBuilder code,int[] sequence)throws Exception{
        String name="v"+(sequence[0]++);code.append("let ").append(name).append("=").append(expression).append(";if !").append(name).append("{return 1;}");
        if(expected==JSONObject.NULL){code.append("if db_kind(").append(name).append(")!=0{return 2;}");return;}
        if(expected instanceof JSONObject&&((JSONObject)expected).has("$real")){
            code.append("if db_kind(").append(name).append(")!=4||db_word(").append(name).append(")!=").append(((JSONObject)expected).getLong("$real")).append("{return 3;}");return;
        }
        if(expected instanceof JSONObject){
            JSONObject object=(JSONObject)expected;code.append("if db_kind(").append(name).append(")!=5||db_count(").append(name).append(")!=").append(object.length()).append("{return 4;}");
            for(Iterator<String> keys=object.keys();keys.hasNext();){String key=keys.next();wire("device_field("+name+","+q(key)+")",object.get(key),code,sequence);}return;
        }
        if(expected instanceof JSONArray){
            JSONArray array=(JSONArray)expected;code.append("if db_kind(").append(name).append(")!=5||db_count(").append(name).append(")!=").append(array.length()).append("{return 5;}");
            for(int i=0;i<array.length();i++)wire("db_at("+name+","+i+")",array.get(i),code,sequence);return;
        }
        if(expected instanceof String){code.append("if db_kind(").append(name).append(")!=2||!worker_equal(db_word(").append(name).append("),").append(q((String)expected)).append("){return 6;}");return;}
        long number=expected instanceof Boolean?((Boolean)expected?1:0):((Number)expected).longValue();
        code.append("if db_kind(").append(name).append(")!=1||db_word(").append(name).append(")!=").append(number==Long.MIN_VALUE?"(-9223372036854775807-1)":Long.toString(number)).append("{return 7;}");
    }
    void wirePage(String expression,JSONObject expected)throws Exception{
        StringBuilder code=new StringBuilder("fn main(){");wire(expression,expected,code,new int[]{0});code.append("return 0;}");
        if(code.length()>60000)throw new IOException("Metadata oracle source exceeds its test bound");vm(code.toString());
    }
    static JSONObject expectedPage(JSONArray rows,int total,int end,String type)throws Exception{
        JSONObject value=new JSONObject().put("value",rows).put("array",true).put("total",total).put("next",end<total?end:-1);
        if(type!=null)value.put("sdk_type",type);return value;
    }
    void metadataFixture(Object value,int offset,int limit,JSONObject expected)throws Exception{
        VmHardware.Handle fixture=new VmHardware.Handle(context,"camera","camera_metadata_fixture"){
            public Object info()throws Exception{check();return CameraValues.page(value,offset,limit);}
        };String handle=VmHardware.add(fixture);
        try{wirePage("device_info("+q(handle)+")",expected);}finally{VmHardware.close(context,handle);}
    }
    void dynamicProfile(Object object,String expression)throws Exception{
        android.hardware.camera2.params.DynamicRangeProfiles profiles=(android.hardware.camera2.params.DynamicRangeProfiles)object;
        TreeSet<Long> ids=new TreeSet<>(profiles.getSupportedProfiles());int count=0;
        for(long id:ids){
            TreeSet<Long> constraints=new TreeSet<>(profiles.getProfileCaptureRequestConstraints(id));
            JSONArray rows=new JSONArray().put(new JSONObject().put("profile",id).put("capture_request_constraints",new JSONArray(constraints)).put("extra_latency",profiles.isExtraLatencyPresent(id)));
            JSONObject expected=expectedPage(rows,ids.size(),count+1,"dynamic_range_profiles");
            if(expression==null)metadataFixture(object,count,1,expected);else wirePage(expression.replace("OFFSET",Integer.toString(count)),expected);count++;
        }
        JSONObject end=expectedPage(new JSONArray(),ids.size(),ids.size(),"dynamic_range_profiles");
        if(expression==null)metadataFixture(object,ids.size(),1,end);else wirePage(expression.replace("OFFSET",Integer.toString(ids.size())),end);
    }
    void colorProfile(Object object,String expression)throws Exception{
        android.hardware.camera2.params.ColorSpaceProfiles profiles=(android.hardware.camera2.params.ColorSpaceProfiles)object;
        TreeSet<android.graphics.ColorSpace.Named> colors=new TreeSet<>(profiles.getSupportedColorSpaces(android.hardware.camera2.params.ColorSpaceProfiles.UNSPECIFIED));JSONArray all=new JSONArray();
        for(android.graphics.ColorSpace.Named color:colors)for(int format:new TreeSet<>(profiles.getSupportedImageFormatsForColorSpace(color))){
            all.put(new JSONObject().put("color_space_id",color.ordinal()).put("color_space",color.name()).put("image_format",format).put("dynamic_ranges",new JSONArray(new TreeSet<>(profiles.getSupportedDynamicRangeProfiles(color,format)))));
        }
        for(int i=0;i<all.length();i++){
            JSONObject expected=expectedPage(new JSONArray().put(all.get(i)),all.length(),i+1,"color_space_profiles");
            if(expression==null)metadataFixture(object,i,1,expected);else wirePage(expression.replace("OFFSET",Integer.toString(i)),expected);
        }
        JSONObject end=expectedPage(new JSONArray(),all.length(),all.length(),"color_space_profiles");
        if(expression==null)metadataFixture(object,all.length(),1,end);else wirePage(expression.replace("OFFSET",Integer.toString(all.length())),end);
    }
    void metadata(CameraCharacteristics characteristics,String id)throws Exception{
        android.util.Pair<Double,Double>[] noise=new android.util.Pair[]{new android.util.Pair<>(1.25,.5),new android.util.Pair<>(2.5,.125)};
        metadataFixture(noise,1,1,expectedPage(new JSONArray().put(new JSONArray().put(VmHardware.real(2.5)).put(VmHardware.real(.125))),2,2,null));
        metadataFixture(new android.util.Pair<>(null,Double.NaN),0,1,new JSONObject().put("value",new JSONArray().put(JSONObject.NULL).put(new JSONObject().put("non_finite","nan"))).put("array",false).put("total",1).put("next",-1));
        check(true,"constructed SDK Pair/noise-profile values preserve pagination, binary64 coefficients, null and nonfinite markers through the real VM");
        if(Build.VERSION.SDK_INT>=33){
            android.hardware.camera2.params.DynamicRangeProfiles profiles=new android.hardware.camera2.params.DynamicRangeProfiles(new long[]{2,3,0,4,1,1});
            dynamicProfile(profiles,null);
            check(true,"constructed public dynamic-range SDK profile, constraint and latency values survive every VM page and exact EOF");
            android.hardware.camera2.params.DynamicRangeProfiles actual=characteristics.get(CameraCharacteristics.REQUEST_AVAILABLE_DYNAMIC_RANGE_PROFILES);
            if(actual!=null){dynamicProfile(actual,"camera_value("+q(id)+",\"android.request.availableDynamicRangeProfiles\",OFFSET,1)");check(true,"every actual advertised camera dynamic-range profile agrees with independent SDK getter values through camera_value");}
        }
        if(Build.VERSION.SDK_INT>=34){
            android.hardware.camera2.params.ColorSpaceProfiles profiles=new android.hardware.camera2.params.ColorSpaceProfiles(new long[]{0,256,1,7,35,3,7,256,2});
            colorProfile(profiles,null);colorProfile(new android.hardware.camera2.params.ColorSpaceProfiles(new long[0]),null);
            check(true,"constructed public color-space SDK mappings preserve sorted color/format identities, exact dynamic-range sets and empty/EOF pages in the VM");
            android.hardware.camera2.params.Capability capability=new android.hardware.camera2.params.Capability(2,new Size(1920,1080),new android.util.Range<Float>(.5f,4f));
            metadataFixture(capability,0,1,new JSONObject().put("value",new JSONObject().put("sdk_type","capability").put("mode",2).put("maximum_streaming_size",new JSONArray().put(1920).put(1080)).put("zoom_ratio_range",new JSONArray().put(VmHardware.real(.5)).put(VmHardware.real(4)))).put("array",false).put("total",1).put("next",-1));
            check(true,"a constructed public Capability transports mode, maximum dimensions and exact zoom range without toString or reflection");
            android.hardware.camera2.params.ColorSpaceProfiles actual=characteristics.get(CameraCharacteristics.REQUEST_AVAILABLE_COLOR_SPACE_PROFILES);
            if(actual!=null){colorProfile(actual,"camera_value("+q(id)+",\"android.request.availableColorSpaceProfiles\",OFFSET,1)");check(true,"every actual camera color-space/format/profile mapping matches an independent SDK query through camera_value");}
        }
        for(int[] bounds:new int[][]{{-1,1},{1000001,1},{0,0},{0,33}})try{CameraValues.page(noise,bounds[0],bounds[1]);throw new IOException("Invalid metadata page accepted");}catch(VmHardware.Failure expected){check(expected.code.equals("invalid_argument"),"invalid direct metadata page bound fails before SDK profile traversal: "+Arrays.toString(bounds));}
    }
    JSONObject video()throws Exception{
        String id=state("video");HardwareCameraVideo.Video v=VmHardware.handle(context,id,HardwareCameraVideo.Video.class);check(v.released&&v.state.equals("stopped")&&v.file.length()>0,"the actual recorder returned from stop/release and produced a nonempty finalized container");
        MediaExtractor extractor=new MediaExtractor();int video=0,audio=0,samples=0;
        try{extractor.setDataSource(v.file.getAbsolutePath());for(int i=0;i<extractor.getTrackCount();i++){MediaFormat format=extractor.getTrackFormat(i);String mime=format.getString(MediaFormat.KEY_MIME);if(mime.startsWith("video/")){video++;check(format.getInteger(MediaFormat.KEY_WIDTH)==v.width&&format.getInteger(MediaFormat.KEY_HEIGHT)==v.height,"the independent MediaExtractor validates the actual encoded video dimensions");extractor.selectTrack(i);ByteBufferHolder buffer=new ByteBufferHolder();long prior=-1;for(int n=0;n<240;n++){int size=extractor.readSampleData(buffer.value,0);if(size<0)break;long time=extractor.getSampleTime();checkTime(time>=prior);prior=time;samples++;if(!extractor.advance())break;}extractor.unselectTrack(i);}else if(mime.startsWith("audio/"))audio++;}
        }finally{extractor.release();}
        check(video==1&&samples>0&&audio==(v.audio?1:0),"the independent container parser sees actual video samples and exactly the requested presence/absence of an audio track");
        Adler32 checksum=new Adler32();long count=0;try(InputStream in=new FileInputStream(v.file)){byte[] bytes=new byte[4096];for(int n;(n=in.read(bytes))!=-1;){checksum.update(bytes,0,n);count+=n;}}
        vm("fn main(){let h="+q(id)+";if db_word(camera_video_seek(h,0))!=0{return 1;}let a=1;let b=0;let count=0;let done=0;while !done{let v=device_read(h,32768,1000);if db_kind(v)==0{done=1;}else{if db_kind(v)!=3{return 2;}let i=0;while i<db_bytes(v){a=(a+load8(db_word(v)+i))%65521;b=(b+a)%65521;i=i+1;}count=count+db_bytes(v);}}if count!="+count+"||((b<<16)|a)!="+checksum.getValue()+"{return 3;}if camera_video_seek(h,"+(count+1)+"){return 4;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 5;}if device_write(h,db_text(\"no\")){return 6;}return 0;}");check(true,"every encoded container byte crosses bounded VM pages and matches an independent whole-file Adler32/length, with EOF, seek bounds and read-only enforcement");
        File file=v.file;vm("fn main(){return device_close("+q(id)+")-1;}");check(!file.exists()&&v.lease.released,"closing the finalized video resource deletes its owned private spool and releases the retained resource slot");return report();
    }
    static void checkTime(boolean ok)throws IOException{if(!ok)throw new IOException("Encoded video sample timestamps are not monotonic");}
    static final class ByteBufferHolder {final java.nio.ByteBuffer value=java.nio.ByteBuffer.allocate(4*1024*1024);}
    boolean verifyFramePlanes(String handle,String id,HardwareCamera.Frame frame)throws Exception{
        Image.Plane[] planes=frame.image.getPlanes();boolean large=false;
        for(int p=0;p<planes.length;p++){
            java.nio.ByteBuffer bytes=planes[p].getBuffer().duplicate();int count=bytes.remaining();if(count>32768)large=true;
            vm("fn main(){let f=camera_frame_info("+q(handle)+","+q(id)+");let row=db_at(device_field(f,\"planes\"),"+p+");if db_word(device_field(row,\"bytes\"))!="+count+"||db_word(device_field(row,\"row_stride\"))!="+planes[p].getRowStride()+"||db_word(device_field(row,\"pixel_stride\"))!="+planes[p].getPixelStride()+"{return 1;}return 0;}");
            for(int offset=0;bytes.hasRemaining();){int n=Math.min(bytes.remaining(),32768);byte[] data=new byte[n];bytes.get(data);Adler32 sum=new Adler32();sum.update(data);int next=offset+n<count?offset+n:-1;
                vm("fn main(){let r=camera_frame_read("+q(handle)+","+q(id)+","+p+","+offset+",32768);if !r{return 1;}let v=device_field(r,\"value\");if db_bytes(v)!="+n+"||db_word(device_field(r,\"total\"))!="+count+"||db_word(device_field(r,\"next\"))!="+next+"{return 2;}let ptr=db_word(v);let i=0;let a=1;let b=0;while i<"+n+"{a=(a+load8(ptr+i))%65521;b=(b+a)%65521;i=i+1;}if ((b<<16)|a)!="+sum.getValue()+"{return 3;}return 0;}");offset+=n;
            }
        }
        return large;
    }
    JSONObject yuv()throws Exception{
        String handle=state("camera"),id=state("frame");HardwareCamera.Camera camera=VmHardware.handle(context,handle,HardwareCamera.Camera.class);HardwareCamera.Frame frame=camera.frame(id);
        check(frame.image.getFormat()==android.graphics.ImageFormat.YUV_420_888&&frame.image.getPlanes().length==3,"the actual ImageReader exposes a real three-plane YUV420 image");
        boolean large=verifyFramePlanes(handle,id,frame);
        check(large,"the advertised YUV fixture contains a plane larger than one32768-byte VM page");
        check(true,"all three VM-paged YUV planes match independent SDK buffers byte-for-byte by exact length/Adler32, including actual row and pixel strides");
        boolean manual=false;int[] caps=camera.ch.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES);if(caps!=null)for(int cap:caps)if(cap==CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR)manual=true;
        if(manual){
            android.util.Range<Integer> sensitivity=camera.ch.get(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE);android.util.Range<Long> exposure=camera.ch.get(CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE);if(sensitivity==null||exposure==null)throw new IOException("Manual capability lacks required SDK ranges");
            int iso=Math.min(sensitivity.getUpper(),Math.max(100,sensitivity.getLower()));long ns=Math.min(exposure.getUpper(),Math.max(10000000L,exposure.getLower()));
            JSONObject submitted=vm("fn main(){let settings=db_list();db_add(settings,camera_setting(\"android.control.mode\",\"int\",db_int(0)));db_add(settings,camera_setting(\"android.control.aeMode\",\"int\",db_int(0)));db_add(settings,camera_setting(\"android.sensor.sensitivity\",\"int\",db_int("+iso+")));db_add(settings,camera_setting(\"android.sensor.exposureTime\",\"long\",db_int("+ns+")));let n=camera_capture("+q(handle)+",6,settings,0);if db_kind(n)!=1{return 1;}let number=db_word(n);let b=alloc(20);let i=20;while number>=10{i=i-1;store8(b+i,48+number%10);number=number/10;}i=i-1;store8(b+i,48+number);db_io(0,1,b+i,20-i);return 0;}");
            int captureSequence=Integer.parseInt(submitted.getString("stdout"));
            until(()->{synchronized(camera){for(TotalCaptureResult r:camera.results.values())if(r.getSequenceId()==captureSequence)return true;return false;}});String resultId=null;TotalCaptureResult result=null;synchronized(camera){for(Map.Entry<String,TotalCaptureResult> r:camera.results.entrySet())if(r.getValue().getSequenceId()==captureSequence){resultId=r.getKey();result=r.getValue();break;}}
            vm("fn main(){let i=0;while i<20{let e=device_wait("+q(handle)+",1000);if db_kind(e)==5&&worker_equal(db_word(device_field(e,\"event\")),\"capture_completed\")&&db_word(device_field(e,\"sequence_id\"))=="+captureSequence+"&&worker_equal(db_word(device_field(e,\"result\")),"+q(resultId)+"){return 0;}i=i+1;}return 1;}");check(true,"the actual VM completion event correlates its result ID to the exact submitted SDK sequence, including valid sequence zero");
            Integer actualIso=result.get(CaptureResult.SENSOR_SENSITIVITY),mode=result.get(CaptureResult.CONTROL_AE_MODE);Long actualExposure=result.get(CaptureResult.SENSOR_EXPOSURE_TIME);check(actualIso!=null&&actualIso==iso&&mode!=null&&mode==CaptureRequest.CONTROL_AE_MODE_OFF&&actualExposure!=null&&Math.abs(actualExposure-ns)<=Math.max(100000L,ns/100),"the actual manual-template SDK result confirms requested ISO/exposure and disabled AE, rather than only accepting a settings object");
            vm("fn main(){let p=camera_result_value("+q(handle)+","+q(resultId)+",\"android.sensor.exposureTime\",0,1);if db_word(device_field(p,\"value\"))!="+actualExposure+"{return 1;}return 0;}");check(true,"the applied manual exposure returns through the actual result-key VM transport as an exact integer64");
        }
        return report().put("manual_sensor_supported",manual).put("manual_sensor_verified",manual);
    }
    JSONObject physical()throws Exception{
        String handle=state("camera");HardwareCamera.Camera camera=VmHardware.handle(context,handle,HardwareCamera.Camera.class);String logical=camera.cameraId;
        check(Build.VERSION.SDK_INT>=31&&camera.ch.getPhysicalCameraIds().isEmpty(),"the actual emulator camera advertises no physical children; positive physical overrides/results are not claimed");
        String[] inventory={"camera_physical_info("+q(logical)+",\"not-a-child\")","camera_physical_keys("+q(logical)+",\"not-a-child\",0,32)","camera_physical_value("+q(logical)+",\"not-a-child\",\"android.sensor.orientation\",0,1)","camera_physical_formats("+q(logical)+",\"not-a-child\",0,32)","camera_physical_output_sizes("+q(logical)+",\"not-a-child\",35,0,16)"};
        for(String call:inventory)vm("fn main(){if "+call+"{return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}return 0;}");
        check(true,"all five physical inventory calls reject an ID absent from the actual logical camera without substituting its metadata");
        until(()->{synchronized(camera){return !camera.results.isEmpty()&&camera.pendingSequences.isEmpty()&&camera.reservations==0;}});
        String token;TotalCaptureResult actual;synchronized(camera){token=camera.results.keySet().iterator().next();actual=camera.results.get(token);}
        check(actual.getPhysicalCameraTotalResults().isEmpty(),"the real completed SDK capture contains an empty physical-result map");
        vm("fn main(){let p=camera_result_physical("+q(handle)+","+q(token)+",0,16);if !p||db_word(device_field(p,\"total\"))||db_count(device_field(p,\"cameras\"))||db_word(device_field(p,\"next\"))!=-1||!db_word(device_field(p,\"total_results_api\")){return 1;}return 0;}");
        check(true,"the actual VM returns the SDK's empty physical-result map and Android12+ API provenance without invented child records");
        for(String suffix:new String[]{"-1,16","0,0","0,17","129,1"})vm("fn main(){if camera_result_physical("+q(handle)+","+q(token)+","+suffix+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}return 0;}");
        check(true,"physical-result paging rejects negative offsets, zero/oversized pages and offsets above128 through the actual VM");
        vm("fn main(){if camera_physical_result_keys("+q(handle)+","+q(token)+",\"not-a-child\",0,32){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"unavailable\"){return 2;}if camera_physical_result_value("+q(handle)+","+q(token)+",\"not-a-child\",\"android.sensor.exposureTime\",0,1){return 3;}if !worker_equal(db_word(db_at(device_error(),0)),\"unavailable\"){return 4;}return 0;}");
        check(true,"physical key/value requests report absent child metadata separately from unknown or evicted parent results");
        vm("fn main(){if camera_result_physical("+q(handle)+",\"not-a-result\",0,16){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_result\"){return 2;}return 0;}");
        check(true,"unknown parent capture-result IDs fail with stale_result before physical metadata is inspected");
        File other=new File(root,"physical-foreign");if(!new File(other,"files").mkdirs())throw new IOException("Cannot create physical-result ownership fixture");
        for(String call:new String[]{"camera_result_physical("+q(handle)+","+q(token)+",0,16)","camera_physical_result_keys("+q(handle)+","+q(token)+",\"not-a-child\",0,32)","camera_physical_result_value("+q(handle)+","+q(token)+",\"not-a-child\",\"android.sensor.exposureTime\",0,1)"})vm(other,"fn main(){if "+call+"{return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 2;}return 0;}");
        check(true,"all three physical-result operations reject a different actual VM workspace before metadata access");
        int retained;synchronized(camera){retained=camera.results.size();}
        for(String row:new String[]{"camera_physical_setting(\"not-a-child\",\"android.control.aeMode\",\"int\",db_int(0))","camera_physical_setting(\"\",\"android.control.aeMode\",\"int\",db_int(0))"})vm("fn main(){let s=db_list();db_add(s,"+row+");if camera_capture("+q(handle)+",1,s,0){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}return 0;}");
        check(true,"the portable four-field setting helper reaches trusted validation; absent/empty physical IDs are rejected");
        vm("fn main(){let s=db_list();let r=camera_setting(\"android.control.aeMode\",\"int\",db_int(0));db_add(r,db_int(1));db_add(s,r);if camera_capture("+q(handle)+",1,s,0){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}return 0;}");
        check(true,"non-text physical identifiers fail as typed invalid arguments instead of reaching SDK request submission");
        synchronized(camera){check(camera.reservations==0&&camera.pendingSequences.isEmpty()&&camera.results.size()==retained,"rejected physical settings free local reservations and submit no capture sequences or result records");}
        CaptureRequest.Builder builder=camera.sdk.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
        JSONArray globals=new JSONArray().put(new JSONArray().put("android.control.aeMode").put("int").put(0));
        HardwareCameraPhysical.apply(builder,HardwareCameraPhysical.settings(camera.ch,Collections.emptySet(),true,globals));
        check(builder.get(CaptureRequest.CONTROL_AE_MODE)==CaptureRequest.CONTROL_AE_MODE_OFF,"ordinary global settings still set the exact value on a real public SDK request builder");
        // Nine actual captures exercise parent eviction rather than constructing
        // SDK results or editing the retained-result table in the fixture.
        for(int i=0;i<9;i++){
            final Set<String> previous;synchronized(camera){previous=new HashSet<>(camera.results.keySet());}
            vm("fn main(){if db_kind(camera_capture("+q(handle)+",1,db_list(),0))!=1{return 1;}return 0;}");
            until(()->{synchronized(camera){for(String id:camera.results.keySet())if(!previous.contains(id))return camera.pendingSequences.isEmpty()&&camera.reservations==0;return false;}});
        }
        vm("fn main(){if camera_result_physical("+q(handle)+","+q(token)+",0,16){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_result\"){return 2;}if camera_physical_result_keys("+q(handle)+","+q(token)+",\"not-a-child\",0,32){return 3;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_result\"){return 4;}if camera_physical_result_value("+q(handle)+","+q(token)+",\"not-a-child\",\"android.sensor.exposureTime\",0,1){return 5;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_result\"){return 6;}return 0;}");
        synchronized(camera){check(camera.results.size()==8,"nine real SDK capture callbacks evict old parent results while retaining the existing eight-result bound");}
        check(true,"physical pages and key/value queries all become stale when their parent result is evicted by actual captures");
        return report().put("physical_overrides_verified",false).put("physical_result_values_verified",false).put("actual_empty_physical_results_verified",true);
    }
    static final class Gate implements AutoCloseable {
        final CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        Gate()throws Exception{HardwareCamera.events().post(()->{entered.countDown();try{release.await(30,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}});if(!entered.await(4,TimeUnit.SECONDS))throw new IOException("Camera SDK callback queue did not block");}
        public void close(){release.countDown();}
    }
    static String cameraState(HardwareCamera.Camera c){synchronized(c){return c.state;}}
    static boolean cameraReleased(HardwareCamera.Camera c){synchronized(c){return c.released;}}
    void until(java.util.function.BooleanSupplier ready)throws Exception{long deadline=SystemClock.elapsedRealtime()+10000;while(!ready.getAsBoolean()){if(SystemClock.elapsedRealtime()>=deadline)throw new IOException("Actual camera SDK teardown did not finish");Thread.sleep(10);}}
    String open(String id)throws Exception{String handle=vm("fn main(){let h=camera_open("+q(id)+",5000);if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");HardwareCamera.Camera c=VmHardware.handle(context,handle,HardwareCamera.Camera.class);until(()->cameraState(c).equals("open"));return handle;}
    void close(String handle)throws Exception{HardwareCamera.Camera camera=VmHardware.handle(context,handle,HardwareCamera.Camera.class);ui(()->{try{camera.close();}catch(IOException e){throw new RuntimeException(e);}});until(()->cameraReleased(camera));}
    JSONObject lifecycle()throws Exception{
        String id=state("camera_id");String pending;HardwareCamera.Camera camera;
        try(Gate gate=new Gate()){
            pending=vm("fn main(){let h=camera_open("+q(id)+",500);if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");camera=VmHardware.handle(context,pending,HardwareCamera.Camera.class);Thread.sleep(650);
            vm("fn main(){let d=device_info("+q(pending)+");if !worker_equal(db_word(device_field(d,\"state\")),\"error\"){return 1;}if camera_open("+q(id)+",5000){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"busy\"){return 3;}return 0;}");
            check(!camera.terminal&&!camera.released,"elapsed-time expiry is enforced with the real SDK callback/deadline queue blocked, while the pending open lease stays owned");
            ui(()->{try{camera.close();}catch(IOException e){throw new RuntimeException(e);}});check(camera.closed&&!camera.released,"local close returns on the real UI thread without waiting for its blocked SDK open callback");
        }
        until(()->cameraReleased(camera));check(camera.terminal&&camera.cleaned&&camera.events.isEmpty(),"the delayed actual SDK device is closed without a late guest opened event, and its terminal callback releases capacity");
        String configured=open(id);HardwareCamera.Camera config=VmHardware.handle(context,configured,HardwareCamera.Camera.class);Size smallest=smallest(config.ch,256);
        try(Gate gate=new Gate()){
            vm("fn main(){let outputs=db_list();db_add(outputs,camera_output(256,"+smallest.getWidth()+","+smallest.getHeight()+"));if !camera_configure("+q(configured)+",outputs,500){return 1;}return 0;}");Thread.sleep(650);
            vm("fn main(){let d=device_info("+q(configured)+");if !worker_equal(db_word(device_field(d,\"state\")),\"error\"){return 1;}return 0;}");
            check(!config.released,"configuration expiry does not pretend queued SDK teardown has already completed");ui(()->{try{config.close();}catch(IOException e){throw new RuntimeException(e);}});
        }
        until(()->cameraReleased(config));check(config.terminal&&config.cleaned&&config.frames.isEmpty(),"late actual configuration callbacks cannot revive a timed-out resource or expose stale frame data");
        String burst=open(id);HardwareCamera.Camera queued=VmHardware.handle(context,burst,HardwareCamera.Camera.class);Size yuv=smallest(queued.ch,android.graphics.ImageFormat.YUV_420_888);
        vm("fn main(){let outputs=db_list();db_add(outputs,camera_output(35,"+yuv.getWidth()+","+yuv.getHeight()+"));if !camera_configure("+q(burst)+",outputs,5000){return 1;}return 0;}");until(()->cameraState(queued).equals("configured"));
        try(Gate gate=new Gate()){
            vm("fn main(){let i=0;while i<16{if !camera_capture("+q(burst)+",2,db_list(),0){return 1;}i=i+1;}if camera_capture("+q(burst)+",2,db_list(),0){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"resource_limit\"){return 3;}return 0;}");
            check(queued.pendingSequences.size()==16,"sixteen real submitted SDK captures remain bounded while callbacks are blocked, and the seventeenth is rejected before submission");
            ui(()->{try{queued.close();}catch(IOException e){throw new RuntimeException(e);}});check(!queued.released,"a UI-thread close keeps its lease until the actual queued camera terminal callback");
        }
        until(()->cameraReleased(queued));check(queued.pendingSequences.isEmpty(),"actual shutdown clears the pending request registry without replaying the queued captures");
        vm("fn main(){let all=db_list();let i=0;while i<8{let h=camera_watch();if !h{return 1;}db_add(all,h);i=i+1;}if camera_watch(){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"resource_limit\"){return 3;}i=0;while i<8{if !device_close(db_word(db_at(all,i))){return 4;}i=i+1;}return 0;}");until(()->HardwareCamera.WATCHES.availablePermits()==8);check(true,"eight actual availability/torch registrations enforce the observer bound and release only after SDK unregistration returns");
        live(id);return report();
    }
    static Size smallest(CameraCharacteristics ch,int format)throws Exception{Size[] sizes=ch.get(android.hardware.camera2.CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP).getOutputSizes(format);if(sizes==null||sizes.length==0)throw new IOException("Required fixture format is not advertised");Size best=sizes[0];for(Size s:sizes)if((long)s.getWidth()*s.getHeight()<(long)best.getWidth()*best.getHeight())best=s;return best;}
    void live(String id)throws Exception{
        String handle=open(id);HardwareCamera.Camera camera=VmHardware.handle(context,handle,HardwareCamera.Camera.class);java.lang.reflect.Method save=MainActivity.class.getDeclaredMethod("savePermission",String.class,Object.class);save.setAccessible(true);ExecutorService executor=Executors.newSingleThreadExecutor();Future<JSONObject> running=null;
        try{
            running=executor.submit(()->host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0)).put("source","fn main(){let i=0;while i<10000{device_wait("+q(handle)+",1000);i=i+1;}return 1;}").put("history",new JSONArray())));
            java.lang.reflect.Field active=VmHardware.class.getDeclaredField("active");active.setAccessible(true);boolean waiting=false;long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
            while(System.nanoTime()<end&&!waiting){Object operation=active.get(null);if(operation!=null){java.lang.reflect.Field io=operation.getClass().getDeclaredField("cancelIO");io.setAccessible(true);waiting=io.get(operation)!=null;}if(!waiting){if(running.isDone())throw new IOException("Camera VM exited before revocation: "+running.get());Thread.sleep(10);}}
            check(waiting,"the actual VM is waiting in camera I/O before conversation permission changes");ui(()->{try{save.invoke(host,"camera",false);}catch(Exception e){throw new RuntimeException(e);}});JSONObject stopped=running.get(4,TimeUnit.SECONDS);
            check(stopped.optString("state").equals("error")&&stopped.optString("stderr").toLowerCase(Locale.ROOT).contains("cancel"),"Camera Deny on the real UI thread cancels the already-running VM program");check(camera.closed&&!host.workerConfig(root,0).getJSONObject("permissions").optBoolean("camera"),"revocation invalidates the live camera and persists the changed policy");
            vm("fn main(){if camera_list(0,16){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"permission_denied\"){return 2;}return 0;}");check(true,"subsequent SDK inventory/capture access remains denied after live conversation revocation");until(()->cameraReleased(camera));
        }finally{if(running!=null&&!running.isDone()){VmHardware.cancel();running.cancel(true);}executor.shutdownNow();VmHardware.closeWorkspace(root);ui(()->{try{save.invoke(host,"camera",true);}catch(Exception e){throw new RuntimeException(e);}});}
    }
}
