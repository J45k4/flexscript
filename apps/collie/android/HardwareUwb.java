package org.flexscript.collie;

import android.content.pm.PackageManager;
import android.os.Build;
import android.ranging.*;
import android.ranging.raw.*;
import android.ranging.uwb.*;
import java.io.IOException;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Public Android ranging objects and copied UWB callbacks. Peer negotiation stays in Flexscript. */
final class HardwareUwb {
    static final Semaphore WATCHES=new Semaphore(8),SESSIONS=new Semaphore(8);
    static final ThreadPoolExecutor CLEANUP=new ThreadPoolExecutor(2,2,30,TimeUnit.SECONDS,new ArrayBlockingQueue<Runnable>(16),task->{Thread t=new Thread(task,"collie-uwb-cleanup");t.setDaemon(true);return t;});
    static boolean supports(String op){return op.startsWith("uwb_");}
    static boolean feature(VmHardware.Context c){return c.host.getPackageManager().hasSystemFeature("android.hardware.uwb");}
    static boolean api(){return Build.VERSION.SDK_INT>=36;}
    static boolean legacyGms(VmHardware.Context c){return Build.VERSION.SDK_INT>=31&&HardwareUwbGms.status(c)==0&&!(c.host.getPackageManager().hasSystemFeature("cn.google.services")&&c.host.getPackageManager().hasSystemFeature("com.google.android.feature.services_updater"));}
    static Object legacy(VmHardware.Context c,String op,JSONArray a)throws Exception{return legacyGms(c)?HardwareUwbGms.call(c,op,a):HardwareUwbAosp.call(c,op,a);}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{if(!api()){if(legacyGms(c))HardwareUwbGms.capabilities(c,out);else HardwareUwbAosp.capabilities(c,out);return;}boolean service=Api36.present(c);out.put(VmHardware.object("id","uwb_ranging","implemented",true,"supported",service&&feature(c),"available",JSONObject.NULL,"availability_known",false,"permission","uwb","sdk",Build.VERSION.SDK_INT,"public_ranging_api",service,"feature",feature(c),"observer_slots_available",WATCHES.availablePermits(),"session_slots_available",SESSIONS.availablePermits()));}
    static JSONArray list(Object value,int min,int max)throws Exception{if(!(value instanceof JSONArray)||((JSONArray)value).length()<min||((JSONArray)value).length()>max)throw new VmHardware.Failure("invalid_argument","Expected a bounded typed UWB list.");return (JSONArray)value;}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if((op.equals("uwb_info")||op.equals("uwb_watch"))&&a.length()>0){int backend=VmHardware.integer(a,0,0,3);if(backend==2)return HardwareUwbGms.call(c,op,a);if(backend==3)return HardwareUwbAosp.call(c,op,a);if(backend==1&&!api())throw new VmHardware.Failure("unsupported_operation","The system ranging backend requires Android16+.");}
        if(op.equals("uwb_prepare")){int backend=a.length()>2?VmHardware.integer(a,2,0,3):0;if(backend==1)throw new VmHardware.Failure("unsupported_operation","The system backend uses uwb_range with negotiated peers.");if(backend==2)return HardwareUwbGms.call(c,op,a);if(backend==3)return HardwareUwbAosp.call(c,op,a);return legacy(c,op,a);}
        if(op.equals("uwb_start")||op.equals("uwb_request")||op.equals("uwb_stop")||op.equals("uwb_add")||op.equals("uwb_remove")||op.equals("uwb_interval")||op.equals("uwb_notifications")){
            VmHardware.Handle h=VmHardware.handle(c,VmHardware.text(a,0,128));if(h instanceof HardwareUwbAosp.Range)return HardwareUwbAosp.call(c,op,a);if(h instanceof HardwareUwbGms.Range)return HardwareUwbGms.call(c,op,a);
            if(op.equals("uwb_notifications"))throw new VmHardware.Failure("unsupported_operation","The system ranging SDK does not expose range-data notification reconfiguration.");
        }
        if(!api())return legacy(c,op,a);
        return Api36.call(c,op,a);
    }
    static final class Api36 {
        static boolean present(VmHardware.Context c){return c.host.getSystemService(RangingManager.class)!=null;}
        static RangingManager manager(VmHardware.Context c)throws Exception{
            // Android16's RangingSessionManager retains its session map. Give each
            // owned resource a fresh service cache rather than growing the app cache.
            RangingManager value=c.host.createAttributionContext(null).getSystemService(RangingManager.class);
            if(value==null)throw new VmHardware.Failure("unsupported","Android's public ranging service is unavailable.");return value;
        }
        static JSONArray integers(List<Integer> values)throws Exception{if(values==null)return new JSONArray();if(values.size()>256)throw new VmHardware.Failure("size_limit","Android returned more than256 UWB capability values.");return new JSONArray(values);}
        static JSONObject snapshot(RangingCapabilities caps)throws Exception{
            if(caps==null)throw new VmHardware.Failure("invalid_response","Android returned null ranging capabilities.");
            Integer availability=caps.getTechnologyAvailability().get(RangingManager.UWB);JSONObject out=VmHardware.object("availability_known",availability!=null,"availability",availability==null?JSONObject.NULL:availability,"available",availability!=null&&availability==RangingCapabilities.ENABLED);UwbRangingCapabilities uwb=caps.getUwbCapabilities();
            out.put("uwb_capabilities_known",uwb!=null);if(uwb==null)return out;
            return out.put("distance_supported",uwb.isDistanceMeasurementSupported()).put("azimuth_supported",uwb.isAzimuthalAngleSupported()).put("elevation_supported",uwb.isElevationAngleSupported()).put("background_supported",uwb.isBackgroundRangingSupported()).put("interval_reconfiguration_supported",uwb.isRangingIntervalReconfigurationSupported()).put("minimum_interval_ms",uwb.getMinimumRangingInterval().toMillis()).put("channels",integers(uwb.getSupportedChannels())).put("config_ids",integers(uwb.getSupportedConfigIds())).put("notification_configs",integers(uwb.getSupportedNotificationConfigurations())).put("preamble_indexes",integers(uwb.getSupportedPreambleIndexes())).put("update_rates",integers(uwb.getSupportedRangingUpdateRates())).put("slot_durations",integers(uwb.getSupportedSlotDurations()));
        }
        static final class Watch extends VmHardware.Handle {
            RangingManager sdk;final CountDownLatch ready=new CountDownLatch(1);boolean starting,registered,cleanupQueued,released;String cleanupError="";JSONObject latest;
            final RangingManager.RangingCapabilitiesCallback callback=caps->{try{JSONObject value=snapshot(caps);synchronized(this){if(closed)return;latest=value;emit(VmHardware.object("event","capabilities","uwb",value,"sdk_callback",true));ready.countDown();}}catch(Exception error){synchronized(this){if(!closed){try{emit(VmHardware.object("event","error","code","invalid_response","message",MainActivity.safe(error)));}catch(Exception ignored){}ready.countDown();}}}};
            Watch(VmHardware.Context c)throws Exception{super(c,"uwb","uwb_capabilities");sdk=manager(c);}
            void start()throws Exception{synchronized(this){check();starting=true;}try{sdk.registerCapabilitiesCallback(task->HardwareSensors.events().post(task),callback);}finally{synchronized(this){starting=false;registered=true;if(closed)cleanup();}}}
            synchronized void cleanup(){if(starting||cleanupQueued||released)return;cleanupQueued=true;CLEANUP.execute(()->{try{if(registered)sdk.unregisterCapabilitiesCallback(callback);synchronized(this){registered=false;sdk=null;released=true;WATCHES.release();}}catch(Exception error){synchronized(this){cleanupError=MainActivity.safe(error);}}});}
            public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"snapshot",latest==null?JSONObject.NULL:latest,"availability_known",latest!=null&&latest.optBoolean("availability_known"),"cleanup_pending",closed&&!released,"cleanup_error",cleanupError);}
            public synchronized void close()throws IOException{if(closed)return;super.close();ready.countDown();cleanup();}
        }
        static Watch watch(VmHardware.Context c)throws Exception{if(!WATCHES.tryAcquire())throw new VmHardware.Failure("resource_limit","At most8 UWB capability observers, including cleanup, may be owned.");try{return new Watch(c);}catch(Exception error){WATCHES.release();throw error;}}
        static UUID uuid(JSONArray a,int at)throws Exception{String value=VmHardware.text(a,at,36);if(!value.matches("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"))throw new VmHardware.Failure("invalid_argument","A UWB peer requires a canonical UUID.");return UUID.fromString(value);}
        static UwbAddress address(Object value)throws Exception{byte[] bytes=VmHardware.data(value);if(bytes.length!=2&&bytes.length!=8)throw new VmHardware.Failure("invalid_argument","UWB addresses contain exactly2 or8 bytes.");return UwbAddress.fromBytes(bytes);}
        static byte[] key(Object value)throws Exception{byte[] bytes=VmHardware.data(value);if(bytes.length>32)throw new VmHardware.Failure("invalid_argument","A UWB key contains at most32 bytes; empty means unset.");return bytes;}
        static RawRangingDevice peer(Object value)throws Exception{
            JSONArray row=list(value,12,12);UUID id=uuid(row,0);int session=(int)VmHardware.longInteger(row,1,0,4294967295L),config=VmHardware.integer(row,2,1,6),channel=VmHardware.integer(row,5,0,255),preamble=VmHardware.integer(row,6,0,255),rate=VmHardware.integer(row,7,1,3),slot=VmHardware.integer(row,8,1,2),sub=(int)VmHardware.longInteger(row,10,-1,4294967295L);UwbAddress local=address(row.get(3)),remote=address(row.get(4));byte[] secret=key(row.get(9)),subSecret=key(row.get(11));
            if((channel==0)!=(preamble==0))throw new VmHardware.Failure("invalid_argument","Use an explicit channel and preamble, or0/0 to leave both unset.");
            UwbRangingParams.Builder params=new UwbRangingParams.Builder(session,config,local,remote).setRangingUpdateRate(rate).setSlotDuration(slot).setSubSessionId(sub);
            if(channel!=0)params.setComplexChannel(new UwbComplexChannel.Builder().setChannel(channel).setPreambleIndex(preamble).build());if(secret.length>0)params.setSessionKeyInfo(secret);if(subSecret.length>0)params.setSubSessionKeyInfo(subSecret);
            return new RawRangingDevice.Builder().setRangingDevice(new RangingDevice.Builder().setUuid(id).build()).setUwbRangingParams(params.build()).build();
        }
        static RangingConfig config(int role,Collection<RawRangingDevice> peers){if(role==0)return new RawResponderRangingConfig.Builder().setRawRangingDevice(peers.iterator().next()).build();return new RawInitiatorRangingConfig.Builder().addRawRangingDevices(new ArrayList<>(peers)).build();}
        static SessionConfig options(JSONArray row)throws Exception{
            list(row,7,7);boolean angles=VmHardware.integer(row,0,0,1)==1,fusion=VmHardware.integer(row,2,0,1)==1;int count=VmHardware.integer(row,1,0,65535),notification=VmHardware.integer(row,3,0,3),near=VmHardware.integer(row,4,0,20000),far=VmHardware.integer(row,5,0,20000);VmHardware.integer(row,6,500,120000);
            if(near>far)throw new VmHardware.Failure("invalid_argument","Proximity near distance must not exceed far distance.");
            return new SessionConfig.Builder().setAngleOfArrivalNeeded(angles).setRangingMeasurementsLimit(count).setSensorFusionParams(new SensorFusionParams.Builder().setSensorFusionEnabled(fusion).build()).setDataNotificationConfig(new DataNotificationConfig.Builder().setNotificationConfigType(notification).setProximityNearCm(near).setProximityFarCm(far).build()).build();
        }
        static Object measurement(RangingMeasurement value)throws Exception{if(value==null)return JSONObject.NULL;if(!Double.isFinite(value.getMeasurement())||value.getConfidence()<0||value.getConfidence()>2)throw new VmHardware.Failure("invalid_response","Android returned an invalid UWB measurement.");return VmHardware.object("value",VmHardware.real(value.getMeasurement()),"confidence",value.getConfidence());}
        static final class Range extends VmHardware.Handle {
            RangingManager manager;RangingSession sdk;Runnable cleanupTask;final int role,timeout;final RangingPreference preference;final LinkedHashMap<UUID,RawRangingDevice> peers;boolean starting,requested,terminal,released,cleanupQueued,cleanupReturned,everOpened;int inFlight;long deadlineElapsed;String state="pending",cleanupError="";
            final Runnable deadline=()->{synchronized(this){if(!closed&&state.equals("pending")){state="error";event("error","code","timeout","message","The UWB session did not open before its deadline.");stopRequest();}}};
            Range(VmHardware.Context c,int role,LinkedHashMap<UUID,RawRangingDevice> peers,SessionConfig options,int timeout)throws Exception{super(c,"uwb","uwb_ranging");manager=manager(c);this.role=role;this.peers=peers;this.timeout=timeout;preference=new RangingPreference.Builder(role,config(role,peers.values())).setSessionConfig(options).build();}
            void event(String name,Object... values){try{Object[] fields=new Object[values.length+2];fields[0]="event";fields[1]=name;System.arraycopy(values,0,fields,2,values.length);emit(VmHardware.object(fields));}catch(Exception ignored){}}
            synchronized void release(){if(!released){released=true;HardwareSensors.events().removeCallbacks(deadline);if(cleanupTask!=null)CLEANUP.remove(cleanupTask);cleanupTask=null;manager=null;sdk=null;SESSIONS.release();}}
            synchronized void finish(String next,int reason){terminal=true;HardwareSensors.events().removeCallbacks(deadline);if(!closed){if(!state.equals("error"))state=next;event(next.equals("error")?"open_failed":"closed","reason",reason,"sdk_callback",true);}release();}
            synchronized boolean commit(RangingSession value)throws Exception{if(value==null)throw new VmHardware.Failure("unavailable","Android did not create a ranging session.");sdk=value;if(state.equals("pending")&&android.os.SystemClock.elapsedRealtime()>=deadlineElapsed)deadline.run();if(closed||!state.equals("pending")){terminal=true;release();return false;}requested=true;return true;}
            void start()throws Exception{
                synchronized(this){check();if(!state.equals("pending")){terminal=true;release();return;}starting=true;deadlineElapsed=android.os.SystemClock.elapsedRealtime()+timeout;HardwareSensors.events().postDelayed(deadline,timeout);}
                RangingSession value=null;
                try{
                    value=manager.createRangingSession(task->HardwareSensors.events().post(task),new RangingSession.Callback(){
                        public void onOpened(){synchronized(Range.this){if(terminal)return;if(android.os.SystemClock.elapsedRealtime()>=deadlineElapsed&&state.equals("pending")){state="error";event("error","code","timeout","message","Android delivered the UWB opened callback after its deadline.");stopRequest();return;}HardwareSensors.events().removeCallbacks(deadline);if(!closed&&state.equals("pending")){state="opened";everOpened=true;event("opened","sdk_callback",true);}}}
                        public void onOpenFailed(int reason){synchronized(Range.this){if(everOpened&&!terminal){if(!closed)event("operation_failed","reason",reason,"sdk_callback",true);return;}finish("error",reason);}}
                        public void onClosed(int reason){finish("closed",reason);}
                        public void onStarted(RangingDevice peer,int technology){peerEvent("started",peer,technology);}
                        public void onStopped(RangingDevice peer,int technology){peerEvent("stopped",peer,technology);}
                        public void onResults(RangingDevice peer,RangingData data){synchronized(Range.this){if(closed||terminal||!state.equals("opened"))return;try{known(peer,data.getRangingTechnology());event("ranging","peer",peer.getUuid().toString(),"technology",data.getRangingTechnology(),"timestamp_ms",data.getTimestampMillis(),"distance_m",measurement(data.getDistance()),"azimuth_degrees",measurement(data.getAzimuth()),"elevation_degrees",measurement(data.getElevation()),"rssi_dbm",data.hasRssi()?data.getRssi():JSONObject.NULL,"sdk_callback",true);}catch(Exception error){state="error";event("error","code","invalid_response","message",MainActivity.safe(error));stopRequest();}}}
                    });
                    if(commit(value))value.start(preference);
                }catch(Exception error){synchronized(this){if(!closed){state="error";event("error","code","platform_error","message",MainActivity.safe(error));}if(!requested){terminal=true;release();}else stopRequest();}throw error;}
                finally{synchronized(this){starting=false;if(closed||state.equals("error")||state.equals("stopping"))cleanup();}}
            }
            void known(RangingDevice peer,int technology)throws Exception{if(peer==null||!peers.containsKey(peer.getUuid())||technology!=RangingManager.UWB)throw new VmHardware.Failure("invalid_response","Android returned an unknown UWB peer or technology.");}
            synchronized void peerEvent(String name,RangingDevice peer,int technology){if(closed||terminal||state.equals("error")||state.equals("stopping"))return;try{known(peer,technology);event(name,"peer",peer.getUuid().toString(),"technology",technology,"sdk_callback",true);}catch(Exception error){state="error";event("error","code","invalid_response","message",MainActivity.safe(error));stopRequest();}}
            synchronized void active()throws Exception{check();if(terminal||!state.equals("opened")||sdk==null)throw new VmHardware.Failure("not_ready","Wait for the SDK opened event before changing a UWB session.");}
            synchronized int stopRequest(){if(terminal||state.equals("stopping"))return 0;if(!state.equals("error"))state="stopping";event("stop_requested");cleanup();return 1;}
            synchronized void cleanup(){if(starting||inFlight>0||released||cleanupQueued)return;if(!requested){terminal=true;release();return;}if(sdk==null)return;cleanupQueued=true;RangingSession value=sdk;cleanupTask=()->{try{value.close();synchronized(this){cleanupReturned=true;}}catch(Exception error){synchronized(this){cleanupError=MainActivity.safe(error);if(!closed)event("error","code","cleanup_failed","message",cleanupError);}}};CLEANUP.execute(cleanupTask);}
            public void access(VmHardware.Context c)throws Exception{check();VmHardware.require(c,"android.permission.RANGING");}
            synchronized RangingSession use()throws Exception{active();inFlight++;return sdk;}
            synchronized void end(){inFlight--;if(closed||state.equals("error")||state.equals("stopping"))cleanup();}
            public synchronized Object info()throws Exception{check();if(state.equals("pending")&&deadlineElapsed>0&&android.os.SystemClock.elapsedRealtime()>=deadlineElapsed)deadline.run();JSONArray ids=new JSONArray();for(UUID id:peers.keySet())ids.put(id.toString());return VmHardware.object("kind",kind,"state",state,"role",role,"elapsed_realtime_ms",android.os.SystemClock.elapsedRealtime(),"peers",ids,"sdk_requested",requested,"sdk_terminal",terminal,"cleanup_pending",requested&&!terminal&&(closed||state.equals("error")||state.equals("stopping")),"cleanup_call_returned",cleanupReturned,"cleanup_error",cleanupError);}
            public synchronized void close()throws IOException{if(closed)return;super.close();HardwareSensors.events().removeCallbacks(deadline);stopRequest();}
        }
        static Range range(VmHardware.Context c,int role,LinkedHashMap<UUID,RawRangingDevice> peers,SessionConfig options,int timeout)throws Exception{if(!SESSIONS.tryAcquire())throw new VmHardware.Failure("resource_limit","At most8 UWB sessions, including pending SDK teardown, may be owned.");try{return new Range(c,role,peers,options,timeout);}catch(Exception error){SESSIONS.release();throw error;}}
        static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
            if(op.equals("uwb_info")){Watch watch=watch(c);VmHardware.blocking(watch);try{watch.start();if(!watch.ready.await(2,TimeUnit.SECONDS))throw new VmHardware.Failure("timeout","Android did not deliver UWB capabilities within2 seconds.");synchronized(watch){if(watch.latest==null)throw new VmHardware.Failure("invalid_response","Android did not deliver usable UWB capabilities.");return VmHardware.object("sdk",Build.VERSION.SDK_INT,"feature",feature(c),"public_ranging_api",true,"snapshot",watch.latest);}}finally{watch.close();VmHardware.unblocking();}}
            if(op.equals("uwb_watch")){Watch watch=watch(c);VmHardware.blocking(watch);try{String id=VmHardware.add(watch);watch.start();return id;}catch(Exception error){watch.close();throw error;}finally{VmHardware.unblocking();}}
            if(op.equals("uwb_range")){
                int role=VmHardware.integer(a,0,0,1);JSONArray rows=list(a.get(1),1,role==0?1:8),opts=list(a.get(2),7,7);SessionConfig options=options(opts);LinkedHashMap<UUID,RawRangingDevice> peers=new LinkedHashMap<>();for(int i=0;i<rows.length();i++){RawRangingDevice peer=peer(rows.get(i));UUID id=peer.getRangingDevice().getUuid();if(peers.put(id,peer)!=null)throw new VmHardware.Failure("invalid_argument","UWB peer UUIDs must be unique within the session.");}
                if(!feature(c))throw new VmHardware.Failure("unsupported","This device does not declare UWB hardware.");VmHardware.require(c,"android.permission.RANGING");Range range=range(c,role,peers,options,opts.getInt(6));
                VmHardware.blocking(range);try{String id=VmHardware.add(range);range.start();return id;}catch(Exception error){range.close();throw error;}finally{VmHardware.unblocking();}
            }
            Range range=VmHardware.handle(c,VmHardware.text(a,0,128),Range.class);VmHardware.require(c,"android.permission.RANGING");
            if(op.equals("uwb_stop")){synchronized(range){range.check();return range.stopRequest();}}
            if(op.equals("uwb_add")){RawRangingDevice peer=peer(a.get(1));synchronized(range){range.active();if(range.role!=1)throw new VmHardware.Failure("unsupported_operation","Only an initiator can add a raw UWB peer.");if(range.peers.size()>=8)throw new VmHardware.Failure("resource_limit","At most8 UWB peers may belong to one session.");UUID id=peer.getRangingDevice().getUuid();if(range.peers.containsKey(id))throw new VmHardware.Failure("invalid_argument","This peer already belongs to the session.");range.peers.put(id,peer);}RangingSession sdk=range.use();try{sdk.addDeviceToRangingSession(new RawResponderRangingConfig.Builder().setRawRangingDevice(peer).build());return 1;}finally{range.end();}}
            if(op.equals("uwb_remove")){UUID id=uuid(a,1);RawRangingDevice peer;synchronized(range){range.active();peer=range.peers.get(id);if(peer==null)throw new VmHardware.Failure("unknown_peer","This UUID does not belong to the session.");}RangingSession sdk=range.use();try{sdk.removeDeviceFromRangingSession(peer.getRangingDevice());return 1;}finally{range.end();}}
            if(op.equals("uwb_interval")){int skip=VmHardware.integer(a,1,0,255);RangingSession sdk=range.use();try{sdk.reconfigureRangingInterval(skip);return 1;}finally{range.end();}}
            throw new VmHardware.Failure("unsupported_operation","Unknown UWB operation.");
        }
    }
}
