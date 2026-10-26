package org.flexscript.collie;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.location.*;
import android.os.*;
import java.io.IOException;
import org.json.*;

/** Location/GNSS callbacks are copied to bounded typed event streams. */
final class HardwareLocation {
    static LocationManager manager(VmHardware.Context c){return (LocationManager)c.host.getApplicationContext().getSystemService(Context.LOCATION_SERVICE);}
    static boolean supports(String op){return op.startsWith("location_")||op.startsWith("gnss_");}
    static boolean granted(VmHardware.Context c,boolean fine){return c.host.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED || (!fine && c.host.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)==PackageManager.PERMISSION_GRANTED);}
    static void permission(VmHardware.Context c,boolean fine)throws Exception{
        if(fine)VmHardware.require(c,Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION);
        else VmHardware.requireAny(c,Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION);
    }
    static Object location(Location l)throws Exception{
        if(l==null)return JSONObject.NULL;
        return VmHardware.object("provider",l.getProvider(),"latitude",VmHardware.real(l.getLatitude()),"longitude",VmHardware.real(l.getLongitude()),"time_ms",l.getTime(),"elapsed_realtime_ns",l.getElapsedRealtimeNanos(),"age_ms",Math.max(0,(SystemClock.elapsedRealtimeNanos()-l.getElapsedRealtimeNanos())/1000000),"accuracy_m",l.hasAccuracy()?VmHardware.real(l.getAccuracy()):JSONObject.NULL,"altitude_m",l.hasAltitude()?VmHardware.real(l.getAltitude()):JSONObject.NULL,"speed_m_s",l.hasSpeed()?VmHardware.real(l.getSpeed()):JSONObject.NULL,"bearing_degrees",l.hasBearing()?VmHardware.real(l.getBearing()):JSONObject.NULL);
    }
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{
        boolean gps=c.host.getPackageManager().hasSystemFeature(PackageManager.FEATURE_LOCATION_GPS),present=c.host.getPackageManager().hasSystemFeature(PackageManager.FEATURE_LOCATION);
        out.put(VmHardware.capability("location",present,present,"location"));out.put(VmHardware.capability("gnss",gps,gps,"location"));
    }
    static final class Updates extends VmHardware.Handle implements LocationListener {
        final LocationManager manager;final String provider;
        Updates(VmHardware.Context c,String provider,long period,float distance)throws Exception{
            super(c,"location","location");manager=manager(c);this.provider=provider;
            manager.requestLocationUpdates(provider,period,distance,this,HardwareSensors.events().getLooper());
        }
        public void onLocationChanged(Location l){try{emit(VmHardware.object("event","location","value",location(l)));}catch(Exception ignored){}}
        public void onStatusChanged(String provider,int status,Bundle extras){}
        public void onProviderEnabled(String provider){provider(true);}
        public void onProviderDisabled(String provider){provider(false);}
        private void provider(boolean enabled){try{emit(VmHardware.object("event","provider","provider",provider,"enabled",enabled));}catch(Exception ignored){}}
        void access(VmHardware.Context c)throws Exception{super.access(c);if(!granted(c,false)){close();throw new VmHardware.Failure("permission_revoked","Location permission was revoked. Reopen after granting access.");}}
        public synchronized void close()throws IOException{if(closed)return;super.close();manager.removeUpdates(this);}
    }
    static final class Gnss extends VmHardware.Handle {
        final LocationManager manager;GnssStatus.Callback status;GnssMeasurementsEvent.Callback measurements;GnssNavigationMessage.Callback navigation;OnNmeaMessageListener nmea;
        Gnss(VmHardware.Context c,String type)throws Exception{
            super(c,"location",type);manager=manager(c);boolean registered=false;
            if(type.equals("gnss_status")){
                status=new GnssStatus.Callback(){public void onStarted(){emit(object("event","started"));}public void onStopped(){emit(object("event","stopped"));}public void onFirstFix(int millis){emit(object("event","first_fix","milliseconds",millis));}public void onSatelliteStatusChanged(GnssStatus s){
                    try{JSONArray satellites=new JSONArray();int limit=Math.min(s.getSatelliteCount(),128);for(int i=0;i<limit;i++)satellites.put(VmHardware.object("svid",s.getSvid(i),"constellation",s.getConstellationType(i),"cn0_dbhz",VmHardware.real(s.getCn0DbHz(i)),"elevation_degrees",VmHardware.real(s.getElevationDegrees(i)),"azimuth_degrees",VmHardware.real(s.getAzimuthDegrees(i)),"used_in_fix",s.usedInFix(i)));emit(VmHardware.object("event","satellites","satellites",satellites,"total",s.getSatelliteCount(),"truncated",limit<s.getSatelliteCount()));}catch(Exception ignored){}
                }};registered=manager.registerGnssStatusCallback(status,HardwareSensors.events());
            }else if(type.equals("gnss_measurements")){
                measurements=new GnssMeasurementsEvent.Callback(){public void onGnssMeasurementsReceived(GnssMeasurementsEvent event){
                    try{GnssClock clock=event.getClock();JSONObject time=VmHardware.object("time_ns",clock.getTimeNanos(),"full_bias_ns",clock.hasFullBiasNanos()?clock.getFullBiasNanos():JSONObject.NULL,"bias_ns",clock.hasBiasNanos()?VmHardware.real(clock.getBiasNanos()):JSONObject.NULL,"drift_ns_s",clock.hasDriftNanosPerSecond()?VmHardware.real(clock.getDriftNanosPerSecond()):JSONObject.NULL,"discontinuities",clock.getHardwareClockDiscontinuityCount());JSONArray rows=new JSONArray();int count=0;for(GnssMeasurement m:event.getMeasurements()){if(count++>=32)continue;rows.put(VmHardware.object("svid",m.getSvid(),"constellation",m.getConstellationType(),"state",m.getState(),"received_sv_time_ns",m.getReceivedSvTimeNanos(),"received_sv_time_uncertainty_ns",m.getReceivedSvTimeUncertaintyNanos(),"time_offset_ns",VmHardware.real(m.getTimeOffsetNanos()),"cn0_dbhz",VmHardware.real(m.getCn0DbHz()),"pseudorange_rate_m_s",VmHardware.real(m.getPseudorangeRateMetersPerSecond()),"accumulated_delta_range_m",VmHardware.real(m.getAccumulatedDeltaRangeMeters()),"accumulated_delta_range_state",m.getAccumulatedDeltaRangeState(),"carrier_hz",m.hasCarrierFrequencyHz()?VmHardware.real(m.getCarrierFrequencyHz()):JSONObject.NULL));}emit(VmHardware.object("event","measurements","clock",time,"measurements",rows,"total",count,"truncated",count>32));}catch(Exception ignored){}
                }public void onStatusChanged(int value){emit(object("event","status","status",value));}};registered=manager.registerGnssMeasurementsCallback(measurements,HardwareSensors.events());
            }else if(type.equals("gnss_navigation")){
                navigation=new GnssNavigationMessage.Callback(){public void onGnssNavigationMessageReceived(GnssNavigationMessage m){try{emit(VmHardware.object("event","navigation","type",m.getType(),"svid",m.getSvid(),"message_id",m.getMessageId(),"submessage_id",m.getSubmessageId(),"status",m.getStatus(),"data",VmHardware.bytes(m.getData())));}catch(Exception ignored){}}public void onStatusChanged(int value){emit(object("event","status","status",value));}};registered=manager.registerGnssNavigationMessageCallback(navigation,HardwareSensors.events());
            }else if(type.equals("gnss_nmea")){
                nmea=(message,timestamp)->{if(message.length()<=4096)emit(object("event","nmea","timestamp_ms",timestamp,"message",message));};registered=manager.addNmeaListener(nmea,HardwareSensors.events());
            }
            if(!registered)throw new VmHardware.Failure("unsupported","Android cannot register this GNSS stream on the current device.");
        }
        void access(VmHardware.Context c)throws Exception{super.access(c);if(!granted(c,true)){close();throw new VmHardware.Failure("permission_revoked","Precise location permission was revoked. Reopen this GNSS stream after granting access.");}}
        public synchronized void close()throws IOException{if(closed)return;super.close();if(status!=null)manager.unregisterGnssStatusCallback(status);if(measurements!=null)manager.unregisterGnssMeasurementsCallback(measurements);if(navigation!=null)manager.unregisterGnssNavigationMessageCallback(navigation);if(nmea!=null)manager.removeNmeaListener(nmea);}
    }
    private static JSONObject object(Object... fields){try{return VmHardware.object(fields);}catch(Exception ignored){return new JSONObject();}}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        LocationManager manager=manager(c);
        if(op.equals("location_providers")){JSONArray out=new JSONArray();for(String provider:manager.getAllProviders())out.put(VmHardware.object("id",provider,"enabled",manager.isProviderEnabled(provider)));return out;}
        if(op.startsWith("gnss_")){permission(c,true);return VmHardware.add(new Gnss(c,op));}
        permission(c,false);String provider=VmHardware.text(a,0,80);if(!manager.getAllProviders().contains(provider))throw new VmHardware.Failure("unavailable","Unknown location provider.");
        if(op.equals("location_last"))return location(manager.getLastKnownLocation(provider));
        if(op.equals("location_watch"))return VmHardware.add(new Updates(c,provider,VmHardware.integer(a,1,100,3600000),VmHardware.integer(a,2,0,1000000)/1000.0f));
        throw new VmHardware.Failure("unsupported_operation","Unknown location operation.");
    }
}
