package org.flexscript.collie;

import android.content.*;
import android.content.pm.*;
import android.os.*;
import androidx.core.uwb.backend.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Pinned AndroidX OEM-service protocol. No guest Binder, reflection or hidden UwbManager. */
final class HardwareUwbAosp {
    static final String PACKAGE="androidx.core.uwb.backend",ACTION="androidx.core.uwb.backend.service",PERMISSION="android.permission.UWB_RANGING";
    private static final Set<Base> LEASES=new LinkedHashSet<>();
    private static final ThreadPoolExecutor RPC=pool();
    private static ThreadPoolExecutor pool(){ThreadPoolExecutor p=new ThreadPoolExecutor(4,4,30,TimeUnit.SECONDS,new ArrayBlockingQueue<Runnable>(16),r->{Thread t=new Thread(r,"collie-uwb-oem-rpc");t.setDaemon(true);return t;});p.allowCoreThreadTimeOut(true);return p;}
    private static final ScheduledThreadPoolExecutor TIMERS=timers();
    private static ScheduledThreadPoolExecutor timers(){ScheduledThreadPoolExecutor p=new ScheduledThreadPoolExecutor(1,r->{Thread t=new Thread(r,"collie-uwb-oem-deadline");t.setDaemon(true);return t;});p.setRemoveOnCancelPolicy(true);p.setKeepAliveTime(30,TimeUnit.SECONDS);p.allowCoreThreadTimeOut(true);return p;}
    interface Call {void run()throws Exception;}
    static final class Provider {
        final ComponentName component;final int uid;final String permission;final boolean trusted,fixture;
        Provider(ComponentName component,int uid,String permission,boolean trusted,boolean fixture){this.component=component;this.uid=uid;this.permission=permission;this.trusted=trusted;this.fixture=fixture;}
        JSONObject info()throws Exception{return VmHardware.object("component",component.flattenToString(),"uid",uid,"permission",permission,"trusted_system_provider",trusted,"debug_signature_fixture",fixture);}
    }
    static Provider provider(VmHardware.Context c)throws Exception{
        PackageManager pm=c.host.getPackageManager();List<ResolveInfo> matches=pm.queryIntentServices(new Intent(ACTION).setPackage(PACKAGE),0);
        if(matches.size()>1)throw new VmHardware.Failure("invalid_response","Multiple OEM UWB services match the pinned protocol action.");if(matches.isEmpty())return null;
        ServiceInfo s=matches.get(0).serviceInfo;if(s==null||!PACKAGE.equals(s.packageName)||!s.exported||!s.enabled||!s.applicationInfo.enabled)return null;
        boolean trusted=(s.applicationInfo.flags&(ApplicationInfo.FLAG_SYSTEM|ApplicationInfo.FLAG_UPDATED_SYSTEM_APP))!=0;
        boolean fixture=(c.host.getApplicationInfo().flags&ApplicationInfo.FLAG_DEBUGGABLE)!=0&&(s.applicationInfo.flags&ApplicationInfo.FLAG_DEBUGGABLE)!=0&&pm.checkSignatures(c.host.getPackageName(),s.packageName)==PackageManager.SIGNATURE_MATCH;
        return new Provider(new ComponentName(s.packageName,s.name),s.applicationInfo.uid,s.permission==null?"":s.permission,trusted,fixture);
    }
    static JSONObject base(VmHardware.Context c)throws Exception{Provider p=provider(c);return VmHardware.object("sdk",Build.VERSION.SDK_INT,"backend","aosp","feature",HardwareUwb.feature(c),"public_ranging_api",false,"legacy_aosp_binding_implemented",true,"protocol","androidx.core.uwb.backend.v1","provider",p==null?JSONObject.NULL:p.info(),"provider_present",p!=null,"provider_usable",p!=null&&(p.trusted||p.fixture),"availability_known",false,"available",JSONObject.NULL,"observer_slots_available",HardwareUwb.WATCHES.availablePermits(),"session_slots_available",HardwareUwb.SESSIONS.availablePermits());}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{JSONObject row=base(c);out.put(row.put("id","uwb_ranging").put("implemented",true).put("permission","uwb").put("supported",Build.VERSION.SDK_INT>=31&&HardwareUwb.feature(c)&&row.getBoolean("provider_usable")?JSONObject.NULL:false));}
    static Provider require(VmHardware.Context c)throws Exception{
        if(Build.VERSION.SDK_INT<31||!HardwareUwb.feature(c))throw new VmHardware.Failure("unsupported","OEM UWB requires Android12+ and the actual UWB hardware declaration.");
        Provider p=provider(c);if(p==null)throw new VmHardware.Failure("unavailable","No enabled exported OEM AndroidX UWB backend is installed.");if(!p.trusted&&!p.fixture)throw new VmHardware.Failure("untrusted_provider","OEM UWB requires a system provider; only debuggable same-signature fixtures are accepted in debug builds.");
        VmHardware.require(c,PERMISSION);if(!p.permission.isEmpty())VmHardware.require(c,p.permission);return p;
    }
    static JSONArray ints(int[] values)throws Exception{if(values==null)throw new VmHardware.Failure("invalid_response","The OEM provider returned a null capability list.");if(values.length>256)throw new VmHardware.Failure("size_limit","OEM UWB capability lists contain at most256 values.");JSONArray a=new JSONArray();for(int n:values)a.put(n);return a;}
    static JSONObject caps(RangingCapabilities c)throws Exception{if(c==null||c.minRangingInterval<0)throw new VmHardware.Failure("invalid_response","The OEM provider returned invalid capabilities.");return VmHardware.object("distance_supported",c.supportsDistance,"azimuth_supported",c.supportsAzimuthalAngle,"elevation_supported",c.supportsElevationAngle,"minimum_interval_ms",c.minRangingInterval,"channels",ints(c.supportedChannels),"notification_configs",ints(c.supportedNtfConfigs),"config_ids",ints(c.supportedConfigIds),"slot_durations",ints(c.supportedSlotDurations),"update_rates",ints(c.supportedRangingUpdateRates),"interval_reconfiguration_supported",c.supportsRangingIntervalReconfigure,"background_supported",c.hasBackgroundRangingSupport);}
    static UwbAddress address(byte[] bytes){UwbAddress a=new UwbAddress();a.address=bytes.clone();return a;}
    static boolean contains(JSONArray values,int wanted)throws Exception{for(int i=0;i<values.length();i++)if(values.getInt(i)==wanted)return true;return false;}
    static Object measurement(RangingMeasurement m)throws Exception{if(m==null)return JSONObject.NULL;if(!Float.isFinite(m.value)||m.confidence<0||m.confidence>2)throw new VmHardware.Failure("invalid_response","Malformed OEM UWB measurement.");return VmHardware.object("value",VmHardware.real(m.value),"confidence",m.confidence,"confidence_known",true,"validity_known",false);}
    static abstract class Base extends VmHardware.Handle {
        final VmHardware.Context context;final Provider provider;final Semaphore capacity;final int role;final long deadline;
        final CountDownLatch ready=new CountDownLatch(1);final ServiceConnection connection;
        final IBinder.DeathRecipient death=()->lost("binder_died");
        IUwb service;IUwbClient client;IBinder binder;JSONObject capability,error,operationError,cleanupError;ScheduledFuture<?> timer;
        boolean bindStarting,bindAttempted,bindReturned,bound,connected,initializing,deathLinked,preparationComplete,retired,cleanupWanted,cleanupQueued,cleanupAgain,released,providerDead,expired;int io,serviceVersion,clientVersion,rejectedCallers;String state="preparing";
        Base(VmHardware.Context c,Provider p,String kind,Semaphore capacity,int role,int timeout){super(c,"uwb",kind);context=c;provider=p;this.capacity=capacity;this.role=role;deadline=SystemClock.elapsedRealtime()+timeout;
            connection=new ServiceConnection(){public void onServiceConnected(ComponentName name,IBinder value){connected(name,value);}public void onServiceDisconnected(ComponentName name){lost("service_disconnected");}public void onBindingDied(ComponentName name){lost("binding_died");}public void onNullBinding(ComponentName name){lost("null_binding");}};
            synchronized(LEASES){for(Base old:LEASES)old.retryCleanup();LEASES.add(this);}
        }
        synchronized boolean live(){return !closed&&!retired&&!released;}
        void event(String name,Object... fields){synchronized(this){if(closed)return;}try{Object[] a=new Object[fields.length+4];a[0]="event";a[1]=name;a[2]="backend";a[3]="aosp";System.arraycopy(fields,0,a,4,fields.length);emit(VmHardware.object(a));}catch(Exception ignored){}}
        void start()throws Exception{
            VmHardware.blocking(this);synchronized(this){if(!live()){VmHardware.unblocking();return;}bindStarting=true;bindAttempted=true;}
            try{timer=TIMERS.schedule(this::expire,Math.max(0,deadline-SystemClock.elapsedRealtime()),TimeUnit.MILLISECONDS);VmHardware.check();boolean accepted=context.host.getApplicationContext().bindService(new Intent(ACTION).setComponent(provider.component),connection,android.content.Context.BIND_AUTO_CREATE);synchronized(this){bindReturned=accepted;if(!accepted)fail(new VmHardware.Failure("unavailable","Android refused the OEM UWB service binding."));}}
            catch(Exception e){fail(e);throw e;}finally{synchronized(this){bindStarting=false;if(cleanupWanted)cleanup();else if(connected)initialize();}VmHardware.unblocking();}
        }
        synchronized void connected(ComponentName name,IBinder value){
            if(released)return;if(!provider.component.equals(name)||value==null){fail(new VmHardware.Failure("invalid_response","Unexpected OEM service connection identity."));return;}
            connected=true;bound=true;binder=value;service=IUwb.Stub.asInterface(value);if(!bindStarting&&!cleanupWanted)initialize();else if(cleanupWanted)cleanup();
        }
        synchronized void initialize(){if(!live()||initializing||io!=0)return;initializing=true;submit(()->{
            final IBinder current;synchronized(this){if(!live())return;current=binder;}if(!IUwb.DESCRIPTOR.equals(current.getInterfaceDescriptor()))throw new VmHardware.Failure("unsupported_protocol","OEM Binder does not implement the pinned UWB protocol.");current.linkToDeath(death,0);synchronized(this){deathLinked=true;}
            int rootVersion=service.getInterfaceVersion();if(rootVersion<1)throw new VmHardware.Failure("unsupported_protocol","OEM UWB root protocol version is unsupported.");IUwbClient sdk=role==1?service.getControllerClient():service.getControleeClient();if(sdk==null)throw new VmHardware.Failure("invalid_response","OEM UWB returned no session client.");int version=sdk.getInterfaceVersion();if(version<1)throw new VmHardware.Failure("unsupported_protocol","OEM UWB client protocol version is unsupported.");
            synchronized(this){client=sdk;serviceVersion=rootVersion;clientVersion=version;if(!live())return;}JSONObject actual=caps(sdk.getRangingCapabilities());synchronized(this){capability=actual;}prepared(sdk);
        });}
        synchronized boolean submit(Call action){
            io++;try{RPC.execute(()->{try{action.run();}catch(Exception e){fail(e);}finally{synchronized(this){io--;if(cleanupWanted)cleanup();}}});return true;}
            catch(RejectedExecutionException e){io--;fail(new VmHardware.Failure("busy","OEM UWB RPC workers are occupied."));return false;}
        }
        abstract void prepared(IUwbClient sdk)throws Exception;
        abstract boolean cleanupRpc()throws Exception;
        synchronized void expire(){if(released||retired||preparationComplete||SystemClock.elapsedRealtime()<deadline)return;expired=true;fail(new VmHardware.Failure("timeout","OEM UWB preparation exceeded its wall deadline."));}
        synchronized void prepared(){if(!live())return;if(SystemClock.elapsedRealtime()>=deadline){expire();return;}preparationComplete=true;state="prepared";if(timer!=null)timer.cancel(false);timer=null;ready.countDown();event("prepared","sdk_rpc",true);}
        synchronized void fail(Exception e){if(released)return;try{JSONObject actual=VmHardware.object("code",e instanceof VmHardware.Failure?((VmHardware.Failure)e).code:e instanceof SecurityException?"permission_denied":e instanceof RemoteException?"disconnected":"api_error","message",MainActivity.safe(e));if(error==null)error=actual;else operationError=actual;}catch(Exception ignored){}retired=true;cleanupWanted=true;state="failed";if(timer!=null)timer.cancel(false);timer=null;ready.countDown();event("error","error",error,"operation_error",operationError==null?JSONObject.NULL:operationError);cleanup();}
        synchronized void lost(String reason){if(released)return;providerDead=true;fail(new VmHardware.Failure("disconnected","OEM UWB provider lost: "+reason+". Hardware effects are not inferred."));}
        boolean caller(){if(Binder.getCallingUid()!=provider.uid){synchronized(this){rejectedCallers++;}return false;}if(context.host.checkSelfPermission(PERMISSION)!=PackageManager.PERMISSION_GRANTED){close();return false;}return true;}
        synchronized void retryCleanup(){if(cleanupWanted&&!released)cleanup();}
        synchronized void cleanup(){
            if(released||bindStarting||io!=0)return;if(cleanupQueued){cleanupAgain=true;return;}cleanupQueued=true;cleanupAgain=false;
            try{HardwareUwb.CLEANUP.execute(()->{
                boolean complete=false;
                try{
                    if(!providerDead&&!cleanupRpc())return;
                    if(bindAttempted)try{context.host.getApplicationContext().unbindService(connection);}catch(IllegalArgumentException notRegistered){}
                    if(binder!=null&&deathLinked)try{binder.unlinkToDeath(death,0);}catch(NoSuchElementException alreadyUnlinked){}complete=true;
                }catch(Exception e){synchronized(this){try{cleanupError=VmHardware.object("message",MainActivity.safe(e));}catch(Exception ignored){}}}
                finally{synchronized(this){cleanupQueued=false;if(complete){released=true;bound=false;client=null;service=null;binder=null;if(!state.equals("failed"))state="closed";capacity.release();event("closed","local_binding_released",true,"provider_close_status_known",false);}else if(cleanupAgain)cleanup();}if(complete)synchronized(LEASES){LEASES.remove(this);}}
            });}catch(RejectedExecutionException full){cleanupQueued=false;TIMERS.schedule(this::retryCleanup,250,TimeUnit.MILLISECONDS);}
        }
        synchronized JSONObject status()throws Exception{return VmHardware.object("kind",kind,"backend","aosp","provider",provider.info(),"state",state,"preparation_deadline_expired",expired,"bind_returned",bindReturned,"service_connected",connected,"bound",bound,"service_protocol_version",serviceVersion,"client_protocol_version",clientVersion,"capabilities",capability==null?JSONObject.NULL:capability,"rpc_in_flight",io,"cleanup_pending",cleanupWanted&&!released,"lease_released",released,"provider_dead",providerDead,"rejected_caller_callbacks",rejectedCallers,"provider_close_status_known",false,"error",error==null?JSONObject.NULL:error,"cleanup_error",cleanupError==null?JSONObject.NULL:cleanupError,"operation_error",operationError==null?JSONObject.NULL:operationError);}
        void access(VmHardware.Context c)throws Exception{super.access(c);if(c.host.checkSelfPermission(PERMISSION)!=PackageManager.PERMISSION_GRANTED){close();throw new VmHardware.Failure("permission_revoked","Android UWB access was revoked. Reopen after granting access.");}}
        public synchronized void close(){if(!closed){closed=true;events.clear();retired=true;cleanupWanted=true;if(timer!=null)timer.cancel(false);timer=null;ready.countDown();}cleanup();}
    }
    static final class Watch extends Base {
        boolean subscribed;Boolean available;int reason;
        final IUwbAvailabilityObserver observer=new IUwbAvailabilityObserver.Stub(){public int getInterfaceVersion(){return IUwbAvailabilityObserver.VERSION;}public void onUwbStateChanged(boolean value,int why){if(!caller())return;synchronized(Watch.this){if(!live())return;available=value;reason=why;event("capabilities","available",value,"sdk_reason",why,"sdk_callback",true);}}};
        Watch(VmHardware.Context c,Provider p){super(c,p,"uwb_aosp_capabilities",HardwareUwb.WATCHES,1,8000);}
        void prepared(IUwbClient sdk)throws Exception{boolean value=sdk.isAvailable();synchronized(this){if(!live())return;available=value;subscribed=true;}sdk.subscribeToAvailability(observer);synchronized(this){prepared();event("capabilities","available",available==null?JSONObject.NULL:available,"capabilities",capability,"sdk_rpc",true);}}
        boolean cleanupRpc()throws Exception{if(client!=null&&subscribed){client.unsubscribeFromAvailability();subscribed=false;}return true;}
        public synchronized Object info()throws Exception{check();return status().put("availability_known",available!=null).put("available",available==null?JSONObject.NULL:available).put("sdk_reason",reason);}
    }
    static final class Request {
        final String id="uwb-request-"+UUID.randomUUID(),operation;final long deadline;
        boolean started,returned,complete,expired;Boolean effect;JSONObject error,operationError;ScheduledFuture<?> timer;
        Request(String operation,int timeout){this.operation=operation;deadline=SystemClock.elapsedRealtime()+timeout;}
        JSONObject info()throws Exception{return VmHardware.object("id",id,"operation",operation,"sdk_rpc_started",started,"sdk_rpc_returned",returned,"rpc_complete",complete,"deadline_expired",expired,"effect_confirmed",effect==null?JSONObject.NULL:effect,"error",error==null?JSONObject.NULL:error,"operation_error",operationError==null?JSONObject.NULL:operationError);}
    }
    static final class Peer {
        final HardwareUwbGms.Peer value;boolean removing,removed,seen,removeRpcReturned,suspended;
        Peer(HardwareUwbGms.Peer value){this.value=value;}
    }
    static final class Range extends Base {
        final LinkedHashMap<UUID,Peer> peers=new LinkedHashMap<>();final LinkedHashMap<String,Request> requests=new LinkedHashMap<>();
        byte[] local;UwbComplexChannel channel;HardwareUwbGms.Peer group;Request pending,startRequest;
        boolean prepared,startSubmitted,startRpcStarted,startReturned,initialized,opened,startRejected,terminalObserved,stopRpcStarted,stopRpcFinished,stopCallbackObserved;int discardedCallbacks;ScheduledFuture<?> openTimer;
        final IRangingSessionCallback callback=new IRangingSessionCallback.Stub(){
            public int getInterfaceVersion(){return IRangingSessionCallback.VERSION;}
            public void onRangingInitialized(UwbDevice device){if(!caller())return;try{byte[] a=deviceAddress(device);synchronized(Range.this){if(!live()||!startRpcStarted||!Arrays.equals(a,local)){discardedCallbacks++;return;}initialized=true;if(startRequest!=null&&!startRequest.expired)startRequest.effect=true;maybeOpened();}}catch(Exception e){fail(e);}}
            public void onRangingResult(UwbDevice device,RangingPosition position){if(!caller())return;try{byte[] a=deviceAddress(device);synchronized(Range.this){if(!live())return;Peer p=find(a);if(p==null||p.removing||p.removed){discardedCallbacks++;return;}if(position==null||position.elapsedRealtimeNanos<0)throw new VmHardware.Failure("invalid_response","Malformed OEM UWB ranging position.");p.seen=true;event("ranging","id",p.value.id.toString(),"address",VmHardware.bytes(a),"technology",0,"timestamp_ns",position.elapsedRealtimeNanos,"timestamp_ms",position.elapsedRealtimeNanos/1000000,"distance_m",measurement(position.distance),"azimuth_degrees",measurement(position.azimuth),"elevation_degrees",measurement(position.elevation),"rssi_dbm",JSONObject.NULL,"sdk_callback",true);}}catch(Exception e){fail(e);}}
            public void onRangingSuspended(UwbDevice device,int reason){if(!caller())return;try{byte[] a=deviceAddress(device);synchronized(Range.this){if(released)return;boolean session=Arrays.equals(a,local);Peer p=session?null:find(a);if(!session&&p==null){discardedCallbacks++;return;}
                if(session){terminalObserved=true;if(reason==IRangingSessionCallback.STOP_RANGING_CALLED&&stopRpcStarted)stopCallbackObserved=true;if(!initialized&&(reason==IRangingSessionCallback.WRONG_PARAMETERS||reason==IRangingSessionCallback.FAILED_TO_START)){startRejected=true;if(startRequest!=null)startRequest.effect=false;}retired=true;cleanupWanted=true;if(!state.equals("failed"))state="suspended";if(openTimer!=null)openTimer.cancel(false);}
                else{p.suspended=reason==IRangingSessionCallback.STOPPED_BY_PEER;if(p.removing&&p.removeRpcReturned&&p.suspended)p.removed=true;}
                event("suspended","scope",session?"session":"peer","id",session?JSONObject.NULL:p.value.id.toString(),"address",VmHardware.bytes(a),"sdk_reason",reason,"sdk_callback",true);if(cleanupWanted)cleanup();
            }}catch(Exception e){fail(e);}}
        };
        Range(VmHardware.Context c,Provider p,int role,int timeout){super(c,p,"uwb_aosp_session",HardwareUwb.SESSIONS,role,timeout);}
        void prepared(IUwbClient sdk)throws Exception{UwbAddress allocated=sdk.getLocalAddress();byte[] a=allocated==null?null:allocated.address;if(a==null)throw new VmHardware.Failure("invalid_response","OEM provider returned no local address.");a=HardwareUwbGms.address(VmHardware.bytes(a));UwbComplexChannel selected=role==1?sdk.getComplexChannel():null;if(role==1&&(selected==null||selected.channel<=0||selected.channel>255||selected.preambleIndex<=0||selected.preambleIndex>255))throw new VmHardware.Failure("invalid_response","Invalid OEM controller complex channel.");synchronized(this){if(!live())return;local=a.clone();channel=selected;prepared=true;prepared();}}
        static byte[] deviceAddress(UwbDevice d)throws Exception{if(d==null||d.address==null||d.address.address==null)throw new VmHardware.Failure("invalid_response","OEM callback has no device address.");return HardwareUwbGms.address(VmHardware.bytes(d.address.address));}
        Peer find(byte[] address){for(Peer p:peers.values())if(Arrays.equals(p.value.address,address))return p;return null;}
        synchronized void usable()throws Exception{check();if(!live()||!prepared)throw new VmHardware.Failure("invalid_state","Wait for preparation and use a new session after failure, stop or close.");}
        synchronized void active()throws Exception{usable();if(!opened)throw new VmHardware.Failure("not_ready","Wait for actual OEM start return and initialized callback.");}
        synchronized void maybeOpened(){if(!live()||!startReturned||!initialized||opened)return;opened=true;state="active";if(openTimer!=null)openTimer.cancel(false);openTimer=null;event("opened","sdk_rpc_returned",true,"sdk_initialized",true);}
        synchronized String invoke(String name,Call call,Call before,Call after)throws Exception{
            usable();if(pending!=null)throw new VmHardware.Failure("busy","An OEM UWB mutation is still executing.");before.run();while(requests.size()>=16){String first=requests.keySet().iterator().next();requests.remove(first);}Request r=new Request(name,8000);requests.put(r.id,r);pending=r;
            r.timer=TIMERS.schedule(()->{synchronized(Range.this){if(r.complete||released)return;r.expired=true;try{r.error=VmHardware.object("code","timeout","message","OEM RPC deadline expired; completion may be uncertain.");}catch(Exception ignored){}fail(new VmHardware.Failure("timeout","OEM UWB RPC expired; no mutation is replayed."));}},8000,TimeUnit.MILLISECONDS);
            boolean accepted=submit(()->{try{synchronized(this){if(!live())throw new VmHardware.Failure("cancelled","OEM UWB operation retired before its RPC started.");r.started=true;if(name.equals("start"))startRpcStarted=true;}call.run();synchronized(this){r.returned=true;r.expired|=SystemClock.elapsedRealtime()>=r.deadline;if(name.equals("start"))startReturned=true;if(r.expired&&!retired)fail(new VmHardware.Failure("timeout","OEM RPC returned after its wall deadline; no mutation is replayed."));if(!r.expired)after.run();}}catch(Exception e){synchronized(this){JSONObject actual=VmHardware.object("code",e instanceof VmHardware.Failure?((VmHardware.Failure)e).code:e instanceof RemoteException?"disconnected":"api_error","message",MainActivity.safe(e));if(r.error==null)r.error=actual;else r.operationError=actual;}throw e;}finally{settle(r);}});if(!accepted){r.error=VmHardware.object("code","busy","message","OEM RPC worker queue rejected this request before invocation.");settle(r);}return r.id;
        }
        synchronized void settle(Request r){r.complete=true;if(r.timer!=null)r.timer.cancel(false);if(pending==r)pending=null;event("request_completed","request",r.id,"sdk_rpc_returned",r.returned,"effect_confirmed",r.effect==null?JSONObject.NULL:r.effect);}
        synchronized String start(JSONArray rows,JSONArray options)throws Exception{
            usable();if(startSubmitted)throw new VmHardware.Failure("invalid_state","An OEM session starts once; prepare a new session to restart.");
            HardwareUwb.list(rows,1,role==0?1:8);HardwareUwb.list(options,7,7);int angles=VmHardware.integer(options,0,0,1),count=VmHardware.integer(options,1,0,65535),fusion=VmHardware.integer(options,2,0,1),notification=VmHardware.integer(options,3,0,3),near=VmHardware.integer(options,4,0,20000),far=VmHardware.integer(options,5,0,20000),timeout=VmHardware.integer(options,6,500,120000);
            if(count!=0||fusion!=0)throw new VmHardware.Failure("unsupported_operation","The pinned OEM v1 protocol has no measurement-limit or sensor-fusion field.");if(near>far)throw new VmHardware.Failure("invalid_argument","UWB near distance exceeds far distance.");
            ArrayList<Peer> parsed=new ArrayList<>();HashSet<String> ids=new HashSet<>(),addresses=new HashSet<>();HardwareUwbGms.Peer selected=null;
            for(int i=0;i<rows.length();i++){HardwareUwbGms.Peer p=new HardwareUwbGms.Peer(rows.get(i));if(!Arrays.equals(p.local,local)||!ids.add(p.id.toString())||!addresses.add(Arrays.toString(p.address))||(selected!=null&&!selected.same(p)))throw new VmHardware.Failure("invalid_argument","Use unique peers with the prepared local address and shared session parameters.");if(role==1&&(p.channel!=channel.channel||p.preamble!=channel.preambleIndex))throw new VmHardware.Failure("invalid_argument","Use the actual prepared controller channel/preamble.");if(Arrays.equals(p.address,local))throw new VmHardware.Failure("invalid_argument","A UWB peer cannot use the local address.");parsed.add(new Peer(p));selected=p;}
            final HardwareUwbGms.Peer p=selected;if(!contains(capability.getJSONArray("config_ids"),p.config)||!contains(capability.getJSONArray("channels"),p.channel)||!contains(capability.getJSONArray("slot_durations"),p.slot)||!contains(capability.getJSONArray("update_rates"),p.rate)||!contains(capability.getJSONArray("notification_configs"),notification))throw new VmHardware.Failure("unsupported_operation","The actual OEM capabilities do not advertise those session parameters.");if((p.config==1||p.config==4)&&parsed.size()!=1)throw new VmHardware.Failure("invalid_argument","A unicast UWB profile requires exactly one peer.");if(p.channel==0||p.preamble==0)throw new VmHardware.Failure("invalid_argument","Negotiate an explicit nonzero channel and preamble.");
            RangingParameters parameters=new RangingParameters();parameters.uwbConfigId=p.config;parameters.sessionId=p.session;parameters.subSessionId=p.subSet?p.sub:0;parameters.sessionKeyInfo=p.key.clone();parameters.subSessionKeyInfo=p.subKey.clone();parameters.rangingUpdateRate=p.rate;parameters.slotDuration=p.slot;parameters.isAoaDisabled=angles==0;parameters.complexChannel=new UwbComplexChannel();parameters.complexChannel.channel=p.channel;parameters.complexChannel.preambleIndex=p.preamble;parameters.peerDevices=new ArrayList<>();for(Peer peer:parsed){UwbDevice d=new UwbDevice();d.address=address(peer.value.address);parameters.peerDevices.add(d);}parameters.uwbRangeDataNtfConfig=new UwbRangeDataNtfConfig();parameters.uwbRangeDataNtfConfig.rangeDataNtfConfigType=notification;parameters.uwbRangeDataNtfConfig.ntfProximityNearCm=near;parameters.uwbRangeDataNtfConfig.ntfProximityFarCm=far;
            String id=invoke("start",()->client.startRanging(parameters,callback),()->{for(Peer peer:parsed)peers.put(peer.value.id,peer);group=p;startSubmitted=true;state="starting";openTimer=TIMERS.schedule(()->{synchronized(Range.this){if(!opened&&!retired)fail(new VmHardware.Failure("timeout","OEM initialization callback did not arrive before its wall deadline."));}},timeout,TimeUnit.MILLISECONDS);},()->{startReturned=true;maybeOpened();});startRequest=requests.get(id);if(initialized)startRequest.effect=true;return id;
        }
        synchronized int stop(){if(cleanupWanted)return 0;retired=true;cleanupWanted=true;state="stopping";if(openTimer!=null)openTimer.cancel(false);cleanup();return 1;}
        boolean cleanupRpc()throws Exception{
            synchronized(this){if(openTimer!=null)openTimer.cancel(false);if(!startRpcStarted||startRejected||client==null)return true;if(stopRpcStarted)return stopRpcFinished&&terminalObserved;stopRpcStarted=true;}
            try{client.stopRanging(callback);}finally{synchronized(this){stopRpcFinished=true;}}
            synchronized(this){return terminalObserved;}
        }
        public synchronized void close(){if(openTimer!=null)openTimer.cancel(false);openTimer=null;super.close();}
        public synchronized Object info()throws Exception{check();JSONArray rows=new JSONArray();for(Peer p:peers.values())rows.put(VmHardware.object("id",p.value.id.toString(),"address",VmHardware.bytes(p.value.address),"removing",p.removing,"removed",p.removed,"seen_in_callback",p.seen));return status().put("role",role).put("prepared",prepared).put("local_address",local==null?JSONObject.NULL:VmHardware.bytes(local)).put("channel",channel==null?JSONObject.NULL:channel.channel).put("preamble_index",channel==null?JSONObject.NULL:channel.preambleIndex).put("start_rpc_submitted",startSubmitted).put("start_rpc_returned",startReturned).put("sdk_initialized",initialized).put("start_rejected",startRejected).put("stop_rpc_started",stopRpcStarted).put("stop_rpc_finished",stopRpcFinished).put("sdk_terminal_observed",terminalObserved).put("stop_callback_observed",stopCallbackObserved).put("pending_request",pending==null?JSONObject.NULL:pending.id).put("peers",rows).put("discarded_peer_callbacks",discardedCallbacks);}
    }
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(op.equals("uwb_info"))return base(c);
        if(op.equals("uwb_watch")){Provider p=require(c);if(!HardwareUwb.WATCHES.tryAcquire())throw new VmHardware.Failure("resource_limit","At most8 UWB observers including pending cleanup.");Watch w;try{w=new Watch(c,p);}catch(Exception e){HardwareUwb.WATCHES.release();throw e;}try{String id=VmHardware.add(w);w.start();return id;}catch(Exception e){w.close();throw e;}}
        if(op.equals("uwb_prepare")){int role=VmHardware.integer(a,0,0,1),timeout=VmHardware.integer(a,1,500,30000);Provider p=require(c);if(!HardwareUwb.SESSIONS.tryAcquire())throw new VmHardware.Failure("resource_limit","At most8 UWB sessions including pending cleanup.");Range r;try{r=new Range(c,p,role,timeout);}catch(Exception e){HardwareUwb.SESSIONS.release();throw e;}try{String id=VmHardware.add(r);r.start();return id;}catch(Exception e){r.close();throw e;}}
        if(op.equals("uwb_range"))throw new VmHardware.Failure("unsupported_operation","OEM UWB uses allocated addresses: prepare, exchange device_info parameters, then start.");
        Range r=VmHardware.handle(c,VmHardware.text(a,0,128),Range.class);r.access(c);
        if(op.equals("uwb_start"))return r.start(HardwareUwb.list(a.get(1),1,8),HardwareUwb.list(a.get(2),7,7));
        if(op.equals("uwb_request")){String id=VmHardware.text(a,1,128);synchronized(r){Request request=r.requests.get(id);if(request==null)throw new VmHardware.Failure("stale_request","Unknown or evicted OEM UWB request ID.");return request.info();}}
        if(op.equals("uwb_stop"))return r.stop();
        synchronized(r){r.active();if(r.role!=1&&!op.equals("uwb_notifications"))throw new VmHardware.Failure("unsupported_operation","Only the controller can change peers or intervals.");}
        if(op.equals("uwb_interval")){int skip=VmHardware.integer(a,1,0,255);synchronized(r){if(!r.capability.getBoolean("interval_reconfiguration_supported"))throw new VmHardware.Failure("unsupported_operation","The OEM does not advertise interval reconfiguration.");return r.invoke("interval",()->r.client.reconfigureRangingInterval(skip),()->r.active(),()->{});}}
        if(op.equals("uwb_notifications")){int mode=VmHardware.integer(a,1,0,3),near=VmHardware.integer(a,2,0,20000),far=VmHardware.integer(a,3,0,20000);if(near>far)throw new VmHardware.Failure("invalid_argument","UWB near distance exceeds far distance.");synchronized(r){if(!contains(r.capability.getJSONArray("notification_configs"),mode))throw new VmHardware.Failure("unsupported_operation","OEM notification mode is not advertised.");return r.invoke("notifications",()->r.client.reconfigureRangeDataNtf(mode,near,far),()->r.active(),()->{});}}
        if(op.equals("uwb_remove")){String text=VmHardware.text(a,1,36);UUID id;try{id=UUID.fromString(text);if(!id.toString().equalsIgnoreCase(text))throw new IllegalArgumentException();}catch(Exception e){throw new VmHardware.Failure("invalid_argument","Choose a canonical UWB peer UUID.");}
            synchronized(r){Peer p=r.peers.get(id);if(p==null||p.removing||p.removed)throw new VmHardware.Failure("unknown_peer","Choose an active peer owned by this session.");return r.invoke("remove",()->r.client.removeControlee(address(p.value.address)),()->{r.active();p.removing=true;p.suspended=false;},()->{p.removeRpcReturned=true;if(p.suspended)p.removed=true;});}}
        if(op.equals("uwb_add")){HardwareUwbGms.Peer value=new HardwareUwbGms.Peer(a.get(1));Peer peer=new Peer(value);synchronized(r){
            if(!value.same(r.group)||!Arrays.equals(value.local,r.local)||Arrays.equals(value.address,r.local))throw new VmHardware.Failure("invalid_argument","Use the prepared session parameters and a remote address.");
            if(r.peers.size()>=64)throw new VmHardware.Failure("resource_limit","At most64 lifetime peer identities are retained; prepare a new session.");int active=0;for(Peer old:r.peers.values()){if(!old.removed)active++;if(old.value.id.equals(value.id)||Arrays.equals(old.value.address,value.address))throw new VmHardware.Failure("invalid_argument","Peer UUIDs and addresses cannot be reassigned within a session.");}if(active>=8)throw new VmHardware.Failure("resource_limit","At most8 active peers including pending removals.");
            RangingControleeParameters parameters=new RangingControleeParameters();parameters.address=address(value.address);parameters.subSessionId=value.subSet?value.sub:0;parameters.subSessionKey=value.subKey.clone();
            return r.invoke("add",()->{if(value.subKey.length>0)r.client.addControleeWithSessionParams(parameters);else r.client.addControlee(parameters.address);},()->{r.active();r.peers.put(value.id,peer);},()->{});
        }}
        throw new VmHardware.Failure("unsupported_operation","Unknown OEM UWB operation.");
    }
}
