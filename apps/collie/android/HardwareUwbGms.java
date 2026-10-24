package org.flexscript.collie;

import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.SystemClock;
import com.google.android.gms.common.GoogleApiAvailability;
import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.nearby.Nearby;
import com.google.android.gms.nearby.uwb.*;
import com.google.android.gms.tasks.*;
import java.io.IOException;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Public Play services UWB Tasks and callbacks. No Jetpack internals or raw Binder. */
final class HardwareUwbGms {
    static final String PERMISSION="android.permission.UWB_RANGING";
    static final Executor CALLBACK=Runnable::run;
    static final Object INFO_LOCK=new Object();static UwbClient infoClient;static Task<Boolean> availableTask;static Task<RangingCapabilities> capsTask;
    static int status(VmHardware.Context c){return GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(c.host,230100000);}
    static void require(VmHardware.Context c)throws Exception{
        if(Build.VERSION.SDK_INT<31)throw new VmHardware.Failure("unsupported_operation","Play services UWB requires Android12+.");
        if(!HardwareUwb.feature(c))throw new VmHardware.Failure("unsupported","This device does not declare UWB hardware.");
        if(status(c)!=0)throw new VmHardware.Failure("unavailable","Compatible Google Play services is unavailable; no legacy AOSP provider is bound.");
    }
    static UwbClient client(VmHardware.Context c,int role){Context app=c.host.getApplicationContext();return role==1?Nearby.getUwbControllerClient(app):Nearby.getUwbControleeClient(app);}
    static JSONObject error(Exception e)throws Exception{if(e instanceof ExecutionException&&e.getCause() instanceof Exception)e=(Exception)e.getCause();return VmHardware.object("code",e instanceof SecurityException?"permission_denied":"api_error","sdk_status",e instanceof ApiException?((ApiException)e).getStatusCode():JSONObject.NULL,"message",MainActivity.safe(e));}
    static JSONObject error(Task<?> task)throws Exception{return task.isCanceled()?VmHardware.object("code","cancelled","sdk_status",JSONObject.NULL,"message","The SDK Task was cancelled; hardware effects are not inferred."):error(task.getException()==null?new IOException("SDK Task failed without an exception"):task.getException());}
    static JSONArray ints(List<Integer> values)throws Exception{if(values==null)return new JSONArray();if(values.size()>256)throw new VmHardware.Failure("size_limit","UWB capability list exceeds256 entries.");return new JSONArray(values);}
    static JSONObject caps(RangingCapabilities c)throws Exception{return VmHardware.object("distance_supported",c.supportsDistance(),"azimuth_supported",c.supportsAzimuthalAngle(),"elevation_supported",c.supportsElevationAngle(),"background_supported",c.hasBackgroundRangingSupport(),"interval_reconfiguration_supported",c.supportsRangingIntervalReconfigure(),"minimum_interval_ms",c.getMinRangingInterval(),"channels",ints(c.getSupportedChannels()),"notification_configs",ints(c.getSupportedNtfConfigs()),"config_ids",ints(c.getSupportedConfigIds()),"update_rates",ints(c.getSupportedRangingUpdateRates()),"slot_durations",ints(c.getSupportedSlotDurations()));}
    static JSONObject base(VmHardware.Context c)throws Exception{return VmHardware.object("sdk",Build.VERSION.SDK_INT,"feature",HardwareUwb.feature(c),"backend","play_services","public_ranging_api",false,"legacy_gms_binding_implemented",true,"legacy_aosp_binding_implemented",false,"gms_status",Build.VERSION.SDK_INT>=31?status(c):JSONObject.NULL,"availability_known",false,"available",JSONObject.NULL);}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{out.put(base(c).put("id","uwb_ranging").put("implemented",true).put("supported",Build.VERSION.SDK_INT>=31&&HardwareUwb.feature(c)?JSONObject.NULL:false).put("permission","uwb").put("observer_slots_available",HardwareUwb.WATCHES.availablePermits()).put("session_slots_available",HardwareUwb.SESSIONS.availablePermits()));}
    static Object info(VmHardware.Context c)throws Exception{
        JSONObject result=base(c);if(Build.VERSION.SDK_INT<31||status(c)!=0)return result;
        Task<Boolean> available;Task<RangingCapabilities> capabilities;
        synchronized(INFO_LOCK){if(infoClient==null)infoClient=client(c,1);if(availableTask==null||availableTask.isComplete())availableTask=infoClient.isAvailable();if(capsTask==null||capsTask.isComplete())capsTask=infoClient.getRangingCapabilities();available=availableTask;capabilities=capsTask;}
        try{result.put("available",Tasks.await(available,3,TimeUnit.SECONDS)).put("availability_known",true);}catch(Exception e){result.put("availability_error",error(e));}
        try{result.put("snapshot",caps(Tasks.await(capabilities,3,TimeUnit.SECONDS)));}catch(Exception e){result.put("capabilities_error",error(e));}
        VmHardware.check();return result;
    }
    static final class Watch extends VmHardware.Handle {
        final UwbClient sdk;
        boolean preparing,submitted,settled=true,startupExpired,cleanupQueued,unsubscribeStarted,unsubscribeComplete,released;
        Boolean subscriptionSuccessful,unsubscribeSuccessful;
        JSONObject failure,operationError,cleanupError;
        long expires;
        final Runnable deadline=()->{synchronized(this){expire();}};
        final UwbAvailabilityObserver observer=(available,reason)->{
            synchronized(this){
                if(!settled)expire();
                if(!closed&&!startupExpired&&failure==null)try{event("capabilities","uwb",VmHardware.object("available",available,"availability_known",true,"sdk_reason",reason),"sdk_callback",true);}catch(Exception ignored){}
            }
        };
        Watch(VmHardware.Context c){super(c,"uwb","uwb_gms_capabilities");sdk=client(c,1);}
        void event(String name,Object... values){
            if(closed)return;
            try{Object[] fields=new Object[values.length+4];fields[0]="event";fields[1]=name;fields[2]="backend";fields[3]="play_services";System.arraycopy(values,0,fields,4,values.length);emit(VmHardware.object(fields));}catch(Exception ignored){}
        }
        synchronized void release(){
            if(released)return;released=true;HardwareSensors.events().removeCallbacks(deadline);HardwareUwb.WATCHES.release();
        }
        void expire(){
            if(released||settled||startupExpired||SystemClock.elapsedRealtime()<expires)return;
            startupExpired=true;
            try{failure=VmHardware.object("code","timeout","message","UWB availability startup expired; pending SDK work remains owned.");event("error","error",failure);}catch(Exception ignored){}
            cleanup();
        }
        void failed(Exception e){
            try{operationError=error(e);if(!startupExpired)failure=operationError;event("error","error",failure,"operation_error",operationError);}catch(Exception ignored){}
        }
        void start(){
            synchronized(this){if(closed||released)return;preparing=true;settled=false;expires=SystemClock.elapsedRealtime()+8000;HardwareSensors.events().postDelayed(deadline,8000);}
            try{sdk.getRangingCapabilities().addOnCompleteListener(CALLBACK,this::prepared);}
            catch(Exception e){synchronized(this){expire();preparing=false;settled=true;failed(e);cleanup();}}
        }
        void prepared(Task<RangingCapabilities> task){
            synchronized(this){
                expire();preparing=false;
                if(!task.isSuccessful())try{operationError=error(task);if(!startupExpired)failure=operationError;event("error","error",failure,"operation_error",operationError);}catch(Exception ignored){}
                if(closed||startupExpired||failure!=null){settled=true;release();return;}
                // Admission precedes close; the lease remains owned until the
                // actual subscription Task and subsequent unsubscribe settle.
                submitted=true;
            }
            try{sdk.subscribeToUwbAvailability(observer).addOnCompleteListener(CALLBACK,this::subscribed);}
            catch(Exception e){synchronized(this){expire();settled=true;failed(e);cleanup();}}
        }
        void subscribed(Task<Void> task){
            synchronized(this){
                expire();settled=true;subscriptionSuccessful=task.isSuccessful();HardwareSensors.events().removeCallbacks(deadline);
                if(!task.isSuccessful())try{operationError=error(task);if(!startupExpired)failure=operationError;event("error","error",failure,"operation_error",operationError);}catch(Exception ignored){}
                if(closed||startupExpired||failure!=null)cleanup();
            }
        }
        synchronized void cleanup(){
            if(preparing||released||!settled)return;
            HardwareSensors.events().removeCallbacks(deadline);
            if(!submitted){release();return;}
            if(cleanupQueued||unsubscribeStarted)return;cleanupQueued=true;
            try{HardwareUwb.CLEANUP.execute(()->{
                synchronized(this){cleanupQueued=false;unsubscribeStarted=true;}
                try{sdk.unsubscribeFromUwbAvailability().addOnCompleteListener(CALLBACK,task->{synchronized(this){
                    unsubscribeComplete=true;unsubscribeSuccessful=task.isSuccessful();
                    if(task.isSuccessful())release();else try{cleanupError=error(task);event("cleanup_pending","error",cleanupError);}catch(Exception ignored){}
                }});}catch(Exception e){synchronized(this){try{cleanupError=error(e);event("cleanup_pending","error",cleanupError);}catch(Exception ignored){}}}
            });}catch(RejectedExecutionException full){cleanupQueued=false;HardwareSensors.events().postDelayed(this::cleanup,250);}
        }
        public synchronized Object info()throws Exception{
            check();expire();return VmHardware.object("kind",kind,"backend","play_services","preparing",preparing,"subscription_submitted",submitted,"subscription_task_complete",settled,"subscription_task_success",subscriptionSuccessful==null?JSONObject.NULL:subscriptionSuccessful,"startup_deadline_expired",startupExpired,"startup_deadline_elapsed_ms",expires,"cleanup_queued",cleanupQueued,"unsubscribe_started",unsubscribeStarted,"unsubscribe_task_complete",unsubscribeComplete,"unsubscribe_task_success",unsubscribeSuccessful==null?JSONObject.NULL:unsubscribeSuccessful,"lease_released",released,"error",failure==null?JSONObject.NULL:failure,"operation_error",operationError==null?JSONObject.NULL:operationError,"cleanup_error",cleanupError==null?JSONObject.NULL:cleanupError);
        }
        public synchronized void close(){if(closed)return;closed=true;events.clear();cleanup();}
    }
    static final class Peer {
        final UUID id;final int session,config,channel,preamble,rate,slot,sub;final byte[] local,address,key,subKey;final boolean subSet;boolean removing,removeTaskComplete,suspended;
        Peer(Object value)throws Exception{JSONArray r=HardwareUwb.list(value,12,12);String text=VmHardware.text(r,0,36);try{id=UUID.fromString(text);if(!id.toString().equalsIgnoreCase(text))throw new IllegalArgumentException();}catch(Exception e){throw new VmHardware.Failure("invalid_argument","Choose a canonical UWB peer UUID.");}
            session=(int)VmHardware.longInteger(r,1,0,4294967295L);config=VmHardware.integer(r,2,1,7);local=address(r.get(3));address=address(r.get(4));channel=VmHardware.integer(r,5,0,255);preamble=VmHardware.integer(r,6,0,255);rate=VmHardware.integer(r,7,1,3);slot=VmHardware.integer(r,8,1,2);key=VmHardware.data(r.get(9));long subId=VmHardware.longInteger(r,10,-1,4294967295L);sub=(int)subId;subSet=subId!=-1;subKey=VmHardware.data(r.get(11));if(key.length>32||subKey.length>32)throw new VmHardware.Failure("invalid_argument","UWB keys contain at most32 bytes.");}
        boolean same(Peer p){return session==p.session&&config==p.config&&channel==p.channel&&preamble==p.preamble&&rate==p.rate&&slot==p.slot&&Arrays.equals(key,p.key);}
    }
    static byte[] address(Object value)throws Exception{byte[] b=VmHardware.data(value);if(b.length!=2&&b.length!=8)throw new VmHardware.Failure("invalid_argument","UWB addresses contain2 or8 bytes.");return b;}
    static final class Request {
        final String id="uwb-request-"+UUID.randomUUID(),op;final long expires;boolean submitted,returned,invocationFinished,complete,expired;Boolean success;JSONObject failure;Runnable timer;
        Request(String op,int timeout){this.op=op;expires=SystemClock.elapsedRealtime()+timeout;}
        JSONObject info()throws Exception{expired|=SystemClock.elapsedRealtime()>=expires&&!complete;return VmHardware.object("id",id,"operation",op,"sdk_call_started",submitted,"sdk_task_returned",returned,"invocation_finished",invocationFinished,"task_complete",complete,"task_success",success==null?JSONObject.NULL:success,"deadline_expired",expired,"error",failure==null?JSONObject.NULL:failure);}
    }
    interface Invoke {Task<Void> run()throws Exception;}
    interface Action {void run()throws Exception;}
    static final class Range extends VmHardware.Handle {
        final VmHardware.Context context;final UwbClient sdk;final int role,timeout;final LinkedHashMap<UUID,Peer> peers=new LinkedHashMap<>();final LinkedHashMap<String,Request> requests=new LinkedHashMap<>();final LinkedHashMap<String,Peer> retired=new LinkedHashMap<>();
        boolean preparing,prepared,preparationSettled=true,startSubmitted,startSettled,startSuccessful,initialized,stopWanted,stopQueued,stopSubmitted,stopComplete,released,startupExpired;String state="preparing";byte[] local;UwbComplexChannel channel;RangingCapabilities capabilities;Request pending;JSONObject cleanupError,operationError,preparationError;Peer group;long expires;
        final Runnable deadline=()->{synchronized(this){if((state.equals("preparing")||state.equals("starting"))&&SystemClock.elapsedRealtime()>=expires){startupExpired=true;state="error";try{operationError=VmHardware.object("code","timeout","message","UWB preparation/start expired; pending SDK work remains owned.");}catch(Exception ignored){}event("error","code","timeout","message","UWB preparation/start expired; pending SDK work remains owned.");stopWanted=true;cleanup();}}};
        final RangingSessionCallback callback=new RangingSessionCallback(){
            public void onRangingInitialized(UwbDevice device){synchronized(Range.this){if(released)return;try{
                if(isLocal(device)){initialized=true;event("initialized","scope","session","address",VmHardware.bytes(local),"sdk_callback",true);}
                else{Peer p=known(device);if(!peers.containsKey(p.id))return;p.suspended=false;initialized=true;event("started","scope","peer","peer",p.id.toString(),"sdk_callback",true);}
                opened();
            }catch(Exception e){fault(e);}}}
            public void onRangingResult(UwbDevice device,RangingPosition position){synchronized(Range.this){if(closed||!state.equals("ranging"))return;try{Peer p=known(device);if(!peers.containsKey(p.id))return;event("ranging","peer",p.id.toString(),"technology",1,"timestamp_ns",position.getElapsedRealtimeNanos(),"timestamp_ms",position.getElapsedRealtimeNanos()/1000000,"distance_m",measurement(position.getDistance()),"azimuth_degrees",measurement(position.getAzimuth()),"elevation_degrees",measurement(position.getElevation()),"rssi_dbm",position.getRssiDbm()==RangingPosition.RSSI_UNKNOWN?JSONObject.NULL:position.getRssiDbm(),"sdk_callback",true);}catch(Exception e){fault(e);}}}
            public void onRangingSuspended(UwbDevice device,int reason){synchronized(Range.this){if(released)return;try{
                if(isLocal(device)){event("stopped","scope","session","address",VmHardware.bytes(local),"reason",reason,"sdk_callback",true);if(!stopWanted)state="suspended";stopWanted=true;cleanup();return;}
                Peer p=known(device);p.suspended=true;event("stopped","scope","peer","peer",p.id.toString(),"reason",reason,"sdk_callback",true);removed(p);
                if(reason==RangingSessionCallback.RangingSuspendedReason.WRONG_PARAMETERS||reason==RangingSessionCallback.RangingSuspendedReason.FAILED_TO_START){state="error";stopWanted=true;cleanup();}
            }catch(Exception e){fault(e);}}}
        };
        Range(VmHardware.Context c,int role,int timeout){super(c,"uwb","uwb_gms_ranging");context=c;this.role=role;this.timeout=timeout;sdk=client(c,role);}
        void event(String name,Object... values){if(closed)return;try{Object[] fields=new Object[values.length+4];fields[0]="event";fields[1]=name;fields[2]="backend";fields[3]="play_services";System.arraycopy(values,0,fields,4,values.length);emit(VmHardware.object(fields));}catch(Exception ignored){}}
        synchronized void release(){if(!released){released=true;HardwareSensors.events().removeCallbacks(deadline);local=null;group=null;peers.clear();retired.clear();HardwareUwb.SESSIONS.release();}}
        void prepare(){
            synchronized(this){if(closed||released)return;preparing=true;preparationSettled=false;expires=SystemClock.elapsedRealtime()+timeout;HardwareSensors.events().postDelayed(deadline,timeout);}
            ArrayList<Task<?>> tasks=new ArrayList<>();Exception failure=null;
            try{tasks.add(Objects.requireNonNull(sdk.getRangingCapabilities()));tasks.add(Objects.requireNonNull(sdk.getLocalAddress()));if(role==1)tasks.add(Objects.requireNonNull(sdk.getComplexChannel()));}catch(Exception e){failure=e;}
            final Exception invocationError=failure;
            Tasks.whenAllComplete(tasks).addOnCompleteListener(CALLBACK,all->{synchronized(this){
                preparing=false;preparationSettled=true;
                Exception actualError=invocationError;
                if(actualError==null)for(Task<?> t:tasks)if(!t.isSuccessful()){actualError=t.getException()==null?new IOException("UWB preparation Task cancelled"):t.getException();break;}
                if(actualError!=null)try{preparationError=error(actualError);}catch(Exception ignored){}
                if(closed||SystemClock.elapsedRealtime()>=expires){if(!closed){deadline.run();if(preparationError!=null)event("preparation_result","error",preparationError,"deadline_expired",startupExpired);}cleanup();return;}
                try{
                    if(actualError!=null)throw actualError;
                    capabilities=(RangingCapabilities)tasks.get(0).getResult();local=address(VmHardware.bytes(((UwbAddress)tasks.get(1).getResult()).getAddress()));
                    if(role==1)channel=(UwbComplexChannel)tasks.get(2).getResult();prepared=true;state="ready";HardwareSensors.events().removeCallbacks(deadline);
                    event("prepared","local_address",VmHardware.bytes(local),"channel",channel==null?JSONObject.NULL:channel.getChannel(),"preamble_index",channel==null?JSONObject.NULL:channel.getPreambleIndex(),"sdk_task_complete",true);
                }catch(Exception e){fault(e);}
            }});
        }
        synchronized void fault(Exception e){state="error";try{JSONObject actual=error(e);if(!startupExpired)operationError=actual;event("error","error",operationError,"operation_error",actual);}catch(Exception ignored){}stopWanted=true;cleanup();}
        boolean isLocal(UwbDevice d){return local!=null&&d!=null&&d.getAddress()!=null&&Arrays.equals(local,d.getAddress().getAddress());}
        Peer known(UwbDevice d)throws Exception{byte[] address=d.getAddress().getAddress();for(Peer p:peers.values())if(Arrays.equals(p.address,address))return p;Peer old=retired.get(Arrays.toString(address));if(old!=null)return old;throw new VmHardware.Failure("invalid_response","SDK callback names a peer outside this owned session.");}
        void removed(Peer p){if(p.removing&&p.removeTaskComplete&&p.suspended&&peers.remove(p.id,p)){while(retired.size()>=16)retired.remove(retired.keySet().iterator().next());retired.put(Arrays.toString(p.address),p);}}
        synchronized void opened(){if(state.equals("starting")&&SystemClock.elapsedRealtime()>=expires)deadline.run();if(!closed&&!stopWanted&&state.equals("starting")&&startSuccessful&&initialized){state="ranging";HardwareSensors.events().removeCallbacks(deadline);event("opened","sdk_callback",true,"start_task_success",true);}}
        public synchronized void access(VmHardware.Context c)throws Exception{check();if(c.host.checkSelfPermission(PERMISSION)!=PackageManager.PERMISSION_GRANTED){close();throw new VmHardware.Failure("permission_revoked","Android UWB_RANGING was revoked.");}}
        synchronized void active()throws Exception{check();if(!state.equals("ranging")||stopWanted)throw new VmHardware.Failure("not_ready","Wait for actual initialized and successful start Task observations.");if(pending!=null)throw new VmHardware.Failure("busy","A prior UWB SDK Task has not settled.");}
        String invoke(String op,int timeout,Invoke invoke,Action admit,Action accepted)throws Exception{
            Request r;
            synchronized(this){
                check();if(pending!=null)throw new VmHardware.Failure("busy","A prior UWB Task remains unsettled.");
                admit.run();r=new Request(op,timeout);while(requests.size()>=16)requests.remove(requests.keySet().iterator().next());
                requests.put(r.id,r);pending=r;r.submitted=true;if(op.equals("start"))startSubmitted=true;
                r.timer=()->{synchronized(this){if(!r.complete&&!r.expired){r.expired=true;try{event("request_timeout","result",r.info());}catch(Exception ignored){}}}};HardwareSensors.events().postDelayed(r.timer,timeout);
            }
            // The admission above precedes close. A closing resource keeps this
            // slot until invocation and the real Task settle; no UI lock spans SDK I/O.
            try{
                Task<Void> task=Objects.requireNonNull(invoke.run());synchronized(this){r.returned=true;r.invocationFinished=true;}
                task.addOnCompleteListener(CALLBACK,done->{synchronized(this){
                    r.expired|=SystemClock.elapsedRealtime()>=r.expires;r.complete=true;r.success=done.isSuccessful();HardwareSensors.events().removeCallbacks(r.timer);
                    try{if(!done.isSuccessful()){r.failure=error(done);operationError=r.failure;}else accepted.run();}catch(Exception e){try{r.failure=error(e);}catch(Exception ignored){}}
                    if(op.equals("start")){startSettled=true;startSuccessful=done.isSuccessful();if(!startSuccessful){state="error";stopWanted=true;}opened();}
                    if(pending==r)pending=null;try{event("request_result","result",r.info());}catch(Exception ignored){}cleanup();
                }});
            }catch(Exception e){synchronized(this){
                r.invocationFinished=true;r.failure=error(e);HardwareSensors.events().removeCallbacks(r.timer);operationError=r.failure;if(pending==r)pending=null;state="error";stopWanted=true;
                event("request_error","result",r.info());cleanupError=r.failure;cleanup();
            }}
            return r.id;
        }
        synchronized void cleanup(){
            if(!stopWanted&&!closed)return;if(preparing||!preparationSettled||pending!=null)return;
            if(!startSubmitted){state="closed";release();return;}if(stopQueued||stopSubmitted)return;stopQueued=true;state="stopping";
            try{HardwareUwb.CLEANUP.execute(()->{
                synchronized(this){stopQueued=false;stopSubmitted=true;}try{sdk.stopRanging(callback).addOnCompleteListener(CALLBACK,task->{synchronized(this){
                    stopComplete=true;
                    if(task.isSuccessful()){state="closed";event("closed","stop_task_success",true,"sdk_task_complete",true);release();}
                    else try{cleanupError=error(task);event("cleanup_pending","error",cleanupError);}catch(Exception ignored){}
                }});}catch(Exception e){synchronized(this){try{cleanupError=error(e);}catch(Exception ignored){}}}
            });}catch(RejectedExecutionException full){stopQueued=false;HardwareSensors.events().postDelayed(this::cleanup,250);}
        }
        public synchronized void close(){if(closed)return;closed=true;events.clear();stopWanted=true;cleanup();}
        synchronized int stop(){if(stopWanted)return 0;stopWanted=true;cleanup();return 1;}
        public synchronized Object info()throws Exception{check();JSONArray peerRows=new JSONArray();for(Peer p:peers.values())peerRows.put(VmHardware.object("id",p.id.toString(),"address",VmHardware.bytes(p.address),"pending_removal",p.removing,"removal_task_complete",p.removeTaskComplete,"sdk_suspended",p.suspended));return VmHardware.object("peers",peerRows,"retired_peer_count",retired.size(),"error",operationError==null?JSONObject.NULL:operationError,"kind",kind,"backend","play_services","role",role,"state",state,"prepared",prepared,"local_address",local==null?JSONObject.NULL:VmHardware.bytes(local),"channel",channel==null?JSONObject.NULL:channel.getChannel(),"preamble_index",channel==null?JSONObject.NULL:channel.getPreambleIndex(),"capabilities",capabilities==null?JSONObject.NULL:caps(capabilities),"start_task_complete",startSettled,"start_task_success",startSettled?startSuccessful:JSONObject.NULL,"sdk_initialized",initialized,"pending_request",pending==null?JSONObject.NULL:pending.id,"retained_requests",requests.size(),"preparation_error",preparationError==null?JSONObject.NULL:preparationError,"startup_deadline_expired",startupExpired,"startup_deadline_elapsed_ms",expires,"stop_queued",stopQueued,"stop_submitted",stopSubmitted,"stop_task_complete",stopComplete,"lease_released",released,"cleanup_error",cleanupError==null?JSONObject.NULL:cleanupError);}
        String start(JSONArray rows,JSONArray options)throws Exception{
            synchronized(this){check();if(!prepared||!state.equals("ready"))throw new VmHardware.Failure("not_ready","Wait for an actual prepared event before negotiating and starting UWB.");}
            HardwareUwb.list(rows,1,role==0?1:8);HardwareUwb.list(options,7,7);int angles=VmHardware.integer(options,0,0,1),count=VmHardware.integer(options,1,0,65535),fusion=VmHardware.integer(options,2,0,1),notification=VmHardware.integer(options,3,0,3),near=VmHardware.integer(options,4,0,20000),far=VmHardware.integer(options,5,0,20000),timeout=VmHardware.integer(options,6,500,120000);
            if(count!=0||fusion!=0)throw new VmHardware.Failure("unsupported_operation","The raw Play services API has no measurement-count limit or sensor-fusion binding; use0 for both options.");if(near>far)throw new VmHardware.Failure("invalid_argument","UWB near distance exceeds far distance.");
            LinkedHashMap<UUID,Peer> parsed=new LinkedHashMap<>();HashSet<String> addresses=new HashSet<>();Peer first=null;
            for(int i=0;i<rows.length();i++){Peer p=new Peer(rows.get(i));if(!Arrays.equals(local,p.local))throw new VmHardware.Failure("invalid_argument","Use the actual SDK-prepared local address; it cannot be selected by the guest.");if(first!=null&&!first.same(p))throw new VmHardware.Failure("invalid_argument","Legacy peers must share session/config/channel/rate/slot/key parameters.");if(parsed.put(p.id,p)!=null||!addresses.add(Arrays.toString(p.address)))throw new VmHardware.Failure("invalid_argument","UWB peer UUIDs and addresses must be unique.");if(first==null)first=p;}
            final Peer p=first;if(!capabilities.getSupportedConfigIds().contains(p.config))throw new VmHardware.Failure("unsupported_operation","The SDK does not advertise that UWB profile.");if((p.config==1||p.config==4)&&parsed.size()!=1)throw new VmHardware.Failure("invalid_argument","A unicast UWB profile requires one peer.");if(p.channel==0||p.preamble==0)throw new VmHardware.Failure("invalid_argument","Exchange and provide an explicit UWB complex channel.");if(role==1&&(channel.getChannel()!=p.channel||channel.getPreambleIndex()!=p.preamble))throw new VmHardware.Failure("invalid_argument","Use the controller's actual SDK-prepared complex channel.");
            RangingParameters params=parameters(p,parsed.values(),angles,notification,near,far);
            return invoke("start",timeout,()->sdk.startRanging(params,callback),()->{
                if(!state.equals("ready"))throw new VmHardware.Failure("busy","UWB preparation was already used.");
                peers.putAll(parsed);group=p;state="starting";expires=SystemClock.elapsedRealtime()+timeout;HardwareSensors.events().postDelayed(deadline,timeout);
            },()->{});
        }
    }
    static RangingParameters parameters(Peer p,Collection<Peer> peers,int angles,int notification,int near,int far)throws Exception{
            RangingParameters.Builder b=new RangingParameters.Builder().setUwbConfigId(p.config).setSessionId(p.session).setRangingUpdateRate(p.rate).setSlotDuration(p.slot).setIsAoaDisabled(angles==0).setComplexChannel(new UwbComplexChannel.Builder().setChannel(p.channel).setPreambleIndex(p.preamble).build()).setUwbRangeDataNtfConfig(new UwbRangeDataNtfConfig.Builder().setRangeDataConfigType(notification).setNtfProximityNear(near).setNtfProximityFar(far).build());
            if(p.subSet)b.setSubSessionId(p.sub);if(p.key.length>0)b.setSessionKeyInfo(p.key);if(p.subKey.length>0)b.setSubSessionKeyInfo(p.subKey);for(Peer peer:peers)b.addPeerDevice(UwbDevice.createForAddress(peer.address));return b.build();
    }
    static Object measurement(RangingMeasurement value)throws Exception{if(value==null)return JSONObject.NULL;if(!Float.isFinite(value.getValue()))throw new VmHardware.Failure("invalid_response","SDK returned a nonfinite UWB measurement.");return VmHardware.object("value",VmHardware.real(value.getValue()),"confidence",JSONObject.NULL,"confidence_known",false);}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(op.equals("uwb_info"))return info(c);
        if(op.equals("uwb_watch")){require(c);if(!HardwareUwb.WATCHES.tryAcquire())throw new VmHardware.Failure("resource_limit","At most8 UWB observers including cleanup.");Watch w;try{w=new Watch(c);}catch(Exception e){HardwareUwb.WATCHES.release();throw e;}try{String id=VmHardware.add(w);w.start();return id;}catch(Exception e){w.close();throw e;}}
        if(op.equals("uwb_prepare")){int role=VmHardware.integer(a,0,0,1),timeout=VmHardware.integer(a,1,500,30000);require(c);VmHardware.require(c,PERMISSION);if(!HardwareUwb.SESSIONS.tryAcquire())throw new VmHardware.Failure("resource_limit","At most8 UWB sessions including SDK cleanup.");Range r;try{r=new Range(c,role,timeout);}catch(Exception e){HardwareUwb.SESSIONS.release();throw e;}try{String id=VmHardware.add(r);r.prepare();return id;}catch(Exception e){r.close();throw e;}}
        if(op.equals("uwb_range"))throw new VmHardware.Failure("unsupported_operation","Legacy UWB uses SDK-allocated addresses: call uwb_prepare, negotiate using device_info, then uwb_start.");
        Range r=VmHardware.handle(c,VmHardware.text(a,0,128),Range.class);r.access(c);
        if(op.equals("uwb_start"))return r.start(HardwareUwb.list(a.get(1),1,8),HardwareUwb.list(a.get(2),7,7));
        if(op.equals("uwb_request")){String id=VmHardware.text(a,1,128);synchronized(r){Request request=r.requests.get(id);if(request==null)throw new VmHardware.Failure("stale_request","Unknown or evicted UWB Task ID.");return request.info();}}
        if(op.equals("uwb_stop"))return r.stop();
        synchronized(r){r.active();if(r.role!=1)throw new VmHardware.Failure("unsupported_operation","Only a controller can change peers or intervals.");}
        if(op.equals("uwb_interval")){int skip=VmHardware.integer(a,1,0,255);return r.invoke("interval",8000,()->r.sdk.reconfigureRangingInterval(skip),()->r.active(),()->{});}
        if(op.equals("uwb_remove")){
            String text=VmHardware.text(a,1,36);UUID id;try{id=UUID.fromString(text);if(!id.toString().equalsIgnoreCase(text))throw new IllegalArgumentException();}catch(Exception e){throw new VmHardware.Failure("invalid_argument","Choose a canonical UWB peer UUID.");}
            final Peer peer;synchronized(r){peer=r.peers.get(id);}if(peer==null)throw new VmHardware.Failure("unknown_peer","This UUID is not owned by the session.");
            return r.invoke("remove",8000,()->r.sdk.removeControlee(new UwbAddress(peer.address)),()->{r.active();if(r.peers.get(id)!=peer||peer.removing)throw new VmHardware.Failure("invalid_argument","This peer was already removed or is pending removal.");peer.removing=true;peer.suspended=false;},()->{peer.removeTaskComplete=true;r.removed(peer);});
        }
        if(op.equals("uwb_add")){
            Peer peer=new Peer(a.get(1));
            return r.invoke("add",8000,()->peer.subKey.length>0?r.sdk.addControleeWithSessionParams(new RangingControleeParameters(new UwbAddress(peer.address),peer.sub,peer.subKey)):r.sdk.addControlee(new UwbAddress(peer.address)),()->{
                r.active();if(r.peers.size()>=8)throw new VmHardware.Failure("resource_limit","At most8 UWB peers including pending removal.");
                if(r.peers.containsKey(peer.id)||!peer.same(r.group)||!Arrays.equals(peer.local,r.local))throw new VmHardware.Failure("invalid_argument","Use a new peer with this prepared session's parameters.");
                for(Peer old:r.peers.values())if(Arrays.equals(old.address,peer.address))throw new VmHardware.Failure("invalid_argument","UWB peer address already belongs to this session.");
                Peer old=r.retired.get(Arrays.toString(peer.address));if(old!=null&&!old.id.equals(peer.id))throw new VmHardware.Failure("invalid_argument","Reusing an address cannot reassign its callback UUID within this session.");r.peers.put(peer.id,peer);
            },()->{});
        }
        throw new VmHardware.Failure("unsupported_operation","Unknown Play services UWB operation.");
    }
}
