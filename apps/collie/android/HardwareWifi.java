package org.flexscript.collie;

import android.Manifest;
import android.content.*;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.net.*;
import android.net.wifi.*;
import android.os.Build;
import android.util.AtomicFile;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Android Wi-Fi objects/callbacks. Guest grants and protocols remain Flexscript. */
final class HardwareWifi {
    static boolean supports(String op){return op.startsWith("wifi_");}
    private static final Object LEASES=new Object();
    private static final Map<String,Suggestion> SUGGESTIONS=new HashMap<>();
    private static Hotspot hotspot;
    private static final ExecutorService RECOVERY=new ThreadPoolExecutor(0,1,30,TimeUnit.SECONDS,new SynchronousQueue<Runnable>(),task->{Thread thread=new Thread(task,"collie-wifi-recovery");thread.setDaemon(true);return thread;});
    static void recoverAsync(Context host){Context app=host.getApplicationContext();try{RECOVERY.execute(()->{try{recover(app);}catch(Exception error){android.util.Log.w("Collie","Wi-Fi suggestion recovery remains pending.");}});}catch(RejectedExecutionException ignored){}}
    private static Executor events(){return task->HardwareSensors.events().post(task);}
    private static Context app(VmHardware.Context c){return c.host.getApplicationContext();}
    private static WifiManager manager(VmHardware.Context c)throws Exception{
        WifiManager manager=app(c).getSystemService(WifiManager.class);
        if(manager==null||!app(c).getPackageManager().hasSystemFeature(PackageManager.FEATURE_WIFI))throw new VmHardware.Failure("unsupported","This device has no Android Wi-Fi service.");return manager;
    }
    private static void require(VmHardware.Context c,String key,String... permissions)throws Exception{try{VmHardware.require(c,permissions);}catch(VmHardware.Consent consent){consent.request.put("key",key);throw consent;}}
    private static void location(VmHardware.Context c,boolean enabled)throws Exception{
        require(c,"location",Manifest.permission.ACCESS_COARSE_LOCATION,Manifest.permission.ACCESS_FINE_LOCATION);
        LocationManager lm=app(c).getSystemService(LocationManager.class);
        if(enabled&&(lm==null||!(Build.VERSION.SDK_INT>=28?lm.isLocationEnabled():lm.isProviderEnabled(LocationManager.GPS_PROVIDER)||lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER))))throw new VmHardware.Failure("location_disabled","Turn on Android Location before reading Wi-Fi scan/identity data.");
    }
    private static void nearby(VmHardware.Context c)throws Exception{if(Build.VERSION.SDK_INT>=33)require(c,"wifi",Manifest.permission.NEARBY_WIFI_DEVICES);location(c,Build.VERSION.SDK_INT<33);}
    private static void visible(VmHardware.Context c)throws Exception{if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Start this Wi-Fi operation while Collie is visible.");}
    private static void enabled(WifiManager manager)throws Exception{if(!manager.isWifiEnabled())throw new VmHardware.Failure("wifi_disabled","Turn on Wi-Fi in Android settings first.");}
    private static String bounded(String value,int size){return value==null?null:value.length()>size?value.substring(0,size):value;}
    private static Object value(String text){return text==null?JSONObject.NULL:text;}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{
        boolean supported=app(c).getPackageManager().hasSystemFeature(PackageManager.FEATURE_WIFI);WifiManager wm=app(c).getSystemService(WifiManager.class);boolean available=supported&&wm!=null;
        out.put(VmHardware.capability("wifi_status",supported,available,"wifi"));out.put(VmHardware.object("id","wifi_scan","implemented",true,"supported",supported,"available",available&&(wm.isScanAlwaysAvailable()||wm.isWifiEnabled()),"permission","wifi","also","location"));
        out.put(VmHardware.capability("wifi_request",supported&&Build.VERSION.SDK_INT>=29,available&&Build.VERSION.SDK_INT>=29,"wifi"));out.put(VmHardware.capability("wifi_suggestions",supported&&Build.VERSION.SDK_INT>=29,available&&Build.VERSION.SDK_INT>=29,"wifi"));out.put(VmHardware.capability("wifi_local_hotspot",supported,available,"wifi"));
    }
    private static Object info(WifiManager wm)throws Exception{
        JSONObject info=VmHardware.object("enabled",wm.isWifiEnabled(),"state",wm.getWifiState(),"scan_always_available",wm.isScanAlwaysAvailable(),"five_ghz",wm.is5GHzBandSupported(),"p2p",wm.isP2pSupported());
        if(Build.VERSION.SDK_INT>=29){info.put("wpa3_sae",wm.isWpa3SaeSupported());info.put("enhanced_open",wm.isEnhancedOpenSupported());info.put("sta_ap_concurrency",wm.isStaApConcurrencySupported());}
        if(Build.VERSION.SDK_INT>=30)info.put("six_ghz",wm.is6GHzBandSupported());if(Build.VERSION.SDK_INT>=31)info.put("local_sta_concurrency",wm.isStaConcurrencyForLocalOnlyConnectionsSupported());return info;
    }
    private static Object connection(WifiManager wm)throws Exception{
        WifiInfo info=wm.getConnectionInfo();if(info==null||info.getNetworkId()<0)return JSONObject.NULL;
        JSONObject result=VmHardware.object("ssid",value(bounded(info.getSSID(),256)),"bssid",value(info.getBSSID()),"network_id",info.getNetworkId(),"rssi_dbm",info.getRssi(),"frequency_mhz",info.getFrequency(),"link_mbps",info.getLinkSpeed(),"supplicant",info.getSupplicantState().name(),"hidden",info.getHiddenSSID());
        if(Build.VERSION.SDK_INT>=29){result.put("tx_mbps",info.getTxLinkSpeedMbps());result.put("rx_mbps",info.getRxLinkSpeedMbps());}if(Build.VERSION.SDK_INT>=30)result.put("standard",info.getWifiStandard());if(Build.VERSION.SDK_INT>=31)result.put("security",info.getCurrentSecurityType());return result;
    }
    private static JSONObject scan(ScanResult r)throws Exception{
        JSONObject row=VmHardware.object("ssid",value(bounded(r.SSID,256)),"bssid",value(r.BSSID),"capabilities",value(bounded(r.capabilities,2048)),"rssi_dbm",r.level,"frequency_mhz",r.frequency,"timestamp_us",r.timestamp,"channel_width",r.channelWidth,"center_frequency0_mhz",r.centerFreq0,"center_frequency1_mhz",r.centerFreq1,"rtt_responder",r.is80211mcResponder());
        if(Build.VERSION.SDK_INT>=30)row.put("standard",r.getWifiStandard());if(Build.VERSION.SDK_INT>=33){row.put("ssid_bytes",r.getWifiSsid()==null?JSONObject.NULL:VmHardware.bytes(r.getWifiSsid().getBytes()));JSONArray types=new JSONArray();for(int type:r.getSecurityTypes())types.put(type);row.put("security_types",types);}return row;
    }
    static final class Watch extends VmHardware.Handle {
        final Context app;final BroadcastReceiver receiver;
        Watch(VmHardware.Context c)throws Exception{super(c,"wifi","wifi_state");app=app(c);receiver=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){try{emit(VmHardware.object("event",WifiManager.WIFI_STATE_CHANGED_ACTION.equals(intent.getAction())?"state":"scan_availability","value",HardwareWifi.info(manager(c))));}catch(Exception ignoredError){}}};}
        void start()throws Exception{IntentFilter filter=new IntentFilter(WifiManager.WIFI_STATE_CHANGED_ACTION);filter.addAction(WifiManager.ACTION_WIFI_SCAN_AVAILABILITY_CHANGED);register(app,receiver,filter);emit(VmHardware.object("event","ready"));}
        public synchronized void close()throws IOException{if(closed)return;super.close();try{app.unregisterReceiver(receiver);}catch(IllegalArgumentException ignored){}}
    }
    private static void register(Context app,BroadcastReceiver receiver,IntentFilter filter){if(Build.VERSION.SDK_INT>=33)app.registerReceiver(receiver,filter,Context.RECEIVER_NOT_EXPORTED);else app.registerReceiver(receiver,filter);}
    static final class Scan extends VmHardware.Handle {
        final VmHardware.Context context;final WifiManager manager;final BroadcastReceiver receiver;private List<ScanResult> rows=Collections.emptyList();private int reported;private String state="pending";private boolean registered;
        private final Runnable deadline=()->fail("timeout","Android did not report Wi-Fi scan completion within20 seconds.");
        Scan(VmHardware.Context c,WifiManager manager){super(c,"wifi","wifi_scan","location");context=c;this.manager=manager;receiver=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){try{ready(intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED,false),"broadcast");}catch(Exception error){fail("scan_failed",MainActivity.safe(error));}}};}
        synchronized void ready(boolean updated,String source)throws Exception{if(closed||!state.equals("pending"))return;List<ScanResult> values=manager.getScanResults();reported=values.size();rows=new ArrayList<>(values.subList(0,Math.min(128,values.size())));state="ready";finish();emit(VmHardware.object("event","scan","updated",updated,"source",source,"total",rows.size(),"reported_total",reported,"truncated",reported>rows.size()));}
        private void finish(){HardwareSensors.events().removeCallbacks(deadline);if(registered){registered=false;try{app(context).unregisterReceiver(receiver);}catch(IllegalArgumentException ignored){}}}
        synchronized void fail(String code,String message){if(closed||!state.equals("pending"))return;state="error";finish();try{emit(VmHardware.object("event","error","code",code,"message",message));}catch(Exception ignored){}}
        void start(boolean refresh)throws Exception{if(!refresh){ready(false,"cached");return;}synchronized(this){registered=true;register(app(context),receiver,new IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION));HardwareSensors.events().postDelayed(deadline,20000);if(!manager.startScan())throw new VmHardware.Failure("scan_throttled","Android refused the scan. Use cached mode0 or wait for the platform scan throttle.");}}
        public void access(VmHardware.Context c)throws Exception{check();location(c,true);}
        synchronized List<ScanResult> rttTargets(JSONArray bssids)throws Exception{
            check();if(!state.equals("ready"))throw new VmHardware.Failure("not_ready","Wait for a completed Wi-Fi scan before selecting RTT peers.");
            Set<String> seen=new HashSet<>();List<ScanResult> result=new ArrayList<>();
            for(int i=0;i<bssids.length();i++){String bssid=VmHardware.text(bssids,i,17).toLowerCase(Locale.ROOT);if(!bssid.matches("[0-9a-f]{2}(:[0-9a-f]{2}){5}")||!seen.add(bssid))throw new VmHardware.Failure("invalid_argument","RTT requires distinct BSSIDs from this scan snapshot.");ScanResult found=null;for(ScanResult row:rows)if(bssid.equalsIgnoreCase(row.BSSID)){found=row;break;}if(found==null)throw new VmHardware.Failure("not_found","The requested RTT access point is absent from this scan snapshot.");result.add(found);}return result;
        }
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"total",rows.size(),"reported_total",reported,"truncated",reported>rows.size());}
        synchronized Object page(int offset,int limit)throws Exception{check();if(!state.equals("ready"))throw new VmHardware.Failure(state.equals("pending")?"not_ready":"scan_failed","Wait for the scan event or open a new scan snapshot.");JSONArray result=new JSONArray();for(int i=offset;i<Math.min(rows.size(),offset+limit);i++)result.put(scan(rows.get(i)));return VmHardware.object("access_points",result,"total",rows.size(),"reported_total",reported,"truncated",reported>rows.size(),"next",offset+result.length()<rows.size()?offset+result.length():-1);}
        public synchronized void close()throws IOException{if(closed)return;super.close();finish();rows=Collections.emptyList();}
    }
    private static JSONObject config(JSONArray a,boolean request)throws Exception{
        String ssid=VmHardware.text(a,0,32),security=VmHardware.text(a,1,16),password=VmHardware.text(a,2,64);if(ssid.isEmpty()||ssid.getBytes(StandardCharsets.UTF_8).length>32)throw new VmHardware.Failure("invalid_argument","Wi-Fi SSIDs require1..32 UTF-8 bytes.");
        if(!Arrays.asList("open","owe","wpa2","wpa3").contains(security))throw new VmHardware.Failure("invalid_argument","Use open, owe, wpa2 or wpa3 personal Wi-Fi security.");
        if((security.equals("open")||security.equals("owe"))&&!password.isEmpty())throw new VmHardware.Failure("invalid_argument","Open/OWE networks cannot have a password.");
        if(security.equals("wpa2")||security.equals("wpa3")){if(password.length()<8||password.length()>63)throw new VmHardware.Failure("invalid_argument","Personal Wi-Fi passphrases require8..63 ASCII characters.");for(int i=0;i<password.length();i++)if(password.charAt(i)<32||password.charAt(i)>126)throw new VmHardware.Failure("invalid_argument","Personal Wi-Fi passphrases must be printable ASCII.");}
        JSONObject result=VmHardware.object("ssid",ssid,"security",security,"password",password);
        if(request){String bssid=VmHardware.text(a,3,17);if(!bssid.isEmpty()){if(!bssid.matches("(?i)[0-9a-f]{2}(:[0-9a-f]{2}){5}"))throw new VmHardware.Failure("invalid_argument","BSSID must be a six-byte MAC address or empty.");MacAddress address=MacAddress.fromString(bssid);if(address.getAddressType()!=MacAddress.TYPE_UNICAST||bssid.equalsIgnoreCase("00:00:00:00:00:00"))throw new VmHardware.Failure("invalid_argument","BSSID must be a nonzero unicast address.");}result.put("bssid",bssid);result.put("hidden",VmHardware.integer(a,4,0,1)==1);result.put("timeout",VmHardware.integer(a,5,1000,120000));}
        else{result.put("hidden",VmHardware.integer(a,3,0,1)==1);result.put("metered",VmHardware.integer(a,4,0,1)==1);result.put("autojoin",VmHardware.integer(a,5,0,1)==1);if(Build.VERSION.SDK_INT<30&&!result.getBoolean("autojoin"))throw new VmHardware.Failure("unsupported","Disabling initial autojoin needs Android11 or newer.");}
        return result;
    }
    private static WifiNetworkSpecifier specifier(JSONObject config)throws Exception{
        WifiNetworkSpecifier.Builder b=new WifiNetworkSpecifier.Builder().setSsid(config.getString("ssid")).setIsHiddenSsid(config.getBoolean("hidden"));if(!config.getString("bssid").isEmpty())b.setBssid(MacAddress.fromString(config.getString("bssid")));
        switch(config.getString("security")){case "owe":b.setIsEnhancedOpen(true);break;case "wpa2":b.setWpa2Passphrase(config.getString("password"));break;case "wpa3":b.setWpa3Passphrase(config.getString("password"));break;}return b.build();
    }
    private static WifiNetworkSuggestion suggestion(JSONObject config)throws Exception{
        WifiNetworkSuggestion.Builder b=new WifiNetworkSuggestion.Builder().setSsid(config.getString("ssid")).setIsHiddenSsid(config.getBoolean("hidden")).setIsMetered(config.getBoolean("metered"));
        if(Build.VERSION.SDK_INT>=30)b.setIsInitialAutojoinEnabled(config.getBoolean("autojoin"));switch(config.getString("security")){case "owe":b.setIsEnhancedOpen(true);break;case "wpa2":b.setWpa2Passphrase(config.getString("password"));break;case "wpa3":b.setWpa3Passphrase(config.getString("password"));break;}return b.build();
    }
    static final class Request extends VmHardware.Handle {
        final VmHardware.Context context;final ConnectivityManager manager;final NetworkRequest request;final ConnectivityManager.NetworkCallback callback;final int timeout;volatile Network network;volatile String state="pending";
        Request(VmHardware.Context c,JSONObject config)throws Exception{super(c,"wifi","wifi_request","location");context=c;manager=HardwareNetwork.manager(c);timeout=config.getInt("timeout");request=new NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).setNetworkSpecifier(specifier(config)).build();callback=new ConnectivityManager.NetworkCallback(){
            public void onAvailable(Network n){synchronized(Request.this){if(closed)return;network=n;state="available";event("available",n);}}public void onLost(Network n){synchronized(Request.this){if(closed)return;if(n.equals(network))network=null;state="lost";event("lost",n);}}public void onUnavailable(){synchronized(Request.this){if(closed)return;state="unavailable";event("unavailable",null);}}public void onLinkPropertiesChanged(Network n,LinkProperties p){event("link_changed",n);}
        };}
        void event(String type,Network n){try{emit(VmHardware.object("event",type,"network",n==null?JSONObject.NULL:HardwareNetwork.id(n)));}catch(Exception ignored){}}
        void start(){manager.requestNetwork(request,callback,HardwareSensors.events(),timeout);}
        public void access(VmHardware.Context c)throws Exception{check();nearby(c);}
        public Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"network",network==null?JSONObject.NULL:HardwareNetwork.id(network),"model_route_changed",false);}
        public synchronized void close()throws IOException{if(closed)return;super.close();try{manager.unregisterNetworkCallback(callback);}catch(IllegalArgumentException ignored){}network=null;}
    }
    // Android persists suggestions past process death. Journal before adding;
    // recover only non-live leases, including after restart. Never export PSKs.
    private static File journal(Context app){return new File(app.getFilesDir(),"wifi-leases.json");}
    private static JSONObject readJournal(Context app)throws Exception{File file=journal(app);if(!file.exists())return new JSONObject();if(file.length()>32768)throw new VmHardware.Failure("recovery_required","Wi-Fi lease journal is too large.");return new JSONObject(MainActivity.read(new AtomicFile(file).openRead(),32768));}
    private static void writeJournal(Context app,JSONObject data)throws Exception{MainActivity.atomic(journal(app),data.toString());}
    static void recover(Context host)throws Exception{
        Context app=host.getApplicationContext();synchronized(LEASES){if(!journal(app).exists())return;JSONObject records=readJournal(app);WifiManager manager=app.getSystemService(WifiManager.class);if(manager==null)return;List<String> ids=new ArrayList<>();Iterator<String> keys=records.keys();while(keys.hasNext())ids.add(keys.next());if(ids.size()>32)throw new VmHardware.Failure("recovery_required","Wi-Fi lease journal has too many entries.");
            for(String id:ids){Suggestion live=SUGGESTIONS.get(id);if(live!=null&&!live.closed)continue;int status=manager.removeNetworkSuggestions(Collections.singletonList(suggestion(records.getJSONObject(id))));if(status!=WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS&&status!=WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_REMOVE_INVALID)throw new VmHardware.Failure("cleanup_failed","Android could not remove a prior Wi-Fi suggestion (status"+status+").");records.remove(id);writeJournal(app,records);}
        }
    }
    static final class Suggestion extends VmHardware.Handle {
        final VmHardware.Context context;final WifiManager manager;final JSONObject config;final WifiNetworkSuggestion suggestion;final String lease=UUID.randomUUID().toString();WifiManager.SuggestionUserApprovalStatusListener approval;volatile int approvalStatus=-1;boolean registered;
        Suggestion(VmHardware.Context c,WifiManager manager,JSONObject config)throws Exception{super(c,"wifi","wifi_suggestion");context=c;this.manager=manager;this.config=config;suggestion=suggestion(config);}
        void start()throws Exception{synchronized(LEASES){recover(context.host);VmHardware.check();JSONObject records=readJournal(app(context));if(records.length()>=32)throw new VmHardware.Failure("resource_limit","At most32 Wi-Fi suggestions may be owned by Collie.");for(Suggestion item:SUGGESTIONS.values())if(!item.closed&&item.suggestion.equals(suggestion))throw new VmHardware.Failure("busy","This Wi-Fi suggestion already belongs to another live lease.");records.put(lease,config);writeJournal(app(context),records);SUGGESTIONS.put(lease,this);int status=manager.addNetworkSuggestions(Collections.singletonList(suggestion));if(status!=WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS)throw new VmHardware.Failure("suggestion_rejected","Android rejected the Wi-Fi suggestion (status"+status+").");registered=true;
            if(Build.VERSION.SDK_INT>=31){approval=value->{approvalStatus=value;try{emit(VmHardware.object("event","approval","status",value));}catch(Exception ignored){}};manager.addSuggestionUserApprovalStatusListener(events(),approval);}emit(VmHardware.object("event","accepted"));}}
        public Object info()throws Exception{check();return VmHardware.object("kind",kind,"ssid",config.getString("ssid"),"security",config.getString("security"),"hidden",config.getBoolean("hidden"),"metered",config.getBoolean("metered"),"autojoin",config.getBoolean("autojoin"),"approval_status",approvalStatus,"process_persistent",false);}
        public void close()throws IOException{Exception failure=null;synchronized(LEASES){if(closed)return;super.close();SUGGESTIONS.remove(lease);try{if(Build.VERSION.SDK_INT>=31&&approval!=null)manager.removeSuggestionUserApprovalStatusListener(approval);}catch(Exception error){failure=error;}try{JSONObject records=readJournal(app(context));if(records.has(lease)){int status=manager.removeNetworkSuggestions(Collections.singletonList(suggestion));if(status!=WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS&&status!=WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_REMOVE_INVALID)throw new IOException("Android suggestion cleanup failed (status"+status+"). Retry Wi-Fi access to recover.");records.remove(lease);writeJournal(app(context),records);}}catch(Exception error){failure=error;}}if(failure!=null)throw new IOException(failure);}
    }
    static final class Hotspot extends VmHardware.Handle {
        final VmHardware.Context context;final WifiManager manager;volatile String state="pending";WifiManager.LocalOnlyHotspotReservation reservation;private boolean terminal;
        Hotspot(VmHardware.Context c,WifiManager manager){super(c,"wifi","wifi_hotspot","location");context=c;this.manager=manager;}
        void start()throws Exception{synchronized(LEASES){if(hotspot!=null)throw new VmHardware.Failure("busy","A Collie hotspot request is active or awaiting Android cleanup.");hotspot=this;}try{manager.startLocalOnlyHotspot(new WifiManager.LocalOnlyHotspotCallback(){
            public void onStarted(WifiManager.LocalOnlyHotspotReservation value){synchronized(Hotspot.this){if(closed){value.close();done();return;}reservation=value;state="started";try{emit(VmHardware.object("event","started","config",configuration(false)));}catch(Exception ignored){}}}
            public void onStopped(){synchronized(Hotspot.this){state="stopped";reservation=null;terminal=true;try{emit(VmHardware.object("event","stopped"));}catch(Exception ignored){}done();}}
            public void onFailed(int reason){synchronized(Hotspot.this){state="failed";terminal=true;try{emit(VmHardware.object("event","error","code","hotspot_failed","android_code",reason));}catch(Exception ignored){}done();}}
        },HardwareSensors.events());}catch(Exception error){done();throw error;}}
        private void done(){synchronized(LEASES){if(hotspot==this)hotspot=null;}}
        synchronized JSONObject configuration(boolean secret)throws Exception{if(reservation==null)throw new VmHardware.Failure("not_ready","The local-only hotspot has not started.");JSONObject result;
            if(Build.VERSION.SDK_INT>=30){SoftApConfiguration ap=reservation.getSoftApConfiguration();result=VmHardware.object("ssid",value(ap.getSsid()),"security",ap.getSecurityType(),"hidden",ap.isHiddenSsid());if(secret)result.put("password",value(ap.getPassphrase()));}
            else{WifiConfiguration ap=reservation.getWifiConfiguration();result=VmHardware.object("ssid",value(ap.SSID),"security",ap.allowedKeyManagement.get(WifiConfiguration.KeyMgmt.WPA_PSK)?"wpa2":"open","hidden",ap.hiddenSSID);if(secret)result.put("password",value(ap.preSharedKey));}return result;}
        public void access(VmHardware.Context c)throws Exception{check();nearby(c);}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"internet",false,"config",reservation==null?JSONObject.NULL:configuration(false));}
        public synchronized void close()throws IOException{if(closed)return;super.close();if(reservation!=null){reservation.close();reservation=null;done();}else if(terminal)done();/* No public SDK cancellation before onStarted/onFailed. Late reservations are closed immediately. */}
    }
    private interface Start {void run()throws Exception;}
    private static String publish(VmHardware.Handle handle,Start start)throws Exception{try{start.run();return VmHardware.add(handle);}catch(Exception error){try{handle.close();}catch(Exception ignored){}throw error;}}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(!op.equals("wifi_suggest"))recover(c.host);
        switch(op){
        case "wifi_info":return info(manager(c));
        case "wifi_watch":{manager(c);Watch watch=new Watch(c);return publish(watch,watch::start);}
        case "wifi_connection":{WifiManager wm=manager(c);location(c,true);return connection(wm);}
        case "wifi_scan":{int refresh=VmHardware.integer(a,0,0,1);WifiManager wm=manager(c);location(c,true);if(refresh==1)visible(c);Scan scan=new Scan(c,wm);return publish(scan,()->scan.start(refresh==1));}
        case "wifi_scan_page":{String id=VmHardware.text(a,0,128);int offset=VmHardware.integer(a,1,0,128),limit=VmHardware.integer(a,2,1,16);Scan scan=VmHardware.handle(c,id,Scan.class);scan.access(c);return scan.page(offset,limit);}
        case "wifi_request":{if(Build.VERSION.SDK_INT<29)throw new VmHardware.Failure("unsupported","Android's Wi-Fi network request API needs Android10 or newer.");JSONObject config=config(a,true);WifiManager wm=manager(c);enabled(wm);visible(c);nearby(c);Request request=new Request(c,config);return publish(request,request::start);}
        case "wifi_suggest":{JSONObject config=config(a,false);if(Build.VERSION.SDK_INT<29)throw new VmHardware.Failure("unsupported","Android's Wi-Fi suggestion API needs Android10 or newer.");WifiManager wm=manager(c);visible(c);Suggestion suggestion=new Suggestion(c,wm,config);return publish(suggestion,suggestion::start);}
        case "wifi_hotspot":{WifiManager wm=manager(c);visible(c);nearby(c);Hotspot hotspot=new Hotspot(c,wm);return publish(hotspot,hotspot::start);}
        case "wifi_hotspot_config":{Hotspot hotspot=VmHardware.handle(c,VmHardware.text(a,0,128),Hotspot.class);hotspot.access(c);return hotspot.configuration(true);}
        default:throw new VmHardware.Failure("unsupported_operation","Unknown Android Wi-Fi operation.");
        }
    }
}
