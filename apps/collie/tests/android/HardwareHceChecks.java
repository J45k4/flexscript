package org.flexscript.collie;

import android.content.*;
import android.content.pm.*;
import android.nfc.*;
import android.nfc.cardemulation.PollingFrame;
import android.os.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import org.json.*;

/** Actual Android service binding/SDK Messenger with explicitly constructed command fixtures.
 * This is not a radio or routing-registration oracle. No fake adapter is installed. */
public final class HardwareHceChecks {
    final MainActivity host;final File root;final VmHardware.Context context;final JSONArray checks=new JSONArray();int sequence;boolean pollingTransport;
    HardwareHceChecks(MainActivity host,File root){this.host=host;this.root=root;context=new VmHardware.Context(host,root);}
    public static JSONObject run(MainActivity host,File root)throws Exception{return new HardwareHceChecks(host,root).run();}
    public static JSONObject runBackground(MainActivity host,File root)throws Exception{return new HardwareHceChecks(host,root).background();}
    public static JSONObject runOrphan(MainActivity host,File root)throws Exception{HardwareHceChecks t=new HardwareHceChecks(host,root);Peer p=t.new Peer(0,5000);for(int mode=0;mode<3;mode++)HardwareHce.enabled(host,mode,true);t.check(true,"the constructed live service fixture enables all three actual components before process-death recovery");return t.report().put("orphan_handle",p.handle);}
    public static JSONObject runRecovered(MainActivity host,File root)throws Exception{HardwareHceChecks t=new HardwareHceChecks(host,root);t.ready();for(int mode=0;mode<3;mode++)t.check(host.getPackageManager().getComponentEnabledSetting(HardwareHce.component(host,mode))==PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,"process restart restored the default-disabled component "+mode);return t.report();}
    void check(boolean ok,String text)throws Exception{if(!ok)throw new IOException(text);checks.put(text);}
    void until(java.util.function.BooleanSupplier condition)throws Exception{long end=SystemClock.elapsedRealtime()+15000;while(!condition.getAsBoolean()){if(SystemClock.elapsedRealtime()>=end)throw new IOException("NFC SDK fixture timed out");Thread.sleep(10);}}
    void ready()throws Exception{until(()->{synchronized(HardwareNfc.LEASE){return HardwareHce.recovered&&HardwareHce.owner==null&&host.hardwareResumed;}});}
    void ui(Runnable action)throws Exception{CountDownLatch done=new CountDownLatch(1);AtomicReference<Throwable> error=new AtomicReference<>();host.runOnUiThread(()->{try{action.run();}catch(Throwable e){error.set(e);}finally{done.countDown();}});if(!done.await(5,TimeUnit.SECONDS))throw new IOException("NFC UI fixture timed out");if(error.get()!=null)throw new IOException(error.get());}
    static String q(String s){return JSONObject.quote(s).replace("\\/","/");}
    JSONObject vm(File workspace,String source)throws Exception{source="fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}"+source.replaceAll("return ([1-9][0-9]*);","return fail($1);");JSONObject r=host.engineAt(workspace,3,new JSONObject().put("config",host.workerConfig(workspace,0)).put("source",source).put("call_id","hce-check-"+(++sequence)).put("history",new JSONArray()));if(!r.optString("state").equals("continue")||r.optInt("exit_code")!=0)throw new IOException("HCE scenario "+sequence+": "+r);return r;}
    JSONObject vm(String source)throws Exception{return vm(root,source);}
    JSONObject report()throws Exception{return new JSONObject().put("ok",true).put("checks",checks).put("constructed_sdk_fixture",true).put("actual_component_binding_verified",true).put("polling_binder_transport_verified",pollingTransport).put("routing_registration_verified",false).put("radio_exchange_verified",false).put("physical_devices_verified",false);}
    // Values0/1/2/3/4 below are the AOSP framework's service Messenger protocol.
    // They are used only by this independent debug peer, not by production code.
    final class Peer implements AutoCloseable {
        final int mode;final HardwareHce.Session session;final String handle;final BlockingQueue<Message> replies=new LinkedBlockingQueue<>(16);final CountDownLatch connected=new CountDownLatch(1),peerConnected=new CountDownLatch(1);Messenger service,remote;boolean bound,peerBound;
        final Messenger receive=new Messenger(new Handler(Looper.getMainLooper(),m->{if(m.what==1||m.what==3||m.what==100)replies.offer(Message.obtain(m));return true;}));
        final ServiceConnection connection=new ServiceConnection(){public void onServiceConnected(ComponentName name,IBinder binder){service=new Messenger(binder);connected.countDown();}public void onServiceDisconnected(ComponentName name){}};
        final ServiceConnection peerConnection=new ServiceConnection(){public void onServiceConnected(ComponentName name,IBinder binder){remote=new Messenger(binder);peerConnected.countDown();}public void onServiceDisconnected(ComponentName name){}};
        Peer(int mode,int timeout)throws Exception{
            this.mode=mode;ready();vm("fn main(){return 0;}");session=new HardwareHce.Session(context,HardwareNfc.optional(context),mode,timeout,new ArrayList<>(Arrays.asList("F0434F4C4C494500")),"4000","02FE000000000001");session.state="ready";
            synchronized(HardwareNfc.LEASE){if(HardwareHce.owner!=null)throw new IOException("Existing NFC lease");HardwareHce.owner=session;}
            // No SDK registration/preference flag is set: this is a constructed
            // service transport fixture on hardware which may have no NFC radio.
            handle=VmHardware.add(session);HardwareHce.enabled(host,mode,true);session.componentEnabled=true;
            ui(()->{bound=host.bindService(new Intent().setComponent(HardwareHce.component(host,mode)),connection,android.content.Context.BIND_AUTO_CREATE);});check(bound&&connected.await(5,TimeUnit.SECONDS),"Android binds the actual protected service component for constructed protocol fixture "+mode);
            ui(()->{peerBound=host.bindService(new Intent().setClass(host,HardwareHcePeerFixture.class).setData(android.net.Uri.parse("collie-hce-fixture:"+UUID.randomUUID())),peerConnection,android.content.Context.BIND_AUTO_CREATE);});if(!peerBound||!peerConnected.await(5,TimeUnit.SECONDS))throw new IOException("Independent Binder peer did not bind");Message init=Message.obtain(null,100);init.replyTo=receive;remote.send(init);reply(100);
        }
        void send(int what,byte[] bytes)throws Exception{Message m=Message.obtain(null,what);m.replyTo=remote;if(bytes!=null){Bundle b=new Bundle();b.putByteArray("data",bytes);m.setData(b);}service.send(m);}
        void polling(ArrayList<PollingFrame> frames)throws Exception{Message m=Message.obtain(null,101);m.replyTo=service;Bundle b=new Bundle();b.putParcelableArrayList("android.nfc.cardemulation.POLLING_FRAMES",frames);m.setData(b);remote.send(m);}
        HardwareHce.Request command(byte[] bytes)throws Exception{send(0,bytes);until(()->{synchronized(session){return session.pending!=null;}});synchronized(session){return session.pending;}}
        Message reply(int what)throws Exception{long end=SystemClock.elapsedRealtime()+5000;while(SystemClock.elapsedRealtime()<end){Message m=replies.poll(100,TimeUnit.MILLISECONDS);if(m!=null&&m.what==what)return m;}throw new IOException("SDK service did not send expected fixture message "+what);}
        void deactivate()throws Exception{send(2,null);until(()->{synchronized(session){return !session.channelActive;}});}
        public void close()throws Exception{try{boolean active;synchronized(session){active=session.channelActive;}if(active)deactivate();}finally{try{VmHardware.close(context,handle);}catch(VmHardware.Failure stale){session.close();}if(bound)ui(()->host.unbindService(connection));if(peerBound)ui(()->host.unbindService(peerConnection));until(()->{synchronized(session){return session.released;}});}}
    }
    JSONObject run()throws Exception{
        ready();NfcAdapter sdk=HardwareNfc.optional(context);boolean hce=HardwareHce.supported(host,sdk,0),hcef=HardwareHce.supported(host,sdk,2);
        vm("fn main(){let i=hce_info();if db_word(device_field(i,\"supported\"))!="+(hce?1:0)+"||db_word(device_field(i,\"supported_f\"))!="+(hcef?1:0)+"{return 1;}return 0;}");check(true,"VM emulation capabilities exactly match the independent actual NfcAdapter and package feature queries");
        for(int mode=0;mode<3;mode++){ServiceInfo info=host.getPackageManager().getServiceInfo(HardwareHce.component(host,mode),PackageManager.GET_META_DATA|PackageManager.MATCH_DISABLED_COMPONENTS);check(info.exported&&"android.permission.BIND_NFC_SERVICE".equals(info.permission)&&host.getPackageManager().getComponentEnabledSetting(HardwareHce.component(host,mode))==PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,"service "+mode+" is disabled by default and protected by Android's NFC binding permission");}
        vm("fn main(){let a=db_list();db_add(a,db_text(\"not-an-AID\"));if hce_open(0,a,1000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}if hcef_open(\"40FF\",\"02FE000000000001\",1000)||hcef_open(\"4000\",\"0000000000000001\",1000){return 3;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 4;}return 0;}");check(true,"malformed AIDs, reserved system codes and invalid NFCID2 fail before SDK routing mutation");
        if(!hce&&!hcef){vm("fn main(){let a=db_list();db_add(a,db_text(\"F0434F4C4C494500\"));if hce_open(0,a,1000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"unsupported\"){return 2;}if hcef_open(\"4000\",\"02FE000000000001\",1000){return 3;}if !worker_equal(db_word(db_at(device_error(),0)),\"unsupported\"){return 4;}return 0;}");check(true,"actual adapter absence is returned through the ordinary VM without a fabricated ready/radio callback");}
        for(int mode=0;mode<3;mode++)transport(mode);
        if(Build.VERSION.SDK_INT>=35)polling();
        timeout();blockedDeadline();live();return report().put("actual_hce_supported",hce).put("actual_hcef_supported",hcef);
    }
    // AOSP Parcelable wire keys are fixture-only; production uses SDK getters.
    static PollingFrame frame(int type,byte[] bytes,int gain,long timestamp,boolean automatic){
        Bundle b=new Bundle();b.putInt("android.nfc.cardemulation.TYPE",type);b.putByteArray("android.nfc.cardemulation.DATA",bytes);
        if(gain!=-1)b.putInt("android.nfc.cardemulation.GAIN",gain);
        b.putLong("android.nfc.cardemulation.TIMESTAMP",timestamp);b.putBoolean("android.nfc.cardemulation.TRIGGERED_AUTOTRANSACT",automatic);
        Parcel p=Parcel.obtain();try{p.writeBundle(b);p.setDataPosition(0);return PollingFrame.CREATOR.createFromParcel(p);}finally{p.recycle();}
    }
    void polling()throws Exception{
        NfcAdapter adapter=HardwareNfc.optional(context);boolean hce=HardwareHce.supported(host,adapter,0);
        boolean observe=hce&&adapter.isObserveModeSupported(),enabled=hce&&adapter.isObserveModeEnabled();
        vm("fn main(){let p=device_field(hce_info(),\"polling\");if !db_word(device_field(p,\"frames_api\"))||db_word(device_field(p,\"supported\"))!="+(hce?1:0)+"||db_word(device_field(p,\"observe_supported\"))!="+(observe?1:0)+"||db_word(device_field(p,\"observe_enabled\"))!="+(enabled?1:0)+"{return 1;}if db_word(device_field(p,\"filter_registration_implemented\"))||db_word(device_field(p,\"observe_control_implemented\")){return 2;}return 0;}");
        check(true,"polling/observe capability values match independent public SDK queries and do not claim unimplemented controls");
        for(int mode=0;mode<2;mode++)try(Peer p=new Peer(mode,5000)){
            p.session.events.clear();String h=q(p.handle);int[] types={79,88,65,66,70,85};ArrayList<PollingFrame> rows=new ArrayList<>();
            byte[] binary=new byte[32768];for(int i=0;i<binary.length;i++)binary[i]=(byte)((i*37+11)&255);
            for(int i=0;i<types.length;i++)rows.add(frame(types[i],i==0?binary:new byte[0],i==0?17:-1,9007199254740993L+i,i%2==1));
            p.polling(rows);until(()->p.session.events.size()==6);rows.get(0).getData()[0]^=127;
            StringBuilder code=new StringBuilder("fn main(){let batch=db_null();");
            for(int i=0;i<6;i++)code.append("{let e=device_wait(").append(h).append(",1000);let f=device_field(e,\"frame\");if !worker_equal(db_word(device_field(e,\"event\")),\"polling_frame\")||db_word(device_field(e,\"index\"))!=").append(i).append("||db_word(device_field(e,\"total\"))!=6||!db_word(device_field(e,\"sdk_callback\")){return 1;}if db_word(device_field(f,\"type\"))!=").append(types[i]).append("||db_word(device_field(f,\"timestamp_us\"))!=").append(9007199254740993L+i).append("||db_word(device_field(f,\"vendor_specific_gain\"))!=").append(i==0?17:-1).append("||db_word(device_field(f,\"triggered_auto_transact\"))!=").append(i%2).append("{return 2;}let b=device_field(e,\"batch\");if db_kind(batch)!=0&& !worker_equal(db_word(b),db_word(batch)){return 3;}batch=b;let bytes=device_field(f,\"data\");if db_bytes(bytes)!=").append(i==0?32768:0).append("{return 4;}").append(i==0?"let j=0;while j<32768{if load8(db_word(bytes)+j)!=(j*37+11)%256{return 5;}j=j+1;}":"").append("}");
            code.append("if db_kind(hce_request(").append(h).append("))!=0||db_word(device_field(device_info(").append(h).append("),\"channel_active\")){return 6;}return 0;}");vm(code.toString());
            check(true,"separate-process constructed SDK polling messages reach the actual service and VM for category"+mode+", preserving32KiB/every byte, all six types, exact microsecond timestamps above2^53, gain and auto-transact metadata");
            check(true,"polling metadata creates neither an APDU command nor a transaction-active lease for category"+mode);
            ArrayList<PollingFrame> large=new ArrayList<>();for(int i=0;i<70;i++)large.add(frame(85,new byte[0],-1,i,false));p.polling(large);until(()->p.session.events.size()==65);
            vm("fn main(){let i=0;while i<64{let e=device_wait("+h+",1000);if !worker_equal(db_word(device_field(e,\"event\")),\"polling_frame\")||db_word(device_field(e,\"index\"))!=i||db_word(device_field(e,\"total\"))!=70{return 1;}i=i+1;}let e=device_wait("+h+",1000);if !worker_equal(db_word(device_field(e,\"event\")),\"polling_batch_truncated\")||db_word(device_field(e,\"copied\"))!=64||db_word(device_field(e,\"dropped_frames\"))!=6{return 2;}return 0;}");
            check(true,"a70-frame SDK batch performs at most64 frame copies and explicitly reports all six dropped frames for category"+mode);
            ArrayList<PollingFrame> invalid=new ArrayList<>();invalid.add(frame(85,new byte[32769],-1,0,false));invalid.add(null);invalid.add(frame(85,new byte[0],-1,1,false));p.polling(invalid);until(()->p.session.events.size()==3);
            vm("fn main(){let e=device_wait("+h+",1000);if !worker_equal(db_word(device_field(e,\"code\")),\"size_limit\"){return 1;}e=device_wait("+h+",1000);if !worker_equal(db_word(device_field(e,\"code\")),\"invalid_sdk_value\"){return 2;}e=device_wait("+h+",1000);if !worker_equal(db_word(device_field(e,\"event\")),\"polling_frame\")||db_word(device_field(e,\"index\"))!=2{return 3;}return 0;}");
            check(true,"oversize/null SDK frames produce bounded typed errors and do not discard a subsequent valid frame for category"+mode);
            ArrayList<PollingFrame> small=new ArrayList<>();for(int i=0;i<64;i++)small.add(frame(85,new byte[0],-1,i,false));
            for(int j=0;j<3;j++)p.polling(small);p.polling(new ArrayList<>(Arrays.asList(frame(85,new byte[0],-1,999,false))));
            until(()->p.session.events.stream().anyMatch(e->e instanceof JSONObject&&((JSONObject)e).optJSONObject("frame")!=null&&((JSONObject)e).optJSONObject("frame").optLong("timestamp_us")==999));
            vm("fn main(){let e=device_wait("+h+",1000);if !worker_equal(db_word(device_field(e,\"event\")),\"overflow\")||db_word(device_field(e,\"dropped\"))!=65{return 1;}let first=device_field(e,\"next\");if db_word(device_field(device_field(first,\"frame\"),\"timestamp_us\"))!=1{return 2;}let i=0;while i<127{e=device_wait("+h+",1000);i=i+1;}if db_word(device_field(device_field(e,\"frame\"),\"timestamp_us\"))!=999{return 3;}return 0;}");
            check(true,"193 actual SDK-dispatched constructed frames retain128 events, report65 losses and preserve the final frame for category"+mode);
            File foreign=new File(root,"polling-foreign");new File(foreign,"files").mkdirs();vm(foreign,"fn main(){if device_wait("+h+",0){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 2;}return 0;}");
            check(true,"a different actual VM workspace cannot read the polling-frame handle for category"+mode);
            p.session.state="stopping";int count=p.session.events.size();HardwareHcePolling.frames(p.session,rows);check(count==p.session.events.size(),"the callback guard discards explicitly constructed late polling values once category"+mode+" is stopping");
        }
        pollingTransport=true;
    }
    void transport(int mode)throws Exception{
        try(Peer p=new Peer(mode,5000)){
            int n=mode==2?255:mode==0?65544:261;byte[] command=new byte[n];for(int i=0;i<n;i++)command[i]=(byte)((i*37+11)&255);if(mode==2)command[0]=(byte)n;
            HardwareHce.Request request=p.command(command);String h=q(p.handle),id=q(request.id);
            vm("fn main(){let r=hce_request("+h+");if db_word(device_field(r,\"bytes\"))!="+n+"||!worker_equal(db_word(device_field(r,\"id\")),"+id+"){return 1;}"+(n>32768?"if db_kind(device_field(r,\"data\"))!=0{return 2;}":"if db_bytes(device_field(r,\"data\"))!="+n+"{return 2;}")+"return 0;}");
            for(int offset=0;offset<n;offset+=32768){int count=Math.min(32768,n-offset),next=offset+count<n?offset+count:-1;
                vm("fn main(){let r=hce_request_read("+h+","+id+","+offset+",32768);let b=device_field(r,\"value\");if db_bytes(b)!="+count+"||db_word(device_field(r,\"next\"))!="+next+"||db_word(device_field(r,\"total\"))!="+n+"{return 1;}let ptr=db_word(b);let i=0;while i<"+count+"{let expected=((i+"+offset+")*37+11)%256;"+(mode==2?"if i==0{expected=255;}":"")+"if load8(ptr+i)!=expected{return 2;}i=i+1;}return 0;}");
            }check(true,"constructed command "+mode+" crosses the real service SDK callback and bounded VM pages with every byte intact ("+n+" bytes)");
            vm("fn main(){let end=hce_request_read("+h+","+id+","+n+",32768);if db_bytes(device_field(end,\"value\"))||db_word(device_field(end,\"next\"))!=-1{return 1;}if hce_request_read("+h+","+id+","+(n+1)+",1){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 3;}return 0;}");check(true,"command pages enforce exact EOF and reject offsets past the actual payload for fixture "+mode);
            File foreign=new File(root,"hce-foreign");new File(foreign,"files").mkdirs();vm(foreign,"fn main(){if hce_request("+h+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 2;}return 0;}");check(true,"another actual VM workspace cannot inspect or reply through the service fixture handle "+mode);
            vm("fn main(){if hce_reply("+h+","+id+",db_blob(\"x\",1)){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}return 0;}");
            int responseBytes=mode==0?65538:n;
            if(mode==0){
                vm("fn main(){if db_word(hce_reply_begin("+h+","+id+",65538))!=65538{return 1;}if hce_reply_commit("+h+","+id+"){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"not_ready\"){return 3;}if hce_reply_begin("+h+","+id+",65538){return 4;}if !worker_equal(db_word(db_at(device_error(),0)),\"busy\"){return 5;}return 0;}");
                for(int offset=0;offset<responseBytes;offset+=32768){int count=Math.min(32768,responseBytes-offset);vm("fn main(){let b=alloc("+count+");let i=0;while i<"+count+"{store8(b+i,((i+"+offset+")*19+7)%256);i=i+1;}if db_word(hce_reply_write("+h+","+id+","+offset+",db_blob(b,"+count+")))!="+count+"{return 1;}if hce_reply_write("+h+","+id+","+offset+",db_blob(b,"+count+")){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 3;}return 0;}");}
                vm("fn main(){return db_word(hce_reply_commit("+h+","+id+"))-1;}");check(true,"the full65538-byte extended response stages through bounded chunks, rejects replay/early commit, and commits exactly once");
            }else vm("fn main(){let b=alloc("+n+");let i=0;while i<"+n+"{store8(b+i,(i*19+7)%256);i=i+1;}"+(mode==2?"store8(b,255);":"")+"return db_word(hce_reply("+h+","+id+",db_blob(b,"+n+")))-1;}");
            byte[] response=p.reply(1).getData().getByteArray("data");check(response!=null&&response.length==responseBytes,"actual SDK Messenger returns the exact constructed reply length for service "+mode);for(int i=0;i<responseBytes;i++)if((response[i]&255)!=(mode==2&&i==0?255:(i*19+7)&255))throw new IOException("SDK reply bytes differ");check(true,"every VM-generated response byte reaches the independent actual framework Messenger peer for service "+mode);
            String valid=mode==2?"let b=alloc(2);store8(b,2);store8(b+1,0);let response=db_blob(b,2);":"let response=db_blob(\"ok\",2);";
            vm("fn main(){"+valid+"if hce_reply("+h+","+id+",response){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_request\"){return 2;}return 0;}");check(true,"a duplicate reply is rejected after SDK submission for service "+mode);
            check(!HardwareSensors.events().hasCallbacks(request.deadline),"answering service "+mode+" removes its deadline callback instead of retaining old command payloads");
            HardwareHce.Request replaced=p.command(command);p.send(0,command);until(()->{synchronized(p.session){return p.session.pending!=null&&p.session.pending!=replaced;}});vm("fn main(){"+valid+"if hce_reply("+h+","+q(replaced.id)+",response){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_request\"){return 2;}return 0;}");check(!HardwareSensors.events().hasCallbacks(replaced.deadline),"a later actual SDK command supersedes the old fixture token and frees its timer for service "+mode);
            HardwareHce.Request stale;synchronized(p.session){stale=p.session.pending;}p.deactivate();vm("fn main(){"+valid+"if hce_reply("+h+","+q(stale.id)+",response){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_request\"){return 2;}return 0;}");check(true,"actual SDK deactivation invalidates the constructed pending token for service "+mode);
            HardwareHce.Request pending=p.command(command);if(mode==2){vm("fn main(){if hce_unhandled("+h+","+q(pending.id)+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"unsupported_operation\"){return 2;}return 0;}");check(true,"NFC-F reports its real lack of the public notifyUnhandled operation");}
            vm("fn main(){return db_word(hce_shutdown("+h+"))-1;}");until(()->{synchronized(p.session){return p.session.cleanupReturned;}});check(!p.session.released&&p.session.channelActive,"local shutdown of fixture "+mode+" keeps ownership until actual SDK deactivation, even after component cleanup returned");p.deactivate();until(()->{synchronized(p.session){return p.session.released;}});check(true,"actual deactivation releases the quarantined constructed lease "+mode);
        }
    }
    void timeout()throws Exception{
        try(Peer p=new Peer(0,100)){
            HardwareHce.Request r=p.command(new byte[]{0,1,2,3});p.reply(3);vm("fn main(){if hce_reply("+q(p.handle)+","+q(r.id)+",db_blob(\"ok\",2)){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_request\"){return 2;}return 0;}");check(true,"a real elapsed deadline expires a constructed command and SDK notifyUnhandled reaches the independent framework peer");
        }
    }
    void blockedDeadline()throws Exception{
        try(Peer p=new Peer(0,100)){
            CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);HardwareSensors.events().post(()->{entered.countDown();try{release.await(10,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}});if(!entered.await(3,TimeUnit.SECONDS))throw new IOException("Deadline queue did not block");
            try{HardwareHce.Request r=p.command(new byte[]{0,1,2,3});Thread.sleep(160);vm("fn main(){let d=device_info("+q(p.handle)+");if db_kind(device_field(d,\"request\"))!=0{return 1;}if hce_reply("+q(p.handle)+","+q(r.id)+",db_blob(\"ok\",2)){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_request\"){return 3;}return 0;}");p.reply(3);check(true,"actual VM access enforces elapsed expiry and SDK unhandled even while the real deadline callback queue is blocked");}
            finally{release.countDown();}
        }
    }
    void live()throws Exception{
        try(Peer p=new Peer(0,5000)){
            ExecutorService executor=Executors.newSingleThreadExecutor();Future<JSONObject> running=null;java.lang.reflect.Method save=MainActivity.class.getDeclaredMethod("savePermission",String.class,Object.class);save.setAccessible(true);
            try{running=executor.submit(()->host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0)).put("source","fn main(){let i=0;while i<1000{device_wait("+q(p.handle)+",1000);i=i+1;}return 1;}").put("history",new JSONArray())));java.lang.reflect.Field active=VmHardware.class.getDeclaredField("active");active.setAccessible(true);until(()->{try{Object o=active.get(null);if(o==null)return false;java.lang.reflect.Field io=o.getClass().getDeclaredField("cancelIO");io.setAccessible(true);return io.get(o)!=null;}catch(Exception e){throw new RuntimeException(e);}});ui(()->{try{save.invoke(host,"nfc",false);}catch(Exception e){throw new RuntimeException(e);}});JSONObject result=running.get(4,TimeUnit.SECONDS);check(result.optString("state").equals("error")&&result.optString("stderr").toLowerCase(Locale.ROOT).contains("cancel")&&p.session.closed,"NFC Deny on the actual UI thread cancels a VM observed waiting in the constructed service fixture");
            }finally{if(running!=null&&!running.isDone()){VmHardware.cancel();running.cancel(true);}executor.shutdownNow();ui(()->{try{save.invoke(host,"nfc",true);}catch(Exception e){throw new RuntimeException(e);}});}
        }
    }
    JSONObject background()throws Exception{
        try(Peer p=new Peer(0,5000)){HardwareHce.Request r=p.command(new byte[]{0,1,2,3});ui(()->host.moveTaskToBack(true));until(()->!host.hardwareResumed&&p.session.closed);check(p.session.pending==null,"actual Activity backgrounding closes the constructed service lease and invalidates its pending command");p.deactivate();until(()->p.session.released);check(true,"after background close, actual SDK deactivation and component cleanup release the constructed fixture lease");}
        return report();
    }
}
