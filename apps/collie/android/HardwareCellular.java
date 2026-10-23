package org.flexscript.collie;

import android.Manifest;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.os.Build;
import android.telephony.*;
import java.io.IOException;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Read-only Android subscription/radio diagnostics. No raw modem commands. */
final class HardwareCellular {
    static boolean supports(String op){return op.startsWith("cellular_");}
    private static boolean feature(VmHardware.Context c,String name){return c.host.getPackageManager().hasSystemFeature(name);}
    private static TelephonyManager base(VmHardware.Context c)throws Exception{
        TelephonyManager manager=c.host.getSystemService(TelephonyManager.class);
        if(manager==null||!feature(c,Build.VERSION.SDK_INT>=33?PackageManager.FEATURE_TELEPHONY_RADIO_ACCESS:PackageManager.FEATURE_TELEPHONY))throw new VmHardware.Failure("unsupported","This device has no supported cellular radio service.");return manager;
    }
    private static SubscriptionManager subscriptions(VmHardware.Context c)throws Exception{
        SubscriptionManager manager=c.host.getSystemService(SubscriptionManager.class);
        if(manager==null||!feature(c,Build.VERSION.SDK_INT>=33?PackageManager.FEATURE_TELEPHONY_SUBSCRIPTION:PackageManager.FEATURE_TELEPHONY))throw new VmHardware.Failure("unsupported","This device has no subscription service.");return manager;
    }
    private static void require(VmHardware.Context c,String key,String... names)throws Exception{
        try{VmHardware.require(c,names);}catch(VmHardware.Consent consent){consent.request.put("key",key);throw consent;}
    }
    private static void phone(VmHardware.Context c)throws Exception{require(c,"cellular",Manifest.permission.READ_PHONE_STATE);}
    private static void location(VmHardware.Context c)throws Exception{
        require(c,"location",Manifest.permission.ACCESS_COARSE_LOCATION,Manifest.permission.ACCESS_FINE_LOCATION);
        LocationManager manager=c.host.getSystemService(LocationManager.class);
        boolean enabled=manager!=null&&(Build.VERSION.SDK_INT>=28?manager.isLocationEnabled():manager.isProviderEnabled(LocationManager.GPS_PROVIDER)||manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER));
        if(!enabled)throw new VmHardware.Failure("location_disabled","Turn on Android Location before requesting cellular service/cell information.");
    }
    private static int sub(JSONArray a,int index)throws Exception{int id=VmHardware.integer(a,index,-1,Integer.MAX_VALUE-1);return id==-1?SubscriptionManager.getDefaultSubscriptionId():id;}
    private static TelephonyManager manager(VmHardware.Context c,int id)throws Exception{
        TelephonyManager manager=base(c);phone(c);
        if(!SubscriptionManager.isValidSubscriptionId(id)||subscriptions(c).getActiveSubscriptionInfo(id)==null)throw new VmHardware.Failure("disconnected","The selected subscription is not active. Enumerate subscriptions again.");
        return manager.createForSubscriptionId(id);
    }
    private static Object text(CharSequence value){if(value==null)return JSONObject.NULL;String s=value.toString();return s.length()>256?s.substring(0,256):s;}
    private static Object number(int value){return value==Integer.MAX_VALUE?JSONObject.NULL:value;}
    private static Object number(long value){return value==Long.MAX_VALUE?JSONObject.NULL:value;}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{
        boolean radio=feature(c,Build.VERSION.SDK_INT>=33?PackageManager.FEATURE_TELEPHONY_RADIO_ACCESS:PackageManager.FEATURE_TELEPHONY),subs=feature(c,Build.VERSION.SDK_INT>=33?PackageManager.FEATURE_TELEPHONY_SUBSCRIPTION:PackageManager.FEATURE_TELEPHONY);
        out.put(VmHardware.capability("cellular_diagnostics",radio,radio&&c.host.getSystemService(TelephonyManager.class)!=null,"cellular"));
        out.put(VmHardware.capability("cellular_subscriptions",subs,subs&&c.host.getSystemService(SubscriptionManager.class)!=null,"cellular"));
        out.put(VmHardware.object("id","cellular_cells","implemented",true,"supported",radio,"available",radio,"permission","cellular","also","location"));
    }
    private static JSONObject subscription(SubscriptionInfo info)throws Exception{
        JSONObject row=VmHardware.object("id",info.getSubscriptionId(),"slot",info.getSimSlotIndex(),"display_name",text(info.getDisplayName()),"carrier_name",text(info.getCarrierName()),"country",text(info.getCountryIso()),"data_roaming",info.getDataRoaming());
        if(Build.VERSION.SDK_INT>=28){row.put("embedded",info.isEmbedded());}
        if(Build.VERSION.SDK_INT>=29){row.put("carrier_id",info.getCarrierId());row.put("mcc",text(info.getMccString()));row.put("mnc",text(info.getMncString()));row.put("opportunistic",info.isOpportunistic());}
        else{row.put("mcc",info.getMcc());row.put("mnc",info.getMnc());}return row;
    }
    private static Object subscriptionPage(VmHardware.Context c,int offset,int limit)throws Exception{
        SubscriptionManager manager=subscriptions(c);phone(c);List<SubscriptionInfo> list=manager.getActiveSubscriptionInfoList();if(list==null)list=Collections.emptyList();JSONArray out=new JSONArray();
        for(int i=offset;i<Math.min(list.size(),offset+limit);i++)out.put(subscription(list.get(i)));
        return VmHardware.object("subscriptions",out,"total",list.size(),"next",offset+out.length()<list.size()?offset+out.length():-1,"default",SubscriptionManager.getDefaultSubscriptionId(),"default_data",SubscriptionManager.getDefaultDataSubscriptionId(),"default_voice",SubscriptionManager.getDefaultVoiceSubscriptionId());
    }
    private static JSONObject strength(CellSignalStrength s,boolean sensitive)throws Exception{
        JSONObject row=VmHardware.object("type",s instanceof CellSignalStrengthLte?"lte":Build.VERSION.SDK_INT>=29&&s instanceof CellSignalStrengthNr?"nr":s instanceof CellSignalStrengthGsm?"gsm":s instanceof CellSignalStrengthWcdma?"wcdma":s instanceof CellSignalStrengthCdma?"cdma":Build.VERSION.SDK_INT>=29&&s instanceof CellSignalStrengthTdscdma?"tdscdma":"unknown","dbm",number(s.getDbm()),"level",s.getLevel(),"asu",number(s.getAsuLevel()));
        if(s instanceof CellSignalStrengthLte){CellSignalStrengthLte x=(CellSignalStrengthLte)s;row.put("rsrp",number(x.getRsrp()));row.put("rsrq",number(x.getRsrq()));row.put("rssnr",number(x.getRssnr()));row.put("cqi",number(x.getCqi()));if(sensitive)row.put("timing_advance",number(x.getTimingAdvance()));}
        if(Build.VERSION.SDK_INT>=29&&s instanceof CellSignalStrengthNr){CellSignalStrengthNr x=(CellSignalStrengthNr)s;row.put("ss_rsrp",number(x.getSsRsrp()));row.put("ss_rsrq",number(x.getSsRsrq()));row.put("ss_sinr",number(x.getSsSinr()));row.put("csi_rsrp",number(x.getCsiRsrp()));row.put("csi_rsrq",number(x.getCsiRsrq()));row.put("csi_sinr",number(x.getCsiSinr()));}
        if(s instanceof CellSignalStrengthCdma){CellSignalStrengthCdma x=(CellSignalStrengthCdma)s;row.put("cdma_dbm",number(x.getCdmaDbm()));row.put("cdma_ecio",number(x.getCdmaEcio()));row.put("evdo_dbm",number(x.getEvdoDbm()));row.put("evdo_ecio",number(x.getEvdoEcio()));row.put("evdo_snr",number(x.getEvdoSnr()));}
        return row;
    }
    private static Object signal(SignalStrength signal)throws Exception{
        if(signal==null)return JSONObject.NULL;JSONArray list=new JSONArray();if(Build.VERSION.SDK_INT>=29)for(CellSignalStrength item:signal.getCellSignalStrengths()){if(list.length()==16)break;list.put(strength(item,false));}
        return VmHardware.object("level",signal.getLevel(),"gsm",signal.isGsm(),"measurements",list);
    }
    private static Object service(ServiceState state)throws Exception{
        if(state==null)return JSONObject.NULL;
        // Explicit fields only. Never serialize ServiceState/registration objects,
        // whose toString/parcel representations may contain cell identities.
        return VmHardware.object("state",state.getState(),"roaming",state.getRoaming(),"operator",text(state.getOperatorNumeric()),"operator_name",text(state.getOperatorAlphaLong()),"operator_short",text(state.getOperatorAlphaShort()),"manual_selection",state.getIsManualSelection());
    }
    private static Object info(TelephonyManager tm,int id)throws Exception{
        return VmHardware.object("subscription",id,"sim_state",tm.getSimState(),"phone_type",tm.getPhoneType(),"operator",text(tm.getNetworkOperator()),"operator_name",text(tm.getNetworkOperatorName()),"country",text(tm.getNetworkCountryIso()),"roaming",tm.isNetworkRoaming(),"data_state",tm.getDataState(),"data_network_type",tm.getDataNetworkType(),"voice_network_type",tm.getVoiceNetworkType(),"signal",Build.VERSION.SDK_INT>=28?signal(tm.getSignalStrength()):JSONObject.NULL);
    }
    private static JSONObject cell(CellInfo cell)throws Exception{
        JSONObject identity=new JSONObject();CellSignalStrength strength;String type;
        if(cell instanceof CellInfoGsm){type="gsm";CellIdentityGsm x=((CellInfoGsm)cell).getCellIdentity();strength=((CellInfoGsm)cell).getCellSignalStrength();identity=VmHardware.object("cid",number(x.getCid()),"lac",number(x.getLac()),"arfcn",number(x.getArfcn()),"bsic",number(x.getBsic()),"mcc",number(x.getMcc()),"mnc",number(x.getMnc()));if(Build.VERSION.SDK_INT>=28){identity.put("mcc",text(x.getMccString()));identity.put("mnc",text(x.getMncString()));}}
        else if(cell instanceof CellInfoLte){type="lte";CellIdentityLte x=((CellInfoLte)cell).getCellIdentity();strength=((CellInfoLte)cell).getCellSignalStrength();identity=VmHardware.object("ci",number(x.getCi()),"pci",number(x.getPci()),"tac",number(x.getTac()),"earfcn",number(x.getEarfcn()),"mcc",number(x.getMcc()),"mnc",number(x.getMnc()));if(Build.VERSION.SDK_INT>=28){identity.put("bandwidth_khz",number(x.getBandwidth()));identity.put("mcc",text(x.getMccString()));identity.put("mnc",text(x.getMncString()));}}
        else if(cell instanceof CellInfoWcdma){type="wcdma";CellIdentityWcdma x=((CellInfoWcdma)cell).getCellIdentity();strength=((CellInfoWcdma)cell).getCellSignalStrength();identity=VmHardware.object("cid",number(x.getCid()),"lac",number(x.getLac()),"psc",number(x.getPsc()),"uarfcn",number(x.getUarfcn()),"mcc",number(x.getMcc()),"mnc",number(x.getMnc()));if(Build.VERSION.SDK_INT>=28){identity.put("mcc",text(x.getMccString()));identity.put("mnc",text(x.getMncString()));}}
        else if(cell instanceof CellInfoCdma){type="cdma";CellIdentityCdma x=((CellInfoCdma)cell).getCellIdentity();strength=((CellInfoCdma)cell).getCellSignalStrength();identity=VmHardware.object("base_station",number(x.getBasestationId()),"network",number(x.getNetworkId()),"system",number(x.getSystemId()),"latitude_quarter_seconds",number(x.getLatitude()),"longitude_quarter_seconds",number(x.getLongitude()));}
        else if(Build.VERSION.SDK_INT>=29&&cell instanceof CellInfoNr){type="nr";CellIdentityNr x=(CellIdentityNr)((CellInfoNr)cell).getCellIdentity();strength=((CellInfoNr)cell).getCellSignalStrength();identity=VmHardware.object("nci",number(x.getNci()),"pci",number(x.getPci()),"tac",number(x.getTac()),"nrarfcn",number(x.getNrarfcn()),"mcc",text(x.getMccString()),"mnc",text(x.getMncString()));}
        else if(Build.VERSION.SDK_INT>=29&&cell instanceof CellInfoTdscdma){type="tdscdma";CellIdentityTdscdma x=((CellInfoTdscdma)cell).getCellIdentity();strength=((CellInfoTdscdma)cell).getCellSignalStrength();identity=VmHardware.object("cid",number(x.getCid()),"lac",number(x.getLac()),"cpid",number(x.getCpid()),"uarfcn",number(x.getUarfcn()),"mcc",text(x.getMccString()),"mnc",text(x.getMncString()));}
        else return VmHardware.object("type","unknown","registered",cell.isRegistered(),"timestamp_ns",cell.getTimeStamp());
        JSONObject row=VmHardware.object("type",type,"registered",cell.isRegistered(),"timestamp_ns",cell.getTimeStamp(),"identity",identity,"signal",strength(strength,true));if(Build.VERSION.SDK_INT>=28)row.put("connection_status",cell.getCellConnectionStatus());return row;
    }
    static final class SubscriptionsWatch extends VmHardware.Handle {
        final VmHardware.Context context;final SubscriptionManager manager;SubscriptionManager.OnSubscriptionsChangedListener listener;
        SubscriptionsWatch(VmHardware.Context c)throws Exception{
            super(c,"cellular","cellular_subscriptions");context=c;manager=subscriptions(c);

        }
        void start()throws Exception{phone(context);onEvents(()->{synchronized(this){check();listener=new SubscriptionManager.OnSubscriptionsChangedListener(){public void onSubscriptionsChanged(){try{emit(VmHardware.object("event","subscriptions_changed","default",SubscriptionManager.getDefaultSubscriptionId()));}catch(Exception ignored){}}};if(Build.VERSION.SDK_INT>=30)manager.addOnSubscriptionsChangedListener(command->HardwareSensors.events().post(command),listener);else manager.addOnSubscriptionsChangedListener(listener);}});emit(VmHardware.object("event","ready"));}
        public void access(VmHardware.Context c)throws Exception{check();phone(c);}
        public synchronized void close()throws IOException{if(closed)return;super.close();if(listener!=null)manager.removeOnSubscriptionsChangedListener(listener);}
    }
    private interface Action {void run()throws Exception;}
    private static void onEvents(Action action)throws Exception{
        FutureTask<Void> task=new FutureTask<>(()->{action.run();return null;});HardwareSensors.events().post(task);try{task.get(2,TimeUnit.SECONDS);}catch(Exception error){task.cancel(false);throw error;}
    }
    static final class RadioWatch extends VmHardware.Handle {
        final VmHardware.Context context;final TelephonyManager manager;final int subscription;final boolean service;
        TelephonyCallback modern;PhoneStateListener legacy;
        RadioWatch(VmHardware.Context c,TelephonyManager tm,int id,boolean service)throws Exception{super(c,"cellular",service?"cellular_service":"cellular_radio",service?"location":"");context=c;manager=tm;subscription=id;this.service=service;}
        void event(String name,Object value){try{emit(VmHardware.object("event",name,"subscription",subscription,"value",value));}catch(Exception ignored){}}
        void start()throws Exception{
            if(Build.VERSION.SDK_INT>=31){modern=service?new ServiceCallbacks(this):new Callbacks(this);if(Build.VERSION.SDK_INT>=33)manager.registerTelephonyCallback(service?TelephonyManager.INCLUDE_LOCATION_DATA_FINE:TelephonyManager.INCLUDE_LOCATION_DATA_NONE,command->HardwareSensors.events().post(command),modern);else manager.registerTelephonyCallback(command->HardwareSensors.events().post(command),modern);}
            else onEvents(()->{synchronized(this){check();legacy=new PhoneStateListener(){public void onSignalStrengthsChanged(SignalStrength value){if(!service)try{event("signal",signal(value));}catch(Exception ignored){}}public void onServiceStateChanged(ServiceState value){if(service)try{event("service",HardwareCellular.service(value));}catch(Exception ignored){}}public void onDataConnectionStateChanged(int state,int network){if(!service)try{event("data",VmHardware.object("state",state,"network_type",network));}catch(Exception ignored){}}};manager.listen(legacy,service?PhoneStateListener.LISTEN_SERVICE_STATE:PhoneStateListener.LISTEN_SIGNAL_STRENGTHS|PhoneStateListener.LISTEN_DATA_CONNECTION_STATE);}});
        }
        public void access(VmHardware.Context c)throws Exception{check();manager(c,subscription);if(service)location(c);}
        public Object info()throws Exception{return VmHardware.object("kind",kind,"subscription",subscription,"queued_events",events.size());}
        public synchronized void close()throws IOException{if(closed)return;super.close();if(Build.VERSION.SDK_INT>=31&&modern!=null)manager.unregisterTelephonyCallback(modern);if(legacy!=null)manager.listen(legacy,PhoneStateListener.LISTEN_NONE);}
    }
    // Register only the listener interfaces actually needed by each watch.
    private static class Callbacks extends TelephonyCallback implements TelephonyCallback.SignalStrengthsListener,TelephonyCallback.DataConnectionStateListener {
        final RadioWatch owner;Callbacks(RadioWatch owner){this.owner=owner;}
        public void onSignalStrengthsChanged(SignalStrength value){try{owner.event("signal",signal(value));}catch(Exception ignored){}}
        public void onDataConnectionStateChanged(int state,int network){try{owner.event("data",VmHardware.object("state",state,"network_type",network));}catch(Exception ignored){}}
    }
    private static final class ServiceCallbacks extends TelephonyCallback implements TelephonyCallback.ServiceStateListener {
        final RadioWatch owner;ServiceCallbacks(RadioWatch owner){this.owner=owner;}
        public void onServiceStateChanged(ServiceState value){try{owner.event("service",service(value));}catch(Exception ignored){}}
    }
    static final class Cells extends VmHardware.Handle {
        final VmHardware.Context context;final int subscription;private List<CellInfo> cells=Collections.emptyList();private int reported;private String state="pending";private final Runnable deadline=()->fail(-2);
        Cells(VmHardware.Context c,int id){super(c,"cellular","cellular_cells","location");context=c;subscription=id;}
        synchronized void update(List<CellInfo> value,String source)throws Exception{if(closed||!state.equals("pending"))return;HardwareSensors.events().removeCallbacks(deadline);reported=value==null?0:value.size();cells=value==null?Collections.emptyList():new ArrayList<>(value.subList(0,Math.min(128,value.size())));state="ready";emit(VmHardware.object("event","cells","count",cells.size(),"reported_total",reported,"truncated",reported>cells.size(),"source",source));}
        synchronized void fail(int code){if(closed||!state.equals("pending"))return;HardwareSensors.events().removeCallbacks(deadline);state="error";try{emit(VmHardware.object("event","error","code","cell_update_failed","android_code",code));}catch(Exception ignored){}}
        public void access(VmHardware.Context c)throws Exception{check();manager(c,subscription);location(c);}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"subscription",subscription,"state",state,"total",cells.size(),"reported_total",reported,"truncated",reported>cells.size());}
        synchronized Object page(int offset,int limit)throws Exception{check();if(state.equals("pending"))throw new VmHardware.Failure("not_ready","Wait for the cellular update event before reading this snapshot.");if(state.equals("error"))throw new VmHardware.Failure("cell_update_failed","Android could not refresh cell information.");JSONArray out=new JSONArray();for(int i=offset;i<Math.min(cells.size(),offset+limit);i++)out.put(cell(cells.get(i)));return VmHardware.object("cells",out,"total",cells.size(),"reported_total",reported,"truncated",reported>cells.size(),"next",offset+out.length()<cells.size()?offset+out.length():-1);}
        void refreshing(){HardwareSensors.events().postDelayed(deadline,20000);}
        public synchronized void close()throws IOException{super.close();HardwareSensors.events().removeCallbacks(deadline);cells=Collections.emptyList();}
    }
    private static String publish(VmHardware.Handle handle,Action start)throws Exception{try{start.run();return VmHardware.add(handle);}catch(Exception error){try{handle.close();}catch(Exception ignored){}throw error;}}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        switch(op){
        case "cellular_subscriptions":{int offset=VmHardware.integer(a,0,0,1024),limit=VmHardware.integer(a,1,1,16);return subscriptionPage(c,offset,limit);}
        case "cellular_watch_subscriptions":{subscriptions(c);phone(c);SubscriptionsWatch watch=new SubscriptionsWatch(c);return publish(watch,watch::start);}
        case "cellular_cell_page":{String id=VmHardware.text(a,0,128);int offset=VmHardware.integer(a,1,0,128),limit=VmHardware.integer(a,2,1,8);Cells cells=VmHardware.handle(c,id,Cells.class);cells.access(c);return cells.page(offset,limit);}
        case "cellular_info":case "cellular_watch":case "cellular_service":case "cellular_watch_service":case "cellular_cells":{
            int id=sub(a,0),refresh=op.equals("cellular_cells")?VmHardware.integer(a,1,0,1):0;TelephonyManager tm=manager(c,id);
            boolean sensitive=op.equals("cellular_service")||op.equals("cellular_watch_service")||op.equals("cellular_cells");if(sensitive)location(c);
            if(op.equals("cellular_info"))return info(tm,id);
            if(op.equals("cellular_service"))return service(Build.VERSION.SDK_INT>=33?tm.getServiceState(TelephonyManager.INCLUDE_LOCATION_DATA_FINE):tm.getServiceState());
            if(op.equals("cellular_cells")){Cells cells=new Cells(c,id);return publish(cells,()->{if(refresh==1){if(Build.VERSION.SDK_INT<29)throw new VmHardware.Failure("unsupported","Explicit cell refresh needs Android 10 or newer; use cached mode 0.");cells.refreshing();tm.requestCellInfoUpdate(command->HardwareSensors.events().post(command),new TelephonyManager.CellInfoCallback(){public void onCellInfo(List<CellInfo> value){try{cells.update(value,"requested");}catch(Exception error){cells.fail(-1);}}public void onError(int code,Throwable detail){cells.fail(code);}});}else cells.update(tm.getAllCellInfo(),"cached");});}
            RadioWatch watch=new RadioWatch(c,tm,id,op.equals("cellular_watch_service"));return publish(watch,watch::start);
        }
        default:throw new VmHardware.Failure("unsupported_operation","Unknown cellular diagnostic operation.");
        }
    }
}
