package org.flexscript.collie;

import android.graphics.ImageFormat;
import android.hardware.camera2.*;
import android.hardware.camera2.params.*;
import android.media.*;
import android.util.Size;
import android.util.Rational;
import android.util.Pair;
import java.io.*;
import java.nio.*;
import java.nio.file.Files;
import java.util.*;
import java.util.concurrent.*;
import java.util.zip.Adler32;
import org.json.*;

/** Actual RAW/depth callbacks and independently parsed DNG bytes; no fake camera images. */
final class HardwareCameraRawChecks {
    final HardwareCameraChecks t;final String handle;final HardwareCamera.Camera camera;final JSONObject facts;
    HardwareCameraRawChecks(HardwareCameraChecks t,String h,HardwareCamera.Camera c){this.t=t;handle=h;camera=c;facts=t.rawDepth;}
    static void run(HardwareCameraChecks t,String h,HardwareCamera.Camera c)throws Exception{new HardwareCameraRawChecks(t,h,c).run();}
    static String q(String s){return HardwareCameraChecks.q(s);}
    void run()throws Exception{
        int[] formats=camera.ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP).getOutputFormats();
        facts.put("raw_advertised",contains(formats,ImageFormat.RAW_SENSOR)).put("depth16_advertised",contains(formats,ImageFormat.DEPTH16)).put("raw_capture_verified",false).put("depth_capture_verified",false).put("dng_verified",false).put("physical_accuracy_verified",false);
        for(int format:new int[]{ImageFormat.RAW_SENSOR,ImageFormat.DEPTH16})if(contains(formats,format)){
            Size[] sizes=camera.ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP).getOutputSizes(format);Size size=sizes[0];for(Size s:sizes)if((long)s.getWidth()*s.getHeight()<(long)size.getWidth()*size.getHeight())size=s;
            t.vm("fn main(){while db_kind(device_wait("+q(handle)+",0))!=0{}let o=db_list();db_add(o,camera_output("+format+","+size.getWidth()+","+size.getHeight()+"));if !camera_configure("+q(handle)+",o,10000){return 1;}let i=0;while i<20{let e=device_wait("+q(handle)+",1000);if db_kind(e)==5&&worker_equal(db_word(device_field(e,\"event\")),\"configured\"){return 0;}i=i+1;}return 2;}");
            capture(format==ImageFormat.RAW_SENSOR);String frameId=t.state("raw_frame"),resultId=t.state("raw_result");HardwareCamera.Frame frame=camera.frame(frameId);
            t.check(frame.image.getFormat()==format&&frame.image.getWidth()==size.getWidth()&&frame.image.getHeight()==size.getHeight(),"an actual SDK "+(format==ImageFormat.RAW_SENSOR?"RAW_SENSOR":"DEPTH16")+" capture delivers the exact advertised dimensions without JPEG substitution");
            t.verifyFramePlanes(handle,frameId,frame);t.check(true,"every actual "+format+" plane byte, stride and EOF agrees with independent SDK buffers through bounded VM pages");
            if(format==ImageFormat.RAW_SENSOR){facts.put("raw_capture_verified",true).put("raw_width",size.getWidth()).put("raw_height",size.getHeight());raw(frameId,resultId,frame);}
            else{facts.put("depth_capture_verified",true).put("depth_width",size.getWidth()).put("depth_height",size.getHeight());ByteBuffer b=frame.image.getPlanes()[0].getBuffer().duplicate().order(ByteOrder.LITTLE_ENDIAN);int sample=b.getShort(0)&65535,c=(sample>>13)&7,confidence=c==0?1000:(c-1)*1000/7;
                t.vm("fn main(){let r=camera_frame_read("+q(handle)+","+q(frameId)+",0,0,2);let p=db_word(device_field(r,\"value\"));let sample=load8(p)+256*load8(p+1);if sample!="+sample+"||camera_depth_mm(sample)!="+(sample&8191)+"||camera_depth_confidence(sample)!="+confidence+"{return 1;}return 0;}");
                t.check(true,"the real DEPTH16 sample retains its13-bit millimeter field and non-linear three-bit confidence through portable Flexscript helpers");
                t.vm("fn main(){let o=camera_dng_options(1,\"\",db_null(),30000);if camera_dng("+q(handle)+","+q(frameId)+","+q(resultId)+",o){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"unsupported_format\"){return 2;}return 0;}");
                t.check(true,"a real depth frame is rejected as a DNG source without reinterpreting its range bytes as Bayer data");
            }
            t.vm("fn main(){return db_word(camera_frame_close("+q(handle)+","+q(frameId)+"))-1;}");
        }
    }
    static boolean contains(int[] values,int selected){for(int value:values)if(value==selected)return true;return false;}
    void capture(boolean raw)throws Exception{
        int[] modes=camera.ch.get(CameraCharacteristics.STATISTICS_INFO_AVAILABLE_LENS_SHADING_MAP_MODES);String setting=raw&&modes!=null&&contains(modes,1)?"db_add(settings,camera_setting(\"android.statistics.lensShadingMapMode\",\"int\",db_int(1)));":"";
        t.vm("fn main(){let settings=db_list();"+setting+"if !camera_capture("+q(handle)+",2,settings,0){return 1;}let f=0;let r=0;let i=0;while i<30{let e=device_wait("+q(handle)+",1000);if db_kind(e)==5{if worker_equal(db_word(device_field(e,\"event\")),\"frame\"){f=device_field(e,\"frame\");}if worker_equal(db_word(device_field(e,\"event\")),\"capture_completed\"){r=device_field(e,\"result\");}if f&&r{state_set(\"raw_frame\",f);state_set(\"raw_result\",r);return 0;}}i=i+1;}return 2;}");
    }
    static JSONArray rational(Rational r)throws Exception{return new JSONArray().put(r.getNumerator()).put(r.getDenominator());}
    void metadata(CaptureResult r,String id)throws Exception{
        Rational[] neutral=r.get(CaptureResult.SENSOR_NEUTRAL_COLOR_POINT);if(neutral!=null){JSONArray a=new JSONArray();for(Rational v:neutral)a.put(rational(v));t.wirePage("camera_result_value("+q(handle)+","+q(id)+","+q(CaptureResult.SENSOR_NEUTRAL_COLOR_POINT.getName())+",0,32)",HardwareCameraChecks.expectedPage(a,a.length(),a.length(),null));}
        RggbChannelVector gains=r.get(CaptureResult.COLOR_CORRECTION_GAINS);if(gains!=null){JSONArray a=new JSONArray().put(VmHardware.real(gains.getRed())).put(VmHardware.real(gains.getGreenEven())).put(VmHardware.real(gains.getGreenOdd())).put(VmHardware.real(gains.getBlue()));t.wirePage("camera_result_value("+q(handle)+","+q(id)+","+q(CaptureResult.COLOR_CORRECTION_GAINS.getName())+",0,32)",VmHardware.object("value",a,"array",false,"total",1,"next",-1));}
        ColorSpaceTransform matrix=r.get(CaptureResult.COLOR_CORRECTION_TRANSFORM);if(matrix!=null){Rational[] copied=new Rational[9];matrix.copyElements(copied,0);JSONArray a=new JSONArray();for(Rational value:copied)a.put(rational(value));t.wirePage("camera_result_value("+q(handle)+","+q(id)+","+q(CaptureResult.COLOR_CORRECTION_TRANSFORM.getName())+",0,32)",VmHardware.object("value",a,"array",false,"total",1,"next",-1));}
        Pair<Double,Double>[] noise=r.get(CaptureResult.SENSOR_NOISE_PROFILE);if(noise!=null){JSONArray a=new JSONArray();for(Pair<Double,Double> pair:noise)a.put(new JSONArray().put(VmHardware.real(pair.first)).put(VmHardware.real(pair.second)));t.wirePage("camera_result_value("+q(handle)+","+q(id)+","+q(CaptureResult.SENSOR_NOISE_PROFILE.getName())+",0,32)",HardwareCameraChecks.expectedPage(a,a.length(),a.length(),null));}
        int verified=(neutral!=null?1:0)+(gains!=null?1:0)+(matrix!=null?1:0)+(noise!=null?1:0);
        facts.put("neutral_color_verified",neutral!=null).put("color_gains_verified",gains!=null).put("color_transform_verified",matrix!=null).put("noise_profile_verified",noise!=null).put("calibration_fields_verified",verified);
        if(verified>0)t.check(true,"the "+verified+" populated RAW calibration/noise/gain/transform fields match independent public SDK getters/copies across the VM");
        LensShadingMap shading=r.get(CaptureResult.STATISTICS_LENS_SHADING_CORRECTION_MAP);facts.put("lens_shading_verified",shading!=null);
        if(shading!=null){float[] copied=new float[shading.getGainFactorCount()];shading.copyGainFactors(copied,0);facts.put("lens_shading_gains_verified",copied.length);for(int offset=0;offset<copied.length;offset+=32){int end=Math.min(copied.length,offset+32);JSONArray a=new JSONArray();for(int i=offset;i<end;i++)a.put(VmHardware.real(copied[i]));t.wirePage("camera_result_value("+q(handle)+","+q(id)+","+q(CaptureResult.STATISTICS_LENS_SHADING_CORRECTION_MAP.getName())+","+offset+",32)",HardwareCameraChecks.expectedPage(a,copied.length,end,null));}t.check(true,"every actual lens-shading gain from the enabled RAW request matches an independent SDK copy through bounded metadata pages");}
    }
    void raw(String frameId,String resultId,HardwareCamera.Frame frame)throws Exception{
        TotalCaptureResult result=camera.results.get(resultId);t.check(result!=null&&result.get(CaptureResult.SENSOR_TIMESTAMP)==frame.timestamp,"the actual RAW image and retained result carry the same independent SDK sensor timestamp");
        metadata(result,resultId);
        capture(true);String second=t.state("raw_result");
        t.vm("fn main(){let o=camera_dng_options(6,\"Collie RAW sample\",db_null(),30000);if camera_dng("+q(handle)+","+q(frameId)+","+q(second)+",o){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}return 0;}");
        t.check(true,"a real RAW frame paired with a different actual result is rejected before DngCreator or a spool lease is allocated");
        t.vm("fn main(){let o=camera_dng_options(9,\"\",db_null(),30000);if camera_dng("+q(handle)+","+q(frameId)+","+q(resultId)+",o){return 1;}o=camera_dng_options(1,\"\",db_null(),499);if camera_dng("+q(handle)+","+q(frameId)+","+q(resultId)+",o){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 3;}return 0;}");
        synchronized(HardwareCameraDng.OWNED){t.check(HardwareCameraDng.OWNED.isEmpty(),"invalid DNG orientation/deadline values allocate no SDK export lease");}
        String file=t.vm("fn main(){let l=camera_dng_gps(db_int(12),db_int(-45),1700000000000);let o=camera_dng_options(6,\"Collie RAW sample\",l,30000);let h=camera_dng("+q(handle)+","+q(frameId)+","+q(resultId)+",o);if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");
        HardwareCameraDng.Export owned=VmHardware.handle(t.context,file,HardwareCameraDng.Export.class);
        try{
            t.vm("fn main(){let i=0;while i<40{let d=device_info("+q(file)+");if worker_equal(db_word(device_field(d,\"state\")),\"ready\"){if !db_word(device_field(d,\"sdk_released\")){return 1;}return 0;}if worker_equal(db_word(device_field(d,\"state\")),\"error\"){let e=device_field(d,\"error\");db_io(0,2,db_word(e),db_bytes(e));return 2;}device_wait("+q(file)+",1000);i=i+1;}return 3;}");
            byte[] bytes=Files.readAllBytes(owned.file.toPath());ExifInterface exif=new ExifInterface(owned.file.getAbsolutePath());
            t.check(exif.getAttributeInt(ExifInterface.TAG_IMAGE_WIDTH,0)==frame.width&&exif.getAttributeInt(ExifInterface.TAG_IMAGE_LENGTH,0)==frame.height&&exif.getAttributeInt(ExifInterface.TAG_ORIENTATION,0)==6,"Android's independent EXIF reader accepts the actual DNG with exact RAW dimensions and requested orientation");
            t.check("Collie RAW sample".equals(exif.getAttribute(ExifInterface.TAG_IMAGE_DESCRIPTION)),"the actual DNG preserves its requested description tag");
            float[] coordinates=new float[2];t.check(exif.getLatLong(coordinates)&&coordinates[0]==12&&coordinates[1]== -45&&exif.getGpsDateTime()==1700000000000L,"the DNG preserves caller-supplied GPS metadata without claiming a device Location measurement");
            validateTiff(bytes,frame);
            for(int offset=0;offset<bytes.length;offset+=32768){int n=Math.min(32768,bytes.length-offset);Adler32 crc=new Adler32();crc.update(bytes,offset,n);
                t.vm("fn main(){let b=device_read("+q(file)+",32768,1000);if db_bytes(b)!="+n+"{return 1;}let i=0;let a=1;let c=0;while i<"+n+"{a=(a+load8(db_word(b)+i))%65521;c=(c+a)%65521;i=i+1;}if ((c<<16)|a)!="+crc.getValue()+"{return 2;}return 0;}");
            }
            t.vm("fn main(){if db_kind(device_read("+q(file)+",1,1000))!=0{return 1;}if device_write("+q(file)+",db_blob(\"no\",2))||camera_dng_seek("+q(file)+","+(bytes.length+1)+"){return 2;}if db_word(camera_dng_seek("+q(file)+",0)){return 3;}let h=device_read("+q(file)+",4,1000);if db_bytes(h)!=4{return 4;}return 0;}");
            t.check(true,"every finalized DNG byte crosses VM read pages with independent length/Adler32 checks; EOF, seek bounds and read-only enforcement hold");
            File foreign=new File(t.root,"raw-foreign");new File(foreign,"files").mkdirs();t.vm(foreign,"fn main(){if camera_dng_seek("+q(file)+",0){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 2;}return 0;}");
            t.check(true,"another actual VM workspace cannot read or seek the owned DNG resource");
            t.vm("fn main(){let o=camera_dng_options(1,\"\",db_null(),30000);if camera_dng("+q(handle)+","+q(frameId)+","+q(resultId)+",o){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"resource_limit\"){return 2;}return 0;}");
            t.check(true,"the retained finalized file still owns the sole DNG copy/spool lease");
            facts.put("dng_verified",true).put("dng_bytes",bytes.length).put("dng_plane_bytes_verified",true);
        }finally{VmHardware.close(t.context,file);long end=android.os.SystemClock.elapsedRealtime()+5000;boolean released=false;while(!released&&android.os.SystemClock.elapsedRealtime()<end){synchronized(owned){released=owned.released;}if(!released)Thread.sleep(10);}t.check(released&&(owned.file==null||!owned.file.exists()),"actual DngCreator/file cleanup deletes the private spool and releases the export lease");}
        queued(frameId,resultId,0);queued(frameId,resultId,1);queued(t.state("raw_frame"),second,2);
        capture(true);streamClosed(t.state("raw_frame"),t.state("raw_result"));
    }
    void streamClosed(String frameId,String resultId)throws Exception{
        HardwareCamera.Frame frame=camera.frame(frameId);String id=null;HardwareCameraDng.Export owned=null;boolean reading=false;
        try{
            synchronized(frame){
                id=t.vm("fn main(){let h=camera_dng("+q(handle)+","+q(frameId)+","+q(resultId)+",camera_dng_options(1,\"\",db_null(),30000));if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");owned=VmHardware.handle(t.context,id,HardwareCameraDng.Export.class);
                long end=android.os.SystemClock.elapsedRealtime()+5000;
                while(!reading&&android.os.SystemClock.elapsedRealtime()<end){for(Map.Entry<Thread,StackTraceElement[]> thread:Thread.getAllStackTraces().entrySet())if(thread.getKey().getName().equals("collie-camera-dng"))for(StackTraceElement entry:thread.getValue())if(entry.getClassName().equals(HardwareCamera.Frame.class.getName())&&entry.getMethodName().equals("copy"))reading=true;if(!reading)Thread.sleep(10);}
                t.check(reading&&owned.sdkRequested,"the actual DngCreator input stream reaches the bounded SDK image-row copy before source invalidation");
                HardwareCamera.call(t.context,"camera_frame_close",new JSONArray().put(handle).put(frameId));
            }
        }finally{
            if(owned!=null){long end=android.os.SystemClock.elapsedRealtime()+5000;boolean released=false;while(!released&&android.os.SystemClock.elapsedRealtime()<end){synchronized(owned){released=owned.released;}if(!released)Thread.sleep(10);}
                try{t.vm("fn main(){let d=device_info("+q(id)+");if !worker_equal(db_word(device_field(d,\"state\")),\"error\")||!worker_equal(db_word(device_field(d,\"code\")),\"stale_frame\")||!db_word(device_field(d,\"sdk_requested\"))||!db_word(device_field(d,\"sdk_released\"))||!db_word(device_field(d,\"lease_released\")){return 1;}if device_read("+q(id)+",1,1000){return 2;}return 0;}");t.check(released&&owned.file!=null&&!owned.file.exists(),"closing the real Image during SDK DNG streaming preserves stale_frame through the I/O exception, publishes no partial container and settles SDK/file ownership");}
                finally{VmHardware.close(t.context,id);}
            }
        }
    }
    void queued(String frame,String result,int action)throws Exception{
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);String id=null;HardwareCameraDng.Export owned=null;
        HardwareCameraDng.SDK.execute(()->{entered.countDown();try{release.await(15,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}});
        try{
            if(!entered.await(5,TimeUnit.SECONDS))throw new IOException("DNG worker fixture did not block");
            id=t.vm("fn main(){let h=camera_dng("+q(handle)+","+q(frame)+","+q(result)+",camera_dng_options(1,\"\",db_null(),"+(action==1?500:30000)+"));if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");owned=VmHardware.handle(t.context,id,HardwareCameraDng.Export.class);
            if(action==1){while(android.os.SystemClock.elapsedRealtime()<owned.deadline+20)Thread.sleep(10);t.vm("fn main(){let d=device_info("+q(id)+");if !worker_equal(db_word(device_field(d,\"state\")),\"error\")||!worker_equal(db_word(device_field(d,\"code\")),\"timeout\")||db_word(device_field(d,\"lease_released\")){return 1;}return 0;}");t.check(!owned.sdkRequested,"elapsed expiry rejects a DNG job while the actual SDK worker is blocked, retaining its lease before SDK entry");}
            else if(action==2)t.vm("fn main(){return db_word(camera_frame_close("+q(handle)+","+q(frame)+"))-1;}");
            else{String closing=id;long start=android.os.SystemClock.elapsedRealtime();t.ui(()->{try{VmHardware.close(t.context,closing);}catch(Exception e){throw new RuntimeException(e);}});t.check(android.os.SystemClock.elapsedRealtime()-start<1000,"closing a queued DNG on the real UI thread does not wait for the blocked SDK worker");synchronized(HardwareCameraDng.OWNED){t.check(HardwareCameraDng.OWNED.contains(owned),"local DNG close retains the export reservation until its submitted worker actually settles");}}
        }finally{
            release.countDown();if(owned!=null){long end=android.os.SystemClock.elapsedRealtime()+5000;boolean done=false;while(!done&&android.os.SystemClock.elapsedRealtime()<end){synchronized(owned){done=owned.released;}if(!done)Thread.sleep(10);}t.check(done&&!owned.sdkRequested&&owned.file==null,"the late queued DNG task performs no SDK write or spool creation and releases only after actual settlement");if(action==2)t.check("stale_frame".equals(owned.errorCode),"closing the actual source Image before queued export starts rejects stale_frame before DngCreator entry");if(!owned.closed)VmHardware.close(t.context,id);}
        }
    }
    void validateTiff(byte[] bytes,HardwareCamera.Frame frame)throws Exception{
        ByteBuffer b=ByteBuffer.wrap(bytes);if(bytes.length<8)throw new IOException("Short DNG");boolean little=bytes[0]=='I'&&bytes[1]=='I';if(!little&&!(bytes[0]=='M'&&bytes[1]=='M'))throw new IOException("Invalid TIFF byte order");b.order(little?ByteOrder.LITTLE_ENDIAN:ByteOrder.BIG_ENDIAN);if((b.getShort(2)&65535)!=42)throw new IOException("Invalid TIFF magic");
        int ifd=b.getInt(4),count=b.getShort(ifd)&65535;Map<Integer,int[]> entries=new HashMap<>();
        for(int i=0;i<count;i++){int at=ifd+2+i*12;entries.put(b.getShort(at)&65535,new int[]{b.getShort(at+2)&65535,b.getInt(at+4),at+8});}
        int[] offsets=values(b,entries.get(273)),lengths=values(b,entries.get(279));int compression=values(b,entries.get(259))[0];if(compression!=1||offsets.length!=lengths.length)throw new IOException("Unsupported DNG strip layout");
        ByteArrayOutputStream pixels=new ByteArrayOutputStream();for(int i=0;i<offsets.length;i++){if(offsets[i]<0||lengths[i]<0||offsets[i]>bytes.length-lengths[i])throw new IOException("Invalid DNG strip bounds");pixels.write(bytes,offsets[i],lengths[i]);}
        byte[] packed=pixels.toByteArray();if(packed.length!=frame.width*frame.height*2)throw new IOException("DNG pixel length differs");Image.Plane plane=frame.image.getPlanes()[0];ByteBuffer source=plane.getBuffer().duplicate();int row=plane.getRowStride();for(int y=0;y<frame.height;y++)for(int x=0;x<frame.width*2;x++)if(packed[y*frame.width*2+x]!=source.get(y*row+x))throw new IOException("DNG raw pixel mismatch");
        t.check(true,"an independent TIFF strip parser validates uncompressed DNG pixels against every actual SDK RAW row, excluding source padding");
    }
    static int[] values(ByteBuffer b,int[] entry)throws Exception{if(entry==null||entry[1]<1||entry[1]>100000)throw new IOException("Missing/oversized TIFF field");int size=entry[0]==3?2:entry[0]==4?4:0;if(size==0)throw new IOException("Unsupported TIFF integer type");int at=entry[1]*size<=4?entry[2]:b.getInt(entry[2]);int[] out=new int[entry[1]];for(int i=0;i<out.length;i++)out[i]=size==2?b.getShort(at+i*2)&65535:b.getInt(at+i*4);return out;}
}
