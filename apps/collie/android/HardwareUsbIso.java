package org.flexscript.collie;

import android.hardware.usb.*;
import android.os.SystemClock;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Owned asynchronous USBFS ISO requests. Packet/result decoding stays in Flexscript. */
final class HardwareUsbIso {
    static final int MAX_PACKETS=128,MAX_BYTES=24576;
    private static final Semaphore SLOTS=new Semaphore(8);
    static int availableSlots(){return SLOTS.availablePermits();}
    private static final Set<Transfer> LEASES=new LinkedHashSet<>();
    private static final ThreadPoolExecutor WORKERS=workers();
    private static ThreadPoolExecutor workers(){ThreadPoolExecutor p=new ThreadPoolExecutor(4,4,30,TimeUnit.SECONDS,new ArrayBlockingQueue<Runnable>(8),r->{Thread t=new Thread(r,"collie-usb-iso");t.setDaemon(true);return t;});p.allowCoreThreadTimeOut(true);return p;}
    private static final ScheduledThreadPoolExecutor TIMERS=timers();
    static int maximumPayload(int config,int number,int alternate,int address,int maximum,byte[] raw)throws Exception{
        int packet=(maximum&2047)*(1+((maximum>>11)&3));if(packet<1)throw new VmHardware.Failure("invalid_response","ISO endpoint has no usable packet payload.");if(raw==null)return packet;if(raw.length>262144)throw new VmHardware.Failure("size_limit","USB descriptors exceed the bounded ISO metadata parser.");int selectedConfig=-1,selectedInterface=-1,selectedAlternate=-1;boolean endpoint=false;
        for(int i=0;i<raw.length;){if(raw.length-i<2)throw new VmHardware.Failure("invalid_response","Incomplete USB descriptor header.");int length=raw[i]&255,type=raw[i+1]&255;if(length<2||length>raw.length-i)throw new VmHardware.Failure("invalid_response","Invalid USB descriptor length.");
            if(endpoint){if(type!=48)return packet;if(length<6)throw new VmHardware.Failure("invalid_response","Incomplete SuperSpeed endpoint companion.");int burst=raw[i+2]&255,mult=raw[i+3]&3,bytes=(raw[i+4]&255)|((raw[i+5]&255)<<8);if(burst>15||mult>2||bytes<1||bytes>(maximum&2047)*(burst+1)*(mult+1))throw new VmHardware.Failure("invalid_response","Invalid SuperSpeed ISO service-interval payload.");return bytes;}
            if(type==2){if(length<9)throw new VmHardware.Failure("invalid_response","Incomplete USB configuration descriptor.");selectedConfig=raw[i+5]&255;selectedInterface=selectedAlternate=-1;}
            else if(type==4){if(length<9)throw new VmHardware.Failure("invalid_response","Incomplete USB interface descriptor.");selectedInterface=raw[i+2]&255;selectedAlternate=raw[i+3]&255;}
            else if(type==5&&selectedConfig==config&&selectedInterface==number&&selectedAlternate==alternate){if(length<7)throw new VmHardware.Failure("invalid_response","Incomplete USB endpoint descriptor.");endpoint=(raw[i+2]&255)==address;}
            i+=length;
        }return packet;
    }
    private static ScheduledThreadPoolExecutor timers(){ScheduledThreadPoolExecutor p=new ScheduledThreadPoolExecutor(1,r->{Thread t=new Thread(r,"collie-usb-iso-deadline");t.setDaemon(true);return t;});p.setRemoveOnCancelPolicy(true);p.setKeepAliveTime(30,TimeUnit.SECONDS);p.allowCoreThreadTimeOut(true);return p;}
    private static final class Native {
        static {System.loadLibrary("collie_hardware");}
        static native long create(int fd,int endpoint,int[] lengths,byte[] data)throws IOException;
        static native byte[] run(long id,long deadline)throws IOException;
        static native void cancel(long id);
        static native boolean retireRequired(long id);
        static native boolean runFinished(long id);
        static native void destroy(long id,boolean sdkClosed)throws IOException;
    }
    static final class Transfer extends VmHardware.Handle {
        final HardwareUsb.Device parent;final int endpoint,packets,requested;final long deadline;
        volatile long nativeId;boolean scheduled,running,runFinished,settled,cleanupRunning,retryQueued,cancelRequested,expired;byte[] frame;JSONObject error,cleanupError;ScheduledFuture<?> timer;
        Transfer(VmHardware.Context c,HardwareUsb.Device parent,int endpoint,int packets,int requested,int timeout){super(c,"usb","usb_iso_transfer");this.parent=parent;this.endpoint=endpoint;this.packets=packets;this.requested=requested;deadline=SystemClock.elapsedRealtimeNanos()+timeout*1000000L;}
        void allocate(int fd,int[] sizes,byte[] data)throws Exception{try{nativeId=Native.create(fd,endpoint,sizes,data);}catch(LinkageError e){throw new IOException("The packaged native USB ISO adapter is unavailable.",e);}synchronized(this){if(cancelRequested||closed)Native.cancel(nativeId);}}
        void start(){
            synchronized(this){if(scheduled)return;scheduled=true;if(nativeId!=0)timer=TIMERS.schedule(()->{synchronized(this){if(runFinished||settled||Native.runFinished(nativeId))return;expired=true;cancelRequested=true;try{error=VmHardware.object("code","timeout","message","USB ISO deadline expired; the original native call and teardown may still be pending. No transfer is replayed.");}catch(Exception ignored){}event("deadline");}Native.cancel(nativeId);},Math.max(0,deadline-SystemClock.elapsedRealtimeNanos()),TimeUnit.NANOSECONDS);else runFinished=true;}if(nativeId==0){cleanup();return;}
            try{WORKERS.execute(()->{
                synchronized(this){running=true;}
                try{byte[] actual=Native.run(nativeId,deadline);synchronized(this){frame=actual;expired=(actual[12]&8)!=0;error=null;int number=(actual[16]&255)|((actual[17]&255)<<8)|((actual[18]&255)<<16)|((actual[19]&255)<<24);if(expired||(actual[12]&4)!=0||number!=0)error=VmHardware.object("code",expired?"timeout":(actual[12]&4)!=0?"cancelled":"io_error","errno",number,"message","ISO returned a bounded result; inspect its packet frame and completion flags before retrying.");}}
                catch(Exception e){synchronized(this){error=failure(e);}}
                finally{synchronized(this){running=false;runFinished=true;if(timer!=null)timer.cancel(false);timer=null;event("result");}cleanup();}
            });}catch(RejectedExecutionException e){synchronized(this){runFinished=true;error=failure(e);if(timer!=null)timer.cancel(false);timer=null;}Native.cancel(nativeId);cleanup();}
        }
        static JSONObject failure(Exception e){try{return VmHardware.object("code",e instanceof RejectedExecutionException?"busy":"io_error","message",MainActivity.safe(e));}catch(Exception ignored){return new JSONObject();}}
        void event(String name){if(closed)return;try{emit(VmHardware.object("event",name,"deadline_expired",expired,"cancel_requested",cancelRequested,"result_ready",frame!=null,"run_finished",runFinished,"lease_released",settled,"error",error==null?JSONObject.NULL:error,"cleanup_error",cleanupError==null?JSONObject.NULL:cleanupError));}catch(Exception ignored){}}
        void cleanup(){
            synchronized(this){if(settled||cleanupRunning||!runFinished||running)return;cleanupRunning=true;}
            boolean complete=false;
            try{long id=nativeId;if(id!=0){boolean retire=Native.retireRequired(id);if(retire)parent.retireIso(this);Native.destroy(id,parent.sdkClosed());nativeId=0;}complete=true;}
            catch(Exception e){synchronized(this){cleanupError=failure(e);event("cleanup_pending");}}
            finally{if(complete){parent.finishIso(this);synchronized(LEASES){LEASES.remove(this);}SLOTS.release();}synchronized(this){cleanupRunning=false;if(complete){settled=true;event("settled");}}}
        }
        void retryCleanup(){synchronized(this){if(!runFinished||running||settled||cleanupRunning||retryQueued)return;retryQueued=true;}try{WORKERS.execute(()->{synchronized(this){retryQueued=false;}cleanup();});}catch(RejectedExecutionException ignored){synchronized(this){retryQueued=false;}}}
        public void access(VmHardware.Context c)throws Exception{super.access(c);parent.access(c);}
        synchronized byte[] result()throws Exception{check();if(!runFinished)throw new VmHardware.Failure("not_ready","Wait for the ISO result; its worker is still executing.");if(frame==null)throw new VmHardware.Failure("io_error",error==null?"ISO produced no packet frame.":error.toString());return frame.clone();}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"endpoint",endpoint,"input",(endpoint&128)!=0,"packets",packets,"requested_bytes",requested,"cancel_requested",cancelRequested,"deadline_expired",expired,"run_finished",runFinished,"result_ready",frame!=null,"lease_released",settled,"cleanup_pending",(cancelRequested||runFinished)&&!settled,"error",error==null?JSONObject.NULL:error,"cleanup_error",cleanupError==null?JSONObject.NULL:cleanupError,"available_slots",SLOTS.availablePermits());}
        synchronized int cancel(){if(runFinished||cancelRequested)return 0;cancelRequested=true;if(nativeId!=0)Native.cancel(nativeId);return 1;}
        public void close(){synchronized(this){if(!closed){closed=true;events.clear();cancelRequested=true;}if(nativeId!=0)Native.cancel(nativeId);}retryCleanup();}
    }
    static Object submit(VmHardware.Context c,HardwareUsb.Device parent,JSONArray args)throws Exception{
        int address=VmHardware.integer(args,1,1,255),timeout=VmHardware.integer(args,4,1,8000);Object value=args.get(2);if(!(value instanceof JSONArray))throw new VmHardware.Failure("invalid_argument","Choose1..128 ISO packet lengths.");JSONArray rows=(JSONArray)value;if(rows.length()<1||rows.length()>MAX_PACKETS)throw new VmHardware.Failure("invalid_argument","Choose1..128 ISO packet lengths.");int[] sizes=new int[rows.length()];int total=0;
        for(int i=0;i<sizes.length;i++){sizes[i]=VmHardware.integer(rows,i,1,16384);if(sizes[i]>MAX_BYTES-total)throw new VmHardware.Failure("size_limit","An ISO request contains at most24576 packet bytes.");total+=sizes[i];}
        byte[] data=VmHardware.data(args.get(3));boolean input=(address&128)!=0;if(input?data.length!=0:data.length!=total)throw new VmHardware.Failure("invalid_argument","ISO input takes an empty blob; output takes exactly the sum of requested packet lengths.");
        synchronized(LEASES){for(Transfer old:LEASES)old.retryCleanup();}if(!SLOTS.tryAcquire())throw new VmHardware.Failure("resource_limit","At most8 ISO requests including actual worker/SDK cleanup.");Transfer transfer=new Transfer(c,parent,address,sizes.length,total,timeout);
        synchronized(LEASES){LEASES.add(transfer);}
        try{int fd=parent.reserveIso(transfer,address,sizes);transfer.allocate(fd,sizes,data);String id=VmHardware.add(transfer);transfer.start();return id;}
        catch(Exception e){transfer.close();transfer.start();throw e;}
    }
    static boolean supports(String op){return op.equals("usb_iso_submit")||op.equals("usb_iso_frame")||op.equals("usb_iso_cancel");}
    static Object call(VmHardware.Context c,String op,JSONArray args)throws Exception{
        if(op.equals("usb_iso_submit")){HardwareUsb.Device parent=VmHardware.handle(c,VmHardware.text(args,0,128),HardwareUsb.Device.class);parent.access(c);return submit(c,parent,args);}
        Transfer t=VmHardware.handle(c,VmHardware.text(args,0,128),Transfer.class);t.access(c);if(op.equals("usb_iso_cancel"))return t.cancel();return VmHardware.bytes(t.result());
    }
}
