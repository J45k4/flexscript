package org.flexscript.collie;

import android.hardware.*;
import android.os.*;
import java.io.*;
import java.util.*;
import java.nio.*;
import org.json.*;

/** Real SDK allocations and VM calls; constructed canaries are not HAL samples. */
public final class HardwareSensorDirectChecks {
    static { System.loadLibrary("collie_sensor_fixture"); }
    private static native int fill(HardwareBuffer buffer);
    final HardwareInputChecks h;final JSONArray checks=new JSONArray(),backings=new JSONArray();
    HardwareSensorDirectChecks(HardwareInputChecks h){this.h=h;}
    void check(boolean okay,String text)throws Exception{if(!okay)throw new IOException(text);checks.put(text);}
    static String q(String value){return JSONObject.quote(value);}
    int leases()throws Exception{java.lang.reflect.Field f=HardwareSensorDirect.class.getDeclaredField("LEASES");f.setAccessible(true);Set<?> values=(Set<?>)f.get(null);synchronized(values){return values.size();}}
    void idle()throws Exception{long end=SystemClock.elapsedRealtime()+3000;while(leases()!=0&&SystemClock.elapsedRealtime()<end)Thread.sleep(10);check(leases()==0,"all actual direct-sensor leases/backings finish cleanup, including failed SDK opens");}
    void expectReadFailure(HardwareBuffer buffer,int offset,int count)throws Exception{try{HardwareSensorDirect.readBuffer(buffer,offset,count);throw new AssertionError("Invalid native buffer read succeeded");}catch(IOException expected){check(true,"native CPU copy rejects invalid backing or bounds");}}
    void memory(int type)throws Exception {
        try(HardwareSensorDirect.Memory memory=new HardwareSensorDirect.Memory(type,320*104)){
            if(type==1){byte[] pattern=new byte[320*104];for(int i=0;i<pattern.length;i++)pattern[i]=(byte)(i*17+128);memory.file.writeBytes(pattern,0,0,pattern.length);byte[] page=memory.read(104,32760);for(int i=0;i<page.length;i++)if(page[i]!=pattern[i+104])throw new IOException("MemoryFile binary copy changed byte"+i);check(true,"real MemoryFile public write/read preserves nonzero binary canaries over a maximum page");}
            else{check(memory.buffer.getWidth()==320*104&&memory.buffer.getHeight()==1&&memory.buffer.getLayers()==1&&memory.buffer.getFormat()==HardwareBuffer.BLOB&&(memory.buffer.getUsage()&HardwareBuffer.USAGE_SENSOR_DIRECT_DATA)!=0,"production HardwareBuffer allocation has actual public sensor BLOB dimensions and usage");check(memory.read(104,32760).length==32760,"the production read bridge locks and copies an actual sensor HardwareBuffer at the maximum page bound");}
            boolean bounds=false;try{memory.read(320*104-1,2);}catch(IOException expected){bounds=true;}check(bounds,"the actual backing abstraction rejects a read across its allocation boundary");
            if(type==2)expectReadFailure(memory.buffer,320*104-1,2);
        }
    }
    void nativeMemory()throws Exception {
            try(HardwareBuffer buffer=HardwareBuffer.create(320*104,1,HardwareBuffer.BLOB,1,HardwareBuffer.USAGE_CPU_READ_OFTEN|HardwareBuffer.USAGE_CPU_WRITE_OFTEN)){
                check(fill(buffer)==0,"a separate debug-only native writer fills an actual SDK-constructed HardwareBuffer; these bytes are not sensor reports");
                byte[] page=HardwareSensorDirect.readBuffer(buffer,104,32760);for(int i=0;i<page.length;i++)if((page[i]&255)!=((i+104)*17+128)%256)throw new IOException("HardwareBuffer binary copy changed byte"+i);
                check(true,"the production JNI read bridge independently preserves every nonzero binary canary byte in a generic CPU BLOB; this does not prove SENSOR_DIRECT_DATA allocation support");
                expectReadFailure(buffer,-1,104);expectReadFailure(buffer,0,32769);expectReadFailure(buffer,Integer.MAX_VALUE,1);
            }
            try(HardwareBuffer image=HardwareBuffer.create(2,2,HardwareBuffer.RGBA_8888,1,HardwareBuffer.USAGE_CPU_READ_OFTEN)){expectReadFailure(image,0,4);}
    }
    void codec()throws Exception {
        h.vm("fn main(){let p=alloc(104);let i=0;while i<104{store8(p+i,0);i=i+1;}store64(p,104|(7<<32));store64(p+8,1|(4294967295<<32));store64(p+16,123456789);store64(p+24,0xc1480000);let rows=sensor_direct_records(db_blob(p,104));let r=db_at(rows,0);if db_count(rows)!=1||db_word(db_at(r,0))!=7||db_word(db_at(r,2))!=4294967295||db_word(db_at(r,3))!=123456789{return 1;}if db_word(sensor_direct_f32(db_at(r,4),0))!=0xc029000000000000{return 2;}if db_word(sensor_direct_i64(db_at(r,4),0))!=0xc1480000||sensor_direct_counter_distance(1,4294967295)!=1{return 3;}store8(p+103,1);if sensor_direct_records(db_blob(p,104)){return 4;}return 0;}");
        check(true,"preloaded portable helpers decode a constructed raw ABI record inside the actual Android VM, including exact f32 bits and unsigned counter wrap");
    }
    void backing(int type)throws Exception {
        String kind=type==1?"memory_file":"hardware_buffer";boolean allocated=true;String allocationError="";
        if(type==2)nativeMemory();
        try{memory(type);}catch(IllegalArgumentException|UnsupportedOperationException error){if(type!=2)throw error;allocated=false;allocationError=error.getClass().getName()+": "+error.getMessage();}
        SensorManager manager=HardwareSensors.manager(h.context);boolean sdkOpened=false;String sdkError="";int supported=0;
        Sensor selected=null;for(Sensor sensor:HardwareSensors.sensors(h.context))if(sensor.isDirectChannelTypeSupported(type)){supported++;if(sensor.getHighestDirectReportRateLevel()>=1&&(selected==null||sensor.getType()==Sensor.TYPE_ACCELEROMETER))selected=sensor;}
        boolean sdkReporting=false;
        boolean independentAllocated=false;
        try{
            // Allocate independently, without Collie's backing constructor, so
            // an adapter allocation defect cannot manufacture unsupportedness.
            MemoryFile file=type==1?new MemoryFile("Independent sensor oracle",320*104):null;
            HardwareBuffer buffer=type==2?HardwareBuffer.create(320*104,1,HardwareBuffer.BLOB,1,HardwareBuffer.USAGE_CPU_READ_OFTEN|HardwareBuffer.USAGE_SENSOR_DIRECT_DATA):null;
            independentAllocated=true;
            SensorDirectChannel channel=null;try{
                channel=type==1?manager.createDirectChannel(file):manager.createDirectChannel(buffer);sdkOpened=channel!=null&&channel.isOpen();
                if(sdkOpened&&selected!=null){int token=channel.configure(selected,SensorDirectChannel.RATE_NORMAL);check(token>0,"independent SDK starts a genuinely advertised direct report");Thread.sleep(350);channel.close();channel=null;byte[] data=new byte[32760];if(type==1)check(file.readBytes(data,0,0,data.length)==data.length,"independent MemoryFile oracle returns a complete raw page");else data=HardwareSensorDirect.readBuffer(buffer,0,data.length);ByteBuffer page=ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN);for(int at=0;at<data.length;at+=104)if(page.getInt(at)==104&&page.getInt(at+4)==token&&page.getInt(at+8)==selected.getType()&&page.getInt(at+12)!=0&&page.getLong(at+16)>0)sdkReporting=true;check(sdkReporting,"independent SDK receives a real token/type/counter/timestamp record after stopping its producer");}
            }catch(RuntimeException error){if(sdkOpened)throw error;sdkError=error.getClass().getName()+": "+error.getMessage();}finally{try{if(channel!=null)channel.close();}finally{if(file!=null)file.close();if(buffer!=null)buffer.close();}}
        }catch(IllegalArgumentException|UnsupportedOperationException error){if(independentAllocated||type!=2)throw error;sdkError=error.getClass().getName()+": "+error.getMessage();}
        check(allocated==independentAllocated,"production backing allocation agrees with a separate public SDK allocation using only required flags for"+kind);
        if(supported>0)check(sdkOpened&&sdkReporting,"advertised direct support must produce a real SDK channel and report; refusal cannot become a passing unsupported branch");
        JSONObject proof=new JSONObject().put("memory_type",kind).put("sdk_memory_backing_verified",allocated).put("independent_sdk_memory_allocated",independentAllocated).put("allocation_error",allocationError).put("independent_sdk_channel_created",sdkOpened).put("advertised_sensors",supported).put("independent_sdk_error",sdkError).put("sdk_direct_reporting_verified",sdkReporting).put("vm_direct_reporting_verified",false).put("physical_direct_reporting_verified",false);backings.put(proof);
        JSONObject result=h.vm("fn main(){let h=sensor_direct_open("+q(kind)+",320);if !h{db_io(0,1,\"refused\",7);return 0;}db_io(0,1,db_word(h),db_bytes(h));return 0;}");String id=result.getString("stdout");
        if(!sdkOpened){check(id.equals("refused"),"the VM reports a genuine SDK channel-open failure consistently with a separate public SDK call for"+kind);idle();return;}
        check(id.startsWith("device-"),"a real VM opens the same backing accepted by an independent SDK channel for"+kind);
        try{
            h.vm("fn main(){let h="+q(id)+";let info=device_info(h);if !worker_equal(db_word(device_field(info,\"memory_type\")),"+q(kind)+")||db_word(device_field(info,\"slots\"))!=320||db_word(device_field(info,\"record_bytes\"))!=104{return 1;}let page=sensor_direct_read(h,1,315);let bytes=device_field(page,\"data\");if db_bytes(bytes)!=32760||db_word(device_field(page,\"frozen\"))||db_count(sensor_direct_records(bytes))!=315{return 2;}return 0;}");
            check(true,"real direct-channel metadata and a315-record zero-initialized page cross the VM boundary for"+kind);
            if(selected!=null){
                h.vm("fn main(){let token=sensor_direct_configure("+q(id)+","+q(HardwareSensors.id(selected))+",1);if !token||db_word(token)<1{return 1;}return state_set(\"direct-token\",token)-1;}");Thread.sleep(350);
                h.vm("fn main(){let h="+q(id)+";if !sensor_direct_freeze(h){return 1;}let info=device_info(h);if db_count(device_field(info,\"reports\"))||db_count(device_field(info,\"tokens\"))!=1{return 2;}let token=db_word(state_get(\"direct-token\"));let rows=sensor_direct_records(device_field(sensor_direct_read(h,0,315),\"data\"));let i=0;let matched=0;while i<db_count(rows){let r=db_at(rows,i);if db_kind(r)==5&&db_word(db_at(r,0))==token&&db_word(db_at(r,1))=="+selected.getType()+"&&db_word(db_at(r,2))>0&&db_word(db_at(r,3))>0{matched=1;}i=i+1;}if !matched{return 3;}return 0;}");
                check(true,"an advertised sensor writes real shared-memory records with the SDK report token inside the actual VM, and frozen token mappings survive producer close");proof.put("vm_direct_reporting_verified",true);
            }
            File foreign=new File(h.root,"direct-foreign");new File(foreign,"files").mkdirs();
            try{h.vm(foreign,"fn main(){if sensor_direct_read("+q(id)+",0,1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 2;}return 0;}");check(true,"a different VM workspace cannot read the owned direct capture");}finally{VmHardware.closeWorkspace(foreign);}
            h.vm("fn main(){let h="+q(id)+";if sensor_direct_read(h,319,2){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}if sensor_direct_read(h,0,316){return 3;}if !device_info(h){return 4;}if !db_word(device_field(device_info(h),\"frozen\")){if !sensor_direct_stop(h){return 5;}}if !sensor_direct_freeze(h)||!sensor_direct_freeze(h){return 6;}let p=sensor_direct_read(h,319,1);if !db_word(device_field(p,\"frozen\"))||db_count(sensor_direct_records(device_field(p,\"data\")))!=1{return 7;}if sensor_direct_stop(h){return 8;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_state\"){return 9;}return 0;}");
            check(true,"bounds preserve the handle, stop calls the SDK, freeze retains readable memory after channel.close, and freezing is idempotent for"+kind);
            Sensor sensor=manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
            h.vm("fn main(){if sensor_direct_configure("+q(id)+","+q(HardwareSensors.id(sensor))+",1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_state\"){return 2;}return 0;}");check(true,"a frozen capture cannot restart reporting under the same handle");
        }finally{try{VmHardware.close(h.context,id);}catch(VmHardware.Failure stale){}}idle();
    }
    JSONObject run()throws Exception {
        idle();codec();
        h.vm("fn main(){if sensor_direct_open(\"invalid\",16){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}if sensor_direct_open(\"memory_file\",0){return 3;}if sensor_direct_open(\"memory_file\",4097){return 4;}return 0;}");check(true,"guest direct-open names and allocation bounds are validated");
        try{backing(1);backing(2);}finally{VmHardware.closeWorkspace(h.root);}idle();
        try{h.ui(()->{try{h.host.savePermission("sensors",false);}catch(Exception e){throw new RuntimeException(e);}});h.vm("fn main(){if sensor_direct_open(\"memory_file\",16){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"permission_denied\"){return 2;}if sensor_direct_open(\"hardware_buffer\",16){return 3;}return 0;}");check(true,"real Sensors denial blocks both direct-channel allocation paths before any SDK memory lease is acquired");idle();}
        finally{h.ui(()->{try{h.host.savePermission("sensors",true);}catch(Exception e){throw new RuntimeException(e);}});}
        return new JSONObject().put("ok",true).put("checks",checks).put("count",checks.length()).put("backings",backings).put("constructed_memory_canaries",true).put("physical_devices_verified",false);
    }
}
