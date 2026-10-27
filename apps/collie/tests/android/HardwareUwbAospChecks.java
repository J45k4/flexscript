package org.flexscript.collie;

import android.net.Uri;
import android.os.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.BooleanSupplier;
import org.json.*;

/** Real cross-UID Binder/VM checks against a labeled, separate APK protocol fixture. No RF proof. */
public final class HardwareUwbAospChecks {
    final MainActivity host;final File root;final VmHardware.Context context;final JSONArray checks=new JSONArray();final List<String> owned=new ArrayList<>();int sequence;
    HardwareUwbAospChecks(MainActivity host,File root){this.host=host;this.root=root;context=new VmHardware.Context(host,root);}
    public static JSONObject run(MainActivity host,File root)throws Exception{return new HardwareUwbAospChecks(host,root).run();}
    void check(boolean value,String text)throws Exception{if(!value)throw new IOException(text);checks.put(text);}
    void await(BooleanSupplier condition,int timeout)throws Exception{long end=SystemClock.elapsedRealtime()+timeout;while(!condition.getAsBoolean()&&SystemClock.elapsedRealtime()<end)Thread.sleep(10);if(!condition.getAsBoolean())throw new IOException("OEM fixture condition deadline; checks="+checks);}
    JSONObject control(String method,String arg,int client)throws Exception{Bundle in=new Bundle();in.putInt("client",client);Bundle out=host.getContentResolver().call(Uri.parse("content://org.flexscript.collie.uwbfixture"),method,arg,in);return new JSONObject(out.getString("json"));}
    JSONObject snapshot(int id)throws Exception{return control("snapshot",null,0).getJSONArray("clients").getJSONObject(id-1);}
    void mode(String name)throws Exception{control("configure",name,0);}
    JSONObject vm(String source)throws Exception{JSONObject r=host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0)).put("source",source).put("call_id","uwb-oem-"+(++sequence)).put("history",new JSONArray()));if(!r.optString("state").equals("continue")||r.optInt("exit_code")!=0)throw new IOException("OEM VM: "+r+" source="+source);return r;}
    static String q(String value){return JSONObject.quote(value).replace("\\/","/");}
    String prepare(String mode,int timeout)throws Exception{mode(mode);String id;if(HardwareUwb.feature(context))id=(String)HardwareUwb.call(context,"uwb_prepare",new JSONArray().put(1).put(timeout).put(3));else{HardwareUwbAosp.Provider provider=HardwareUwbAosp.provider(context);if(provider==null||!provider.fixture)throw new IOException("Only the debug fixture may bypass a missing feature for transport checks");if(!HardwareUwb.SESSIONS.tryAcquire())throw new IOException("Fixture capacity unavailable");HardwareUwbAosp.Range r=new HardwareUwbAosp.Range(context,provider,1,timeout);id=VmHardware.add(r);r.start();}owned.add(id);return id;}
    HardwareUwbAosp.Range range(String id)throws Exception{return VmHardware.handle(context,id,HardwareUwbAosp.Range.class);}
    void prepared(HardwareUwbAosp.Range r)throws Exception{await(()->{synchronized(r){return r.prepared||r.error!=null;}},5000);synchronized(r){check(r.prepared&&r.error==null,"cross-UID provider capabilities/address/channel prepare an owned OEM session");}}
    int client(HardwareUwbAosp.Range r){return r.local[1]&255;}
    String start(String id,HardwareUwbAosp.Range r)throws Exception{
        vm("fn main(){let h="+q(id)+";let p=db_list();db_add(p,uwb_peer(\"12345678-1234-1234-1234-123456789abc\",4294967295,2,device_field(device_info(h),\"local_address\"),db_blob(\"CD\",2),9,10,1,2,db_blob(\"00000000\",8),-1,db_blob(\"\",0)));let req=uwb_start(h,p,uwb_options(1,0,0,1,0,20000,10000));if !req{return 1;}return 0;}");synchronized(r){return r.startRequest.id;}
    }
    void active(HardwareUwbAosp.Range r)throws Exception{await(()->{synchronized(r){return r.opened||r.error!=null;}},5000);synchronized(r){check(r.opened&&r.startReturned&&r.initialized,"actual protocol initialization and RPC return both precede active state; no radio effect is inferred");}}
    void released(HardwareUwbAosp.Base r)throws Exception{await(()->{synchronized(r){return r.released;}},5000);}
    void stop(String id,HardwareUwbAosp.Range r)throws Exception{vm("fn main(){if db_word(uwb_stop("+q(id)+"))!=1{return 1;}return 0;}");released(r);}
    void normal()throws Exception{
        String id=prepare("normal",5000);HardwareUwbAosp.Range r=range(id);prepared(r);int n=client(r);check(snapshot(n).getInt("address_calls")==1,"one actual address allocation is used rather than querying a stateful provider twice");String request=start(id,r);active(r);
        JSONObject p=snapshot(n);check(p.getLong("session_id")==4294967295L&&p.getLong("sub_session_id")==0&&p.getInt("config_id")==2&&p.getInt("channel")==9&&p.getInt("preamble")==10&&p.getInt("peer_count")==1&&p.getInt("key_bytes")==8&&!p.getBoolean("aoa_disabled"),"the independent provider receives exact unsigned session bits, unset sub-session default, negotiated channel, peers and keys through the actual VM");
        vm("fn main(){let r=uwb_request("+q(id)+","+q(request)+");if !db_word(device_field(r,\"rpc_complete\")) || !db_word(device_field(r,\"sdk_rpc_returned\")) || !db_word(device_field(r,\"effect_confirmed\")){return 1;}return 0;}");
        r.events.clear();control("emit","measure",n);
        vm("fn main(){let e=device_wait("+q(id)+",1000);if !worker_equal(db_word(device_field(e,\"event\")),\"ranging\") || db_word(device_field(e,\"timestamp_ns\"))!=9007199254740993{return 1;}if db_word(device_field(device_field(e,\"azimuth_degrees\"),\"value\"))!=-9223372036854775807-1{return 2;}if db_word(device_field(device_field(e,\"distance_m\"),\"value\"))!=4608308318706860032{return 3;}if db_word(device_field(device_field(e,\"distance_m\"),\"confidence\"))!=2 || db_word(device_field(device_field(e,\"distance_m\"),\"validity_known\")){return 4;}return 0;}");
        check(true,"constructed cross-UID measurements retain exact timestamp above2^53, distance float bits, negative zero, degrees and confidence through VM transport; validity and RSSI remain unknown");
        control("emit","unknown",n);synchronized(r){check(r.discardedCallbacks==1&&r.events.isEmpty(),"an unowned callback address is dropped without assigning a peer UUID");}
        int rejected=r.rejectedCallers;r.callback.onRangingInitialized(device(r.local));check(r.rejectedCallers==rejected+1,"same-process spoofed callbacks fail the actual provider UID check");
        vm("fn main(){if !uwb_interval("+q(id)+",255){return 1;}return 0;}");
        await(()->{synchronized(r){return r.pending==null;}},3000);
        vm("fn main(){if !uwb_notifications("+q(id)+",2,12,345){return 1;}return 0;}");await(()->{synchronized(r){return r.pending==null;}},3000);
        p=snapshot(n);check(p.getInt("intervals")==1&&p.getInt("skip")==255&&p.getInt("notifications")==1&&p.getInt("notification_mode")==2&&p.getInt("near")==12&&p.getInt("far")==345,"interval and notification RPC arguments reach the independent provider exactly once; void return is not an effective radio-change acknowledgement");
        vm("fn main(){if !uwb_add("+q(id)+",uwb_peer(\"22345678-1234-1234-1234-123456789abc\",4294967295,2,device_field(device_info("+q(id)+"),\"local_address\"),db_blob(\"EF\",2),9,10,1,2,db_blob(\"00000000\",8),4294967295,db_blob(\"1111111111111111\",16))){return 1;}return 0;}");await(()->{synchronized(r){return r.pending==null;}},3000);
        check(snapshot(n).getInt("adds")==1&&snapshot(n).getLong("added_sub_session_id")==4294967295L&&snapshot(n).getInt("added_sub_key_bytes")==16,"the peer add RPC preserves individual unsigned sub-session bits and binary key length");
        vm("fn main(){if !uwb_remove("+q(id)+",\"22345678-1234-1234-1234-123456789abc\"){return 1;}return 0;}");await(()->{synchronized(r){return r.pending==null;}},3000);
        synchronized(r){HardwareUwbAosp.Peer peer=r.peers.get(UUID.fromString("22345678-1234-1234-1234-123456789abc"));check(peer.removed&&peer.suspended&&peer.removeRpcReturned,"peer removal requires both the independent peer-suspended callback and actual remove RPC return, including callback-before-return ordering");}
        try{VmHardware.handle(new VmHardware.Context(host,new File(root,"other-workspace")),id);throw new IOException("Foreign workspace accepted");}catch(VmHardware.Failure e){check(e.code.equals("stale_handle"),"OEM resources preserve workspace ownership");}
        stop(id,r);check(snapshot(n).getInt("stops")==1&&!((JSONObject)r.info()).getBoolean("provider_close_status_known"),"exactly one stop RPC plus actual terminal callback releases the local lease; provider final-close status stays explicitly unknown");
    }
    static androidx.core.uwb.backend.UwbDevice device(byte[] a){androidx.core.uwb.backend.UwbDevice d=new androidx.core.uwb.backend.UwbDevice();d.address=HardwareUwbAosp.address(a);return d;}
    void ordering()throws Exception{
        String id=prepare("delayed_init",5000);HardwareUwbAosp.Range r=range(id);prepared(r);start(id,r);final HardwareUwbAosp.Range delayed=r;await(()->{synchronized(delayed){return delayed.startReturned;}},3000);check(!r.opened,"RPC return alone cannot create an opened session");control("emit","peer_init",client(r));check(!r.opened,"a peer initialized callback cannot substitute for the local session initialization");control("emit","init",client(r));active(r);stop(id,r);
        id=prepare("init_then_hold",5000);r=range(id);prepared(r);final HardwareUwbAosp.Range held=r;start(id,r);await(()->{synchronized(held){return held.initialized;}},3000);check(!r.opened&&r.io==1,"initialized callback alone cannot open a still-running start RPC");control("release",String.valueOf(client(r)),0);active(r);stop(id,r);
        id=prepare("reject",5000);r=range(id);prepared(r);start(id,r);released(r);check(r.startRejected&&!r.opened&&snapshot(client(r)).getInt("stops")==0,"an actual protocol wrong-parameters callback rejects startup without fabricating opened state or replaying a stop against an unopened session");
    }
    void cleanup()throws Exception{
        String id=prepare("silent_stop",5000);HardwareUwbAosp.Range r=range(id);prepared(r);start(id,r);active(r);r.stop();final HardwareUwbAosp.Range silent=r;await(()->{synchronized(silent){return silent.stopRpcFinished;}},3000);check(!r.released,"stop RPC return without terminal observation retains the lease");control("emit","terminal",client(r));released(r);check(snapshot(client(r)).getInt("stops")==1,"late terminal callback completes cleanup without replaying stop");
        id=prepare("slow_stop",5000);r=range(id);prepared(r);start(id,r);active(r);final HardwareUwbAosp.Range slow=r;r.close();await(()->{synchronized(slow){return slow.stopRpcStarted;}},3000);long start=SystemClock.elapsedRealtime();r.close();check(SystemClock.elapsedRealtime()-start<200&&!r.released,"close stays responsive and keeps capacity while the provider stop RPC is blocked");control("release",String.valueOf(client(r)),0);released(r);
    }
    void timeout()throws Exception{
        String id=prepare("prepare_hold",500);HardwareUwbAosp.Range r=range(id);final HardwareUwbAosp.Range prep=r;await(()->{synchronized(prep){return prep.expired;}},3000);check(!r.released&&r.io==1,"a real preparation wall deadline retains the lease while its Binder call remains in flight");int n=control("snapshot",null,0).getJSONArray("clients").length();control("release",String.valueOf(n),0);released(r);check(!r.prepared&&r.error.getString("code").equals("timeout"),"late address completion cannot resurrect expired preparation");
        id=prepare("start_hold",5000);r=range(id);prepared(r);start(id,r);final HardwareUwbAosp.Range mutation=r;await(()->{synchronized(mutation){return mutation.startRequest.started;}},3000);await(()->{synchronized(mutation){return mutation.startRequest.expired;}},10000);check(!r.released&&!r.startRequest.complete&&r.io==1,"an expired mutation holds capacity until its actual Binder call settles; no mutation is replayed");control("release",String.valueOf(client(r)),0);released(r);check(r.startRequest.complete&&r.startRequest.returned&&!r.opened&&snapshot(client(r)).getInt("starts")==1&&snapshot(client(r)).getInt("stops")==1,"late start return settles the original request and triggers one cleanup stop without reopening or retrying the mutation");
    }
    void queuedCancellation()throws Exception{
        String blockerId=prepare("normal",5000);HardwareUwbAosp.Range blocker=range(blockerId);prepared(blocker);String id=prepare("normal",5000);HardwareUwbAosp.Range r=range(id);prepared(r);
        CountDownLatch entered=new CountDownLatch(4),release=new CountDownLatch(1);
        try{
            for(int i=0;i<4;i++)blocker.submit(()->{entered.countDown();if(!release.await(5,TimeUnit.SECONDS))throw new IOException("Constructed executor hold elapsed");});
            check(entered.await(3,TimeUnit.SECONDS),"four constructed scheduler holds occupy the actual bounded RPC workers");start(id,r);r.close();check(!r.released&&r.io==1&&!r.startRequest.started,"closing a queued mutation retains its capacity until the actual queued worker settles");release.countDown();released(r);
            check(r.startRequest.complete&&!r.startRequest.started&&!r.startRequest.returned&&r.pending==null&&snapshot(client(r)).getInt("starts")==0&&snapshot(client(r)).getInt("stops")==0,"a retired queued start settles cancelled without any provider mutation, fake completion or cleanup stop");
        }finally{release.countDown();blocker.close();r.close();released(blocker);}
    }
    void watchAndDeath()throws Exception{
        mode("normal");String id;HardwareUwbAosp.Watch w;if(HardwareUwb.feature(context)){id=(String)HardwareUwb.call(context,"uwb_watch",new JSONArray().put(3));w=VmHardware.handle(context,id,HardwareUwbAosp.Watch.class);}else{if(!HardwareUwb.WATCHES.tryAcquire())throw new IOException("Fixture observer capacity unavailable");w=new HardwareUwbAosp.Watch(context,HardwareUwbAosp.provider(context));id=VmHardware.add(w);w.start();}owned.add(id);check(w.ready.await(5,TimeUnit.SECONDS)&&w.error==null&&Boolean.TRUE.equals(w.available),"actual separate-process availability subscription produces a copied observer snapshot");int n=control("snapshot",null,0).getJSONArray("clients").length();w.close();released(w);check(snapshot(n).getInt("subscribes")==1&&snapshot(n).getInt("unsubscribes")==1,"owned observer close performs exactly one actual provider unsubscribe");
        id=prepare("normal",5000);HardwareUwbAosp.Range r=range(id);prepared(r);start(id,r);active(r);control("die",null,0);released(r);check(r.providerDead&&r.error.getString("code").equals("disconnected")&&!((JSONObject)r.info()).getBoolean("provider_close_status_known"),"actual independent provider process death releases the local binding with disconnected status and no claim about hardware stop/final close");
    }
    JSONObject run()throws Exception{int watches=HardwareUwb.WATCHES.availablePermits(),sessions=HardwareUwb.SESSIONS.availablePermits();JSONObject provider=HardwareUwbAosp.base(context);check(provider.getJSONObject("provider").getBoolean("debug_signature_fixture")&&provider.getJSONObject("provider").getInt("uid")!=android.os.Process.myUid(),"canonical service resolution finds a debuggable same-signature separate-UID fixture, never a claimed system/radio provider");
        if(!HardwareUwb.feature(context)){vm("fn main(){if uwb_backend_prepare(3,1,1000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"unsupported\"){return 2;}return 0;}");check(true,"the actual VM refuses missing UWB hardware before consent; only this debug test constructs owned transport fixtures directly");}
        try{normal();ordering();cleanup();timeout();queuedCancellation();watchAndDeath();}finally{for(String id:owned)try{VmHardware.close(context,id);}catch(Exception ignored){}}
        await(()->HardwareUwb.WATCHES.availablePermits()==watches&&HardwareUwb.SESSIONS.availablePermits()==sessions,5000);check(true,"all owned observer/session capacity returns to the independently sampled baseline after completed cleanup");
        return new JSONObject().put("ok",true).put("checks",checks).put("actual_provider",provider).put("constructed_protocol_fixture",true).put("cross_uid_binder_verified",true).put("ranging_io_verified",false).put("physical_devices_verified",false);
    }
}
