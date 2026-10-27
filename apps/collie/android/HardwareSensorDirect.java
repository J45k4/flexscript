package org.flexscript.collie;

import android.hardware.*;
import android.os.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Public direct channels. The guest receives copied bytes, never native addresses. */
final class HardwareSensorDirect {
    static final int RECORD_BYTES=104, MAX_SLOTS=4096, MAX_CHANNELS=8;
    private static final Set<Direct> LEASES=new LinkedHashSet<>();
    private static final ThreadPoolExecutor CLEANUP=new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,
        new ArrayBlockingQueue<Runnable>(MAX_CHANNELS),task->{Thread t=new Thread(task,"collie-sensor-direct-close");t.setDaemon(true);return t;});
    private static final class Native {
        static { System.loadLibrary("collie_hardware"); }
        static native byte[] read(HardwareBuffer buffer,int offset,int bytes)throws IOException;
    }
    static byte[] readBuffer(HardwareBuffer buffer,int offset,int bytes)throws IOException{return Native.read(buffer,offset,bytes);}
    static final class Memory implements Closeable {
        final int type,bytes;
        MemoryFile file;HardwareBuffer buffer;
        Memory(int type,int bytes)throws IOException {
            this.type=type;this.bytes=bytes;
            if((type!=1&&type!=2)||bytes<RECORD_BYTES||bytes>MAX_SLOTS*RECORD_BYTES||bytes%RECORD_BYTES!=0)throw new VmHardware.Failure("invalid_argument","Invalid direct-sensor backing allocation.");
            if(type==SensorDirectChannel.TYPE_MEMORY_FILE)file=new MemoryFile("Collie sensor capture",bytes);
            else buffer=HardwareBuffer.create(bytes,1,HardwareBuffer.BLOB,1,
                HardwareBuffer.USAGE_CPU_READ_OFTEN|HardwareBuffer.USAGE_SENSOR_DIRECT_DATA);
        }
        SensorDirectChannel channel(SensorManager manager){return file!=null?manager.createDirectChannel(file):manager.createDirectChannel(buffer);}
        byte[] read(int offset,int count)throws IOException {
            if(offset<0||count<0||count>VmHardware.MAX_BYTES||offset>bytes-count)throw new VmHardware.Failure("invalid_argument","Sensor memory read exceeds its backing or32KiB copy bound.");
            if(type==SensorDirectChannel.TYPE_MEMORY_FILE){if(file==null)throw new IOException("Sensor memory is closed.");byte[] result=new byte[count];if(file.readBytes(result,offset,0,count)!=count)throw new IOException("Sensor memory returned a short read.");return result;}
            if(buffer==null)throw new IOException("Sensor buffer is closed.");return readBuffer(buffer,offset,count);
        }
        public void close(){if(file!=null){file.close();file=null;}if(buffer!=null){buffer.close();buffer=null;}}
    }
    static final class Report {
        final Sensor sensor;final int token,rate;
        Report(Sensor sensor,int token,int rate){this.sensor=sensor;this.token=token;this.rate=rate;}
    }
    static final class Direct extends VmHardware.Handle {
        final VmHardware.Context context;final SensorManager manager;final int type,slots;
        final Map<String,Report> reports=new LinkedHashMap<>();
        final Map<Integer,Report> tokens=new LinkedHashMap<>();
        final SensorManager.DynamicSensorCallback dynamic;
        Memory memory;SensorDirectChannel channel;
        boolean inFlight=true,cleanupQueued,registered,frozen,released;
        String cleanupError="";
        Direct(VmHardware.Context c,int type,int slots)throws Exception {
            super(c,"sensors","sensor_direct");context=c;manager=HardwareSensors.manager(c);this.type=type;this.slots=slots;
            dynamic=new SensorManager.DynamicSensorCallback(){public void onDynamicSensorDisconnected(Sensor sensor){boolean found;synchronized(Direct.this){found=reports.containsKey(HardwareSensors.id(sensor));}if(found)close();}};
            synchronized(LEASES){for(Direct old:LEASES)old.retryCleanup();if(LEASES.size()>=MAX_CHANNELS)throw new VmHardware.Failure("resource_limit","At most8 direct-sensor channels, including pending cleanup, may be owned by Collie.");LEASES.add(this);}
            VmHardware.blocking(this);
            try {
                VmHardware.check();memory=new Memory(type,slots*RECORD_BYTES);check();
                channel=memory.channel(manager);if(channel==null||!channel.isOpen())throw new VmHardware.Failure("unavailable","Android did not open a direct-sensor channel.");
                check();if(manager.isDynamicSensorDiscoverySupported()){registered=true;manager.registerDynamicSensorCallback(dynamic,HardwareSensors.events());}check();
            }catch(Exception|LinkageError error){close();throw error;}
            finally{end();VmHardware.unblocking();}
        }
        synchronized void begin()throws Exception{check();if(inFlight)throw new VmHardware.Failure("busy","Another operation is using this direct-sensor channel.");inFlight=true;}
        synchronized void end(){inFlight=false;if(closed)queueCleanup();}
        synchronized void retryCleanup(){if(closed&&!released&&!inFlight&&!cleanupQueued)queueCleanup();}
        private synchronized void queueCleanup(){
            if(released||inFlight||cleanupQueued)return;cleanupQueued=true;
            try{CLEANUP.execute(this::cleanup);}catch(RejectedExecutionException error){cleanupQueued=false;cleanupError=MainActivity.safe(error);}
        }
        private void cleanup(){
            synchronized(this){if(released){cleanupQueued=false;return;}inFlight=true;}
            boolean complete=false;
            try {
                if(channel!=null){channel.close();channel=null;}
                if(registered){manager.unregisterDynamicSensorCallback(dynamic);registered=false;}
                if(memory!=null){memory.close();memory=null;}
                complete=true;
            }catch(Exception|LinkageError error){synchronized(this){cleanupError=MainActivity.safe(error);}}
            finally{
                synchronized(this){inFlight=false;cleanupQueued=false;if(complete){released=true;reports.clear();tokens.clear();cleanupError="";}}
                if(complete)synchronized(LEASES){LEASES.remove(this);}
            }
        }
        void access(VmHardware.Context c)throws Exception {
            super.access(c);boolean revoked=false;synchronized(this){for(Report report:tokens.values())if(!HardwareSensors.granted(c,report.sensor)){revoked=true;break;}}
            if(revoked){close();throw new VmHardware.Failure("permission_revoked","A direct sensor's Android permission was revoked. Reopen after granting access.");}
        }
        int configure(Sensor sensor,int rate)throws Exception {
            begin();try {
                if(frozen)throw new VmHardware.Failure("invalid_state","A frozen direct capture cannot restart; open a new channel.");
                String id=HardwareSensors.id(sensor);
                if(rate!=SensorDirectChannel.RATE_STOP){
                    if(!sensor.isDirectChannelTypeSupported(type)||rate>sensor.getHighestDirectReportRateLevel())throw new VmHardware.Failure("unsupported_operation","The selected sensor does not advertise this backing type and rate.");
                    synchronized(this){if(!reports.containsKey(id)&&reports.size()>=64)throw new VmHardware.Failure("resource_limit","A direct channel may contain at most64 sensor reports.");}
                    synchronized(this){if(tokens.size()>=64)throw new VmHardware.Failure("resource_limit","This capture has reached64 token mappings; freeze and open a new capture.");}
                }
                int token=channel.configure(sensor,rate);
                if(token<=0){close();throw new VmHardware.Failure("unavailable","Android refused the direct-sensor configuration; the channel was retired.");}
                synchronized(this){if(rate==0)reports.remove(id);else{Report report=new Report(sensor,token,rate);reports.put(id,report);tokens.put(token,report);}}
                check();return token;
            }catch(RuntimeException error){close();throw error;}finally{end();}
        }
        int stop()throws Exception {
            begin();try{if(frozen)throw new VmHardware.Failure("invalid_state","This direct capture is already frozen.");int result=channel.configure(null,SensorDirectChannel.RATE_STOP);if(result!=1){close();throw new VmHardware.Failure("unavailable","Android did not stop every direct report; the channel was retired.");}synchronized(this){reports.clear();}check();return result;}
            catch(RuntimeException error){close();throw error;}finally{end();}
        }
        int freeze()throws Exception {
            begin();try{if(!frozen){channel.close();channel=null;synchronized(this){frozen=true;reports.clear();}}check();return 1;}
            catch(RuntimeException error){close();throw error;}finally{end();}
        }
        Object page(int offset,int count)throws Exception {
            if(offset>slots-count)throw new VmHardware.Failure("invalid_argument","Direct-sensor page runs past the capture slots.");
            begin();try{byte[] data=memory.read(offset*RECORD_BYTES,count*RECORD_BYTES);check();return VmHardware.object("offset",offset,"count",count,"slots",slots,"record_bytes",RECORD_BYTES,"frozen",frozen,"data",VmHardware.bytes(data));}
            catch(IOException|RuntimeException|LinkageError error){close();throw error;}finally{end();}
        }
        synchronized Object info()throws Exception {
            check();JSONArray configured=new JSONArray();for(Map.Entry<String,Report> entry:reports.entrySet()){Report report=entry.getValue();configured.put(VmHardware.object("sensor",entry.getKey(),"token",report.token,"rate",report.rate));}
            JSONArray history=new JSONArray();for(Report report:tokens.values())history.put(VmHardware.object("sensor",HardwareSensors.id(report.sensor),"type",report.sensor.getType(),"token",report.token));
            return VmHardware.object("kind",kind,"memory_type",type==1?"memory_file":"hardware_buffer","slots",slots,"bytes",slots*RECORD_BYTES,"record_bytes",RECORD_BYTES,"frozen",frozen,"in_flight",inFlight,"reports",configured,"tokens",history);
        }
        public synchronized void close(){if(closed)return;try{super.close();}catch(IOException impossible){throw new IllegalStateException(impossible);}queueCleanup();}
    }
    static boolean supports(String op){return op.equals("sensor_direct_open")||op.equals("sensor_direct_configure")||op.equals("sensor_direct_stop")||op.equals("sensor_direct_freeze")||op.equals("sensor_direct_read");}
    static Object call(VmHardware.Context c,String op,JSONArray args)throws Exception {
        if(op.equals("sensor_direct_open")){
            String kind=VmHardware.text(args,0,32);int type=kind.equals("memory_file")?1:kind.equals("hardware_buffer")?2:0;
            if(type==0)throw new VmHardware.Failure("invalid_argument","Direct sensor backing must be memory_file or hardware_buffer.");
            return VmHardware.add(new Direct(c,type,VmHardware.integer(args,1,1,MAX_SLOTS)));
        }
        Direct direct=VmHardware.handle(c,VmHardware.text(args,0,128),Direct.class);direct.access(c);VmHardware.blocking(direct);
        try {
            if(op.equals("sensor_direct_configure")){Sensor sensor=HardwareSensors.sensor(c,VmHardware.text(args,1,128));int rate=VmHardware.integer(args,2,0,3);if(rate!=0)HardwareSensors.permission(c,sensor);return direct.configure(sensor,rate);}
            if(op.equals("sensor_direct_stop"))return direct.stop();
            if(op.equals("sensor_direct_freeze"))return direct.freeze();
            return direct.page(VmHardware.integer(args,1,0,MAX_SLOTS),VmHardware.integer(args,2,1,315));
        }finally{VmHardware.unblocking();}
    }
}
