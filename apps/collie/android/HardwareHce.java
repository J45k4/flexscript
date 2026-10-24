package org.flexscript.collie;

import android.content.*;
import android.content.pm.PackageManager;
import android.nfc.NfcAdapter;
import android.nfc.cardemulation.*;
import android.os.*;
import java.io.IOException;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Public NFC service/routing transport. APDU and NFC-F protocols belong to the guest. */
final class HardwareHce {
    static final ThreadPoolExecutor SDK=new ThreadPoolExecutor(1,1,30,TimeUnit.SECONDS,new ArrayBlockingQueue<Runnable>(8),r->{Thread t=new Thread(r,"collie-hce-sdk");t.setDaemon(true);return t;});
    static final Handler MAIN=new Handler(Looper.getMainLooper());
    static Session owner;
    static boolean recovered,recovering;static String recoveryError="";
    static final String[] SERVICES={"CollieHceService","CollieHcePaymentService","CollieHceFService"};
    static boolean supports(String op){return op.startsWith("hce_")||op.startsWith("hcef_");}
    static ComponentName component(android.content.Context c,int mode){return new ComponentName(c.getPackageName(),c.getPackageName()+"."+SERVICES[mode]);}
    static String category(int mode){return mode==1?CardEmulation.CATEGORY_PAYMENT:CardEmulation.CATEGORY_OTHER;}
    static boolean supported(android.content.Context c,NfcAdapter adapter,int mode){return adapter!=null&&c.getPackageManager().hasSystemFeature(mode==2?PackageManager.FEATURE_NFC_HOST_CARD_EMULATION_NFCF:PackageManager.FEATURE_NFC_HOST_CARD_EMULATION);}
    static boolean owned(){synchronized(HardwareNfc.LEASE){return owner!=null||recovering;}}
    static void hidden(){Session s;synchronized(HardwareNfc.LEASE){s=owner;}if(s!=null)try{s.close();}catch(IOException ignored){}}
    static void visible(VmHardware.Context c)throws Exception{HardwareNfc.permission(c);if(!c.host.hardwareResumed)throw new VmHardware.Failure("foreground_required","NFC card emulation requires a resumed Collie Activity.");}
    static void enabled(android.content.Context c,int mode,boolean value){c.getPackageManager().setComponentEnabledSetting(component(c,mode),value?PackageManager.COMPONENT_ENABLED_STATE_ENABLED:PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,PackageManager.DONT_KILL_APP);}
    static void recoverAsync(android.content.Context context){
        final android.content.Context app=context.getApplicationContext();
        synchronized(HardwareNfc.LEASE){if(recovered||recovering||owner!=null)return;recovering=true;}
        SDK.execute(()->{String error="";NfcAdapter adapter=null;try{adapter=NfcAdapter.getDefaultAdapter(app);}catch(Exception e){error=MainActivity.safe(e);}
            for(int mode=0;mode<3;mode++){
                try{if(supported(app,adapter,mode)){
                    if(mode==2){NfcFCardEmulation f=NfcFCardEmulation.getInstance(adapter);if(f.getSystemCodeForService(component(app,mode))!=null&&!f.unregisterSystemCodeForService(component(app,mode)))throw new IOException("Android did not remove the interrupted NFC-F registration.");}
                    else{CardEmulation h=CardEmulation.getInstance(adapter);if(h.getAidsForService(component(app,mode),category(mode))!=null&&!h.removeAidsForService(component(app,mode),category(mode)))throw new IOException("Android did not remove an interrupted AID registration.");}
                }}catch(Exception e){error=MainActivity.safe(e);}finally{try{enabled(app,mode,false);}catch(Exception e){error=MainActivity.safe(e);}}
            }
        synchronized(HardwareNfc.LEASE){recoveryError=error;recovered=error.isEmpty();recovering=false;}});
    }
    static void serviceCreated(android.app.Service service,int mode){synchronized(HardwareNfc.LEASE){if(owner==null){recovered=false;recoverAsync(service);}}}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{
        NfcAdapter adapter=HardwareNfc.optional(c);for(int mode:new int[]{0,2}){boolean s=supported(c.host,adapter,mode);out.put(VmHardware.object("id",mode==2?"nfc_hcef":"nfc_hce","implemented",true,"supported",s,"available",s&&adapter.isEnabled()&&c.host.hardwareResumed,"permission","nfc","foreground_required",true,"max_sessions",1));}
    }
    static JSONObject info(VmHardware.Context c)throws Exception{
        NfcAdapter a=HardwareNfc.optional(c);JSONObject out=VmHardware.object("supported",supported(c.host,a,0),"supported_f",supported(c.host,a,2),"enabled",a!=null&&a.isEnabled(),"foreground",c.host.hardwareResumed,"foreground_required",true,"maximum_command_bytes",65544,"maximum_response_bytes",65538,"maximum_nfcf_bytes",255);
        synchronized(HardwareNfc.LEASE){out.put("recovery_pending",!recovered).put("recovery_error",recoveryError).put("owned",owner!=null);}
        if(supported(c.host,a,0)){CardEmulation h=CardEmulation.getInstance(a);out.put("aid_prefix_supported",h.supportsAidPrefixRegistration());for(int mode=0;mode<2;mode++)out.put(category(mode),VmHardware.object("foreground_preference_allowed",h.categoryAllowsForegroundPreference(category(mode)),"selection_mode",h.getSelectionModeForCategory(category(mode)),"default_service",h.isDefaultServiceForCategory(component(c.host,mode),category(mode))));}
        return out;
    }
    static ArrayList<String> aids(Object value)throws Exception{
        if(!(value instanceof JSONArray)||((JSONArray)value).length()<1||((JSONArray)value).length()>32)throw new VmHardware.Failure("invalid_argument","Use a list of1..32 AIDs.");JSONArray rows=(JSONArray)value;ArrayList<String> out=new ArrayList<>();HashSet<String> seen=new HashSet<>();
        for(int i=0;i<rows.length();i++){String id=VmHardware.text(rows,i,33).toUpperCase(Locale.ROOT);String hex=id.endsWith("*")||id.endsWith("#")?id.substring(0,id.length()-1):id;if(hex.length()<10||hex.length()>32||(hex.length()&1)!=0||!hex.matches("[0-9A-F]+")||!seen.add(id))throw new VmHardware.Failure("invalid_argument","Use1..32 distinct hexadecimal5..16-byte AIDs, optionally ending in * or #.");out.add(id);}return out;
    }
    static String hex(JSONArray a,int index,int chars)throws Exception{String s=VmHardware.text(a,index,chars).toUpperCase(Locale.ROOT);if(s.length()!=chars||!s.matches("[0-9A-F]+"))throw new VmHardware.Failure("invalid_argument","Expected exactly"+chars+" hexadecimal characters.");return s;}
    interface Endpoint {void response(byte[] value);void unhandled();}
    static final class Request {
        final String id="hce-request-"+UUID.randomUUID();final byte[] bytes;final Endpoint endpoint;final long expires;boolean queued;Runnable deadline;byte[] response;int written;
        Request(byte[] bytes,Endpoint endpoint,int timeout){this.bytes=bytes.clone();this.endpoint=endpoint;expires=SystemClock.elapsedRealtime()+timeout;}
        JSONObject value()throws Exception{return VmHardware.object("id",id,"bytes",bytes.length,"data",bytes.length<=32768?VmHardware.bytes(bytes):JSONObject.NULL,"deadline_elapsed_ms",expires,"reply_queued",queued,"response_bytes",response==null?0:response.length,"response_written",written);}
    }
    static final class Session extends VmHardware.Handle {
        final VmHardware.Context context;final NfcAdapter adapter;final int mode,timeout;final ArrayList<String> aids;final String systemCode,nfcid2;
        CardEmulation apdu;NfcFCardEmulation nfcf;Request pending;Endpoint channel;
        String state="registering",cleanupError="";boolean starting,componentEnabled,registered,registrationAttempted,preferred,watching,cleanupQueued,cleaned,cleanupReturned,released,channelActive;long startupDeadline;
        final BroadcastReceiver radio=new BroadcastReceiver(){public void onReceive(android.content.Context ignored,Intent intent){if(adapter!=null&&!adapter.isEnabled())try{close();}catch(IOException ignoredError){}}};
        final Runnable startupTimer=this::expireStartup;
        Session(VmHardware.Context c,NfcAdapter a,int mode,int timeout,ArrayList<String> aids,String code,String id){super(c,"nfc",mode==2?"nfc_hcef":"nfc_hce");context=c;adapter=a;this.mode=mode;this.timeout=timeout;this.aids=aids;systemCode=code;nfcid2=id;}
        void event(String name,Object... fields){HardwareBle.event(this,name,fields);}
        synchronized boolean stopping(){return closed||state.equals("error")||state.equals("stopping")||state.equals("closed");}
        synchronized void expireStartup(){if(state.equals("registering")&&SystemClock.elapsedRealtime()>=startupDeadline){state="error";event("error","code","timeout","message","NFC registration exceeded its10-second startup deadline.");cleanup();}}
        void guard()throws Exception{synchronized(this){expireStartup();check();if(stopping())throw new VmHardware.Failure("cancelled","NFC registration closed or expired.");}visible(context);if(!adapter.isEnabled())throw new VmHardware.Failure("nfc_disabled","Enable NFC in Android settings.");}
        void register(ComponentName name)throws Exception{
            synchronized(this){registrationAttempted=true;}
            // PackageManager enabling and the NFC service's package scan are
            // asynchronous. Replacing this same owned registration is idempotent.
            long end=SystemClock.elapsedRealtime()+3000;
            while(true){guard();boolean ok=mode==2?nfcf.registerSystemCodeForService(name,systemCode):apdu.registerAidsForService(name,category(mode),aids);if(ok){synchronized(this){registered=true;}return;}if(SystemClock.elapsedRealtime()>=end)throw new VmHardware.Failure("routing_denied","Android rejected the registration after its component-cache grace period.");Thread.sleep(50);}
        }
        void start(){synchronized(this){starting=true;startupDeadline=SystemClock.elapsedRealtime()+10000;}HardwareSensors.events().postDelayed(startupTimer,10000);
            SDK.execute(()->{try{
                guard();IntentFilter filter=new IntentFilter(NfcAdapter.ACTION_ADAPTER_STATE_CHANGED);if(Build.VERSION.SDK_INT>=33)context.host.registerReceiver(radio,filter,null,HardwareSensors.events(),android.content.Context.RECEIVER_EXPORTED);else context.host.registerReceiver(radio,filter,null,HardwareSensors.events());synchronized(this){watching=true;}guard();enabled(context.host,mode,true);synchronized(this){componentEnabled=true;}guard();ComponentName component=component(context.host,mode);
                if(mode==2){nfcf=NfcFCardEmulation.getInstance(adapter);register(component);guard();if(!nfcf.setNfcid2ForService(component,nfcid2))throw new VmHardware.Failure("routing_denied","Android rejected the NFCID2.");}
                else{apdu=CardEmulation.getInstance(adapter);for(String id:aids)if(id.endsWith("*")&&!apdu.supportsAidPrefixRegistration())throw new VmHardware.Failure("unsupported_operation","Android does not support AID prefixes.");register(component);}
                // Serialize Activity-scoped preference with onPause. NFC-F's
                // public disableService rejects an already-paused Activity.
                MAIN.post(()->{try{guard();boolean ok=mode==2?nfcf.enableService(context.host,component):apdu.setPreferredService(context.host,component);if(!ok)throw new VmHardware.Failure("routing_denied","Android/user routing policy did not prefer this service.");synchronized(Session.this){preferred=true;}guard();synchronized(Session.this){state="ready";event("ready","sdk_registration_returned",true,"radio_exchange_verified",false);}}catch(Exception e){failed(e);}finally{started();}});
            }catch(Exception e){failed(e);started();}});
        }
        synchronized void failed(Exception e){if(!closed){state="error";event("error","code",e instanceof VmHardware.Failure?((VmHardware.Failure)e).code:"sdk_error","message",MainActivity.safe(e));}}
        synchronized void started(){starting=false;HardwareSensors.events().removeCallbacks(startupTimer);if(stopping())cleanup();}
        public void access(VmHardware.Context c)throws Exception{super.access(c);try{visible(c);if(adapter!=null&&!adapter.isEnabled())throw new VmHardware.Failure("nfc_disabled","NFC was disabled; reopen after enabling it.");}catch(Exception e){close();throw e;}}
        synchronized boolean accepts(){expireStartup();return !closed&&state.equals("ready")&&context.host.hardwareResumed;}
        synchronized boolean incoming(byte[] bytes,Endpoint endpoint){
            if(!accepts())return false;
            if(pending!=null){event("request_superseded","request",pending.id);clearPending();}
            channel=endpoint;channelActive=true;
            try{if(bytes==null||bytes.length<(mode==2?2:4)||bytes.length>(mode==2?255:65544)||mode==2&&(bytes[0]&255)!=bytes.length){event("error","code","size_limit","message","The actual SDK command exceeds the bounded protocol frame or has an invalid NFC-F length.");return false;}
                Request r=new Request(bytes,endpoint,timeout);pending=r;event("command","request",r.value(),"sdk_callback",true);r.deadline=()->expire(r);HardwareSensors.events().postDelayed(r.deadline,timeout);return true;
            }catch(Exception e){event("error","code","callback_failed","message",MainActivity.safe(e));return false;}
        }
        synchronized void clearPending(){if(pending!=null&&pending.deadline!=null)HardwareSensors.events().removeCallbacks(pending.deadline);pending=null;}
        void expire(Request r){synchronized(this){if(pending!=r||SystemClock.elapsedRealtime()<r.expires)return;clearPending();event("request_expired","request",r.id);}MAIN.post(()->{synchronized(Session.this){if(!closed&&channelActive&&channel==r.endpoint&&pending==null&&mode!=2)try{r.endpoint.unhandled();}catch(Exception e){failed(e);cleanup();}}});}
        synchronized void deactivated(Endpoint endpoint,int reason,boolean destroyed){if(channel!=endpoint)return;clearPending();channel=null;channelActive=false;event(destroyed?"service_destroyed":"deactivated","reason",reason,"sdk_callback",true);if(destroyed&&!stopping()){state="error";cleanup();}release();}
        synchronized Request request(String id)throws Exception{check();expireStartup();Request r=pending;if(r!=null&&SystemClock.elapsedRealtime()>=r.expires){expire(r);r=null;}if(r==null||!r.id.equals(id)||r.queued)throw new VmHardware.Failure("stale_request","That command expired, deactivated, was answered or belongs to another session.");return r;}
        synchronized Object read(String id,int offset,int limit)throws Exception{Request r=request(id);if(offset>r.bytes.length)throw new VmHardware.Failure("invalid_argument","Command offset exceeds its actual length.");int end=Math.min(r.bytes.length,offset+limit);return VmHardware.object("value",VmHardware.bytes(Arrays.copyOfRange(r.bytes,offset,end)),"total",r.bytes.length,"next",end<r.bytes.length?end:-1);}
        synchronized int beginReply(String id,int length)throws Exception{Request r=request(id);if(length<2||length>(mode==2?255:65538))throw new VmHardware.Failure("invalid_argument","Response size exceeds the actual APDU/NFC-F protocol bound.");if(r.response!=null)throw new VmHardware.Failure("busy","This command already has a staged response; continue at response_written.");r.response=new byte[length];r.written=0;return length;}
        synchronized int writeReply(String id,int offset,byte[] bytes)throws Exception{Request r=request(id);if(r.response==null)throw new VmHardware.Failure("not_ready","Begin the staged response first.");if(bytes.length==0||offset!=r.written||bytes.length>r.response.length-offset)throw new VmHardware.Failure("invalid_argument","Append a nonempty response chunk at exactly response_written without exceeding its declared length.");System.arraycopy(bytes,0,r.response,offset,bytes.length);r.written+=bytes.length;return bytes.length;}
        synchronized int commitReply(String id)throws Exception{Request r=request(id);if(r.response==null||r.written!=r.response.length)throw new VmHardware.Failure("not_ready","Write every declared response byte before commit.");return reply(id,r.response,false);}
        int reply(String id,byte[] bytes,boolean unhandled)throws Exception{
            if(!unhandled&&(bytes.length<2||bytes.length>(mode==2?255:65538)||mode==2&&(bytes[0]&255)!=bytes.length))throw new VmHardware.Failure("invalid_argument","Use a bounded APDU response or a2..255-byte NFC-F packet with its exact leading length.");if(unhandled&&mode==2)throw new VmHardware.Failure("unsupported_operation","HostNfcFService has no public notifyUnhandled operation.");
            final Request r;final byte[] copy=bytes.clone();synchronized(this){if(!accepts())throw new VmHardware.Failure("not_ready","Wait for actual SDK registration.");r=request(id);r.queued=true;}
            MAIN.post(()->{synchronized(Session.this){if(pending!=r||!accepts()||channel!=r.endpoint)return;if(SystemClock.elapsedRealtime()>=r.expires){expire(r);return;}clearPending();try{if(unhandled)r.endpoint.unhandled();else r.endpoint.response(copy);event(unhandled?"unhandled_submitted":"reply_submitted","request",r.id,"sdk_call_returned",true,"peer_receipt_verified",false);}catch(Exception e){event("error","code","reply_failed","message",MainActivity.safe(e));}}});return 1;
        }
        synchronized void release(){if(!released&&cleaned&&!starting&&!channelActive){released=true;state="closed";synchronized(HardwareNfc.LEASE){if(owner==this)owner=null;}event("closed","sdk_cleanup_returned",cleanupReturned,"lease_released",true);}}
        synchronized void cleanup(){if(starting||cleanupQueued)return;cleanupQueued=true;clearPending();HardwareSensors.events().removeCallbacks(startupTimer);
            Runnable foreground=()->{String failure="";synchronized(Session.this){try{if(channelActive&&channel!=null&&mode!=2)channel.unhandled();}catch(Exception e){failure=MainActivity.safe(e);}if(preferred)try{boolean ok=mode==2?nfcf.disableService(context.host):apdu.unsetPreferredService(context.host);if(!ok)throw new IOException("Android did not remove foreground NFC routing.");preferred=false;}catch(Exception e){failure=MainActivity.safe(e);}}
                final String foregroundError=failure;SDK.execute(()->{String error=foregroundError;
                    if(registrationAttempted)try{ComponentName name=component(context.host,mode);boolean present=mode==2?nfcf.getSystemCodeForService(name)!=null:apdu.getAidsForService(name,category(mode))!=null;if(present){boolean ok=mode==2?nfcf.unregisterSystemCodeForService(name):apdu.removeAidsForService(name,category(mode));if(!ok)throw new IOException("Android did not remove the owned NFC registration.");}synchronized(Session.this){registered=false;registrationAttempted=false;}}catch(Exception e){error=MainActivity.safe(e);}
                    try{enabled(context.host,mode,false);synchronized(Session.this){componentEnabled=false;}}catch(Exception e){error=MainActivity.safe(e);}if(watching)try{context.host.unregisterReceiver(radio);synchronized(Session.this){watching=false;}}catch(Exception e){error=MainActivity.safe(e);}
                    synchronized(Session.this){cleanupReturned=true;cleanupError=error;cleaned=error.isEmpty();if(!cleaned){state="error";cleanupQueued=false;event("error","code","cleanup_failed","message",error);}release();}
                });
            };if(Looper.myLooper()==Looper.getMainLooper())foreground.run();else MAIN.post(foreground);
        }
        synchronized Object info()throws Exception{check();expireStartup();if(pending!=null&&SystemClock.elapsedRealtime()>=pending.expires)expire(pending);return VmHardware.object("kind",kind,"state",state,"category",mode==2?"nfcf":category(mode),"reply_timeout_ms",timeout,"request",pending==null?JSONObject.NULL:pending.value(),"channel_active",channelActive,"sdk_registered",registered,"sdk_preferred",preferred,"sdk_cleanup_returned",cleanupReturned,"lease_released",released,"cleanup_error",cleanupError);}
        synchronized int shutdown()throws Exception{check();if(state.equals("closed")||state.equals("stopping")&&cleanupQueued)return 0;state="stopping";clearPending();cleanup();return 1;}
        public synchronized void close()throws IOException{if(closed)return;super.close();state="stopping";clearPending();cleanup();}
    }
    static Session current(int mode){Session s;synchronized(HardwareNfc.LEASE){s=owner;}return s!=null&&s.mode==mode&&s.accepts()?s:null;}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(op.equals("hce_info")){recoverAsync(c.host);return info(c);}
        if(op.equals("hce_open")||op.equals("hcef_open")){
            int mode,timeout;ArrayList<String> ids=null;String code="",id="";
            if(op.equals("hce_open")){mode=VmHardware.integer(a,0,0,1);ids=aids(a.get(1));timeout=VmHardware.integer(a,2,20,5000);}
            else{mode=2;code=hex(a,0,4);id=hex(a,1,16);if(code.charAt(0)!='4'||code.endsWith("FF")||!id.startsWith("02FE"))throw new VmHardware.Failure("invalid_argument","Use an NFC-F system code4000..4FFF excluding4*FF, and a16-digit NFCID2 beginning02FE.");timeout=VmHardware.integer(a,2,20,5000);}
            visible(c);NfcAdapter adapter=HardwareNfc.optional(c);if(!supported(c.host,adapter,mode))throw new VmHardware.Failure("unsupported",mode==2?"Android has no NFC-F host card emulation adapter.":"Android has no ISO-DEP host card emulation adapter.");if(!adapter.isEnabled())throw new VmHardware.Failure("nfc_disabled","Enable NFC in Android settings.");recoverAsync(c.host);
            Session session=new Session(c,adapter,mode,timeout,ids,code,id);
            synchronized(HardwareNfc.LEASE){if(!recovered)throw new VmHardware.Failure("recovery_pending","Wait for interrupted NFC registration cleanup: "+recoveryError);if(owner!=null||HardwareNfc.readerOwned())throw new VmHardware.Failure("busy","Close the owned NFC reader/card-emulation lease and wait for SDK/link cleanup first.");owner=session;}
            VmHardware.blocking(session);try{String handle=VmHardware.add(session);session.start();return handle;}catch(Exception e){session.close();throw e;}finally{VmHardware.unblocking();}
        }
        Session s=VmHardware.handle(c,VmHardware.text(a,0,128),Session.class);s.access(c);VmHardware.blocking(s);
        try{if(op.equals("hce_request")){synchronized(s){if(s.pending!=null&&SystemClock.elapsedRealtime()>=s.pending.expires)s.expire(s.pending);return s.pending==null?JSONObject.NULL:s.pending.value();}}
            if(op.equals("hce_reply"))return s.reply(VmHardware.text(a,1,128),VmHardware.data(a.get(2)),false);
            if(op.equals("hce_request_read"))return s.read(VmHardware.text(a,1,128),VmHardware.integer(a,2,0,65544),VmHardware.integer(a,3,1,32768));
            if(op.equals("hce_reply_begin"))return s.beginReply(VmHardware.text(a,1,128),VmHardware.integer(a,2,2,65538));
            if(op.equals("hce_reply_write"))return s.writeReply(VmHardware.text(a,1,128),VmHardware.integer(a,2,0,65538),VmHardware.data(a.get(3)));
            if(op.equals("hce_reply_commit"))return s.commitReply(VmHardware.text(a,1,128));
            if(op.equals("hce_unhandled"))return s.reply(VmHardware.text(a,1,128),new byte[0],true);
            if(op.equals("hce_shutdown"))return s.shutdown();
            throw new VmHardware.Failure("unsupported_operation","Unknown card emulation operation.");
        }finally{VmHardware.unblocking();}
    }
}
