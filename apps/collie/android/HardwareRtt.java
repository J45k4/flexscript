package org.flexscript.collie;

import android.Manifest;
import android.content.*;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.net.wifi.ScanResult;
import android.net.wifi.aware.PeerHandle;
import android.net.wifi.rtt.*;
import android.os.Build;
import java.io.IOException;
import java.util.*;
import org.json.*;

/** Android RTT requests and copied ranging callbacks; no guest positioning policy. */
final class HardwareRtt {
    static boolean supports(String op){return op.startsWith("wifi_rtt_");}
    private static Context app(VmHardware.Context c){return c.host.getApplicationContext();}
    private static boolean supported(VmHardware.Context c){return Build.VERSION.SDK_INT>=28&&app(c).getPackageManager().hasSystemFeature(PackageManager.FEATURE_WIFI_RTT);}
    private static WifiRttManager manager(VmHardware.Context c)throws Exception{
        if(!supported(c))throw new VmHardware.Failure("unsupported","This Android device does not provide Wi-Fi RTT ranging.");
        WifiRttManager manager=app(c).getSystemService(WifiRttManager.class);
        if(manager==null)throw new VmHardware.Failure("unavailable","The Android Wi-Fi RTT service is unavailable.");return manager;
    }
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{
        boolean supported=supported(c);boolean available=supported&&app(c).getSystemService(WifiRttManager.class)!=null&&app(c).getSystemService(WifiRttManager.class).isAvailable();
        out.put(VmHardware.object("id","wifi_rtt","implemented",true,"supported",supported,"available",available,"permission","wifi","also","location"));
    }
    private static void permission(VmHardware.Context c)throws Exception{
        try{VmHardware.require(c,Manifest.permission.ACCESS_COARSE_LOCATION,Manifest.permission.ACCESS_FINE_LOCATION);}catch(VmHardware.Consent consent){consent.request.put("key","location");throw consent;}
        if(Build.VERSION.SDK_INT>=33)try{VmHardware.require(c,Manifest.permission.NEARBY_WIFI_DEVICES);}catch(VmHardware.Consent consent){consent.request.put("key","wifi");throw consent;}
        LocationManager lm=app(c).getSystemService(LocationManager.class);
        if(lm==null||!lm.isLocationEnabled())throw new VmHardware.Failure("location_disabled","Turn on Android Location before Wi-Fi RTT ranging.");
    }
    static JSONObject info(VmHardware.Context c)throws Exception{
        boolean supported=supported(c);JSONObject out=VmHardware.object("supported",supported,"available",supported&&manager(c).isAvailable(),"max_peers",Build.VERSION.SDK_INT>=28?RangingRequest.getMaxPeers():0,"close_cancels_radio",false);
        if(Build.VERSION.SDK_INT>=31)out.put("burst_min",RangingRequest.getMinRttBurstSize()).put("burst_max",RangingRequest.getMaxRttBurstSize()).put("burst_default",RangingRequest.getDefaultRttBurstSize());
        return out;
    }
    static final class Watch extends VmHardware.Handle {
        final VmHardware.Context context;final BroadcastReceiver receiver;boolean registered;
        Watch(VmHardware.Context c){super(c,"wifi","wifi_rtt_state");context=c;receiver=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){try{emit(VmHardware.object("event","availability","available",manager(c).isAvailable()));}catch(Exception error){try{emit(VmHardware.object("event","error","code","platform_error","message",MainActivity.safe(error)));}catch(Exception ignoredError){}}}};}
        void start()throws Exception{
            IntentFilter filter=new IntentFilter(WifiRttManager.ACTION_WIFI_RTT_STATE_CHANGED);
            if(Build.VERSION.SDK_INT>=33)app(context).registerReceiver(receiver,filter,Context.RECEIVER_NOT_EXPORTED);else app(context).registerReceiver(receiver,filter);registered=true;
            emit(VmHardware.object("event","availability","available",manager(context).isAvailable()));
        }
        public Object info()throws Exception{check();return HardwareRtt.info(context);}
        public synchronized void close()throws IOException{if(closed)return;super.close();if(registered){registered=false;app(context).unregisterReceiver(receiver);}}
    }
    static class Range extends VmHardware.Handle {
        final VmHardware.Context context;final RangingRequest request;final Map<PeerHandle,String> peerIds;String state="pending";
        final Runnable deadline=()->fail("timeout","Android did not deliver a ranging result within30 seconds.");
        Range(VmHardware.Context c,RangingRequest request){this(c,request,Collections.emptyMap());}
        Range(VmHardware.Context c,RangingRequest request,Map<PeerHandle,String> peerIds){super(c,"wifi","wifi_rtt_range","location");context=c;this.request=request;this.peerIds=new HashMap<>(peerIds);}
        void start()throws Exception{
            HardwareSensors.events().postDelayed(deadline,30000);
            manager(context).startRanging(request,task->HardwareSensors.events().post(task),new RangingResultCallback(){
                public void onRangingFailure(int code){fail(code==STATUS_CODE_FAIL_RTT_NOT_AVAILABLE?"unavailable":"ranging_failed","Android ranging request failed (reason "+code+").");}
                public void onRangingResults(List<RangingResult> results){complete(results);}
            });
        }
        synchronized void fail(String code,String message){if(closed||!state.equals("pending"))return;state="error";HardwareSensors.events().removeCallbacks(deadline);try{emit(VmHardware.object("event","error","code",code,"message",message));}catch(Exception ignored){}}
        synchronized void complete(List<RangingResult> results){
            if(closed||!state.equals("pending"))return;
            try{
                JSONArray rows=new JSONArray();int limit=Math.min(RangingRequest.getMaxPeers(),results.size());
                for(int i=0;i<limit;i++){
                    RangingResult r=results.get(i);JSONObject row=VmHardware.object("status",r.getStatus(),"bssid",r.getMacAddress()==null?JSONObject.NULL:r.getMacAddress().toString());
                    if(r.getPeerHandle()!=null){String id=peerIds.get(r.getPeerHandle());if(id==null)throw new VmHardware.Failure("invalid_response","Android returned a peer outside this ranging request.");row.put("peer",id);}
                    if(r.getStatus()==RangingResult.STATUS_SUCCESS){
                        row.put("distance_mm",r.getDistanceMm()).put("stddev_mm",r.getDistanceStdDevMm()).put("rssi_dbm",r.getRssi()).put("attempted",r.getNumAttemptedMeasurements()).put("successful",r.getNumSuccessfulMeasurements()).put("timestamp_ms",r.getRangingTimestampMillis());
                        if(Build.VERSION.SDK_INT>=35){byte[] lci=r.getLci(),lcr=r.getLcr();row.put("lci",VmHardware.bytes(Arrays.copyOf(lci,Math.min(lci.length,512)))).put("lcr",VmHardware.bytes(Arrays.copyOf(lcr,Math.min(lcr.length,512)))).put("location_report_truncated",lci.length>512||lcr.length>512);}
                    }
                    rows.put(row);
                }
                JSONObject event=VmHardware.object("event","ranging","results",rows,"reported_total",results.size(),"truncated",results.size()>rows.length());state="complete";HardwareSensors.events().removeCallbacks(deadline);emit(event);
            }catch(Exception error){fail("invalid_response",MainActivity.safe(error));}
        }
        public void access(VmHardware.Context c)throws Exception{check();permission(c);}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"close_cancels_radio",false);}
        public synchronized void close()throws IOException{if(closed)return;super.close();HardwareSensors.events().removeCallbacks(deadline);}
    }
    static void ready(VmHardware.Context c)throws Exception{
        WifiRttManager manager=manager(c);permission(c);
        if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Start Wi-Fi RTT while Collie is visible.");
        if(!manager.isAvailable())throw new VmHardware.Failure("unavailable","Android reports Wi-Fi RTT is temporarily unavailable.");
    }
    static void burst(RangingRequest.Builder builder,int burst)throws Exception{
        if(burst!=0){if(Build.VERSION.SDK_INT<31)throw new VmHardware.Failure("unsupported","Custom RTT burst sizes require Android12 or newer.");builder.setRttBurstSize(burst);}
    }
    static Object call(VmHardware.Context c,String op,JSONArray args)throws Exception{
        if(op.equals("wifi_rtt_info"))return info(c);
        if(op.equals("wifi_rtt_watch")){manager(c);Watch watch=new Watch(c);try{watch.start();return VmHardware.add(watch);}catch(Exception error){watch.close();throw error;}}
        if(op.equals("wifi_rtt_range")){
            HardwareWifi.Scan scan=VmHardware.handle(c,VmHardware.text(args,0,128),HardwareWifi.Scan.class);scan.access(c);
            JSONArray bssids=args.getJSONArray(1);int burst=VmHardware.integer(args,2,0,31);
            if(bssids.length()==0||bssids.length()>16)throw new VmHardware.Failure("invalid_argument","Select1..16 distinct BSSIDs from the scan snapshot.");
            List<ScanResult> targets=scan.rttTargets(bssids);ready(c);
            if(targets.size()>RangingRequest.getMaxPeers())throw new VmHardware.Failure("invalid_argument","The request exceeds Android's RTT peer limit.");
            RangingRequest.Builder builder=new RangingRequest.Builder();
            for(ScanResult target:targets){if(!target.is80211mcResponder()&&!(Build.VERSION.SDK_INT>=35&&target.is80211azNtbResponder()))throw new VmHardware.Failure("unsupported_peer","The selected access point does not advertise RTT responder support.");builder.addAccessPoint(target);}
            burst(builder,burst);
            Range range=new Range(c,builder.build());try{range.start();return VmHardware.add(range);}catch(Exception error){range.close();throw error;}
        }
        throw new VmHardware.Failure("unsupported_operation","Unknown Wi-Fi RTT operation.");
    }
}
