package androidx.core.uwb.backend.fixture;

import android.app.Service;
import android.content.Intent;
import android.os.*;
import androidx.core.uwb.backend.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Separate-UID deterministic transport peer. Never opens a UWB radio or fabricates hardware proof. */
public final class UwbProtocolFixture extends Service {
    static final List<Client> CLIENTS=new ArrayList<>();static String mode="normal";static int binds,unbinds;
    static UwbAddress address(byte[] bytes){UwbAddress a=new UwbAddress();a.address=bytes.clone();return a;}
    static UwbDevice device(byte[] bytes){UwbDevice d=new UwbDevice();d.address=address(bytes);return d;}
    static Client client(int id){synchronized(CLIENTS){return CLIENTS.get(id-1);}}
    final IUwb root=new IUwb.Stub(){
        public int getInterfaceVersion(){return VERSION;}
        public IUwbClient getControllerClient(){return create(true);}
        public IUwbClient getControleeClient(){return create(false);}
        Client create(boolean controller){synchronized(CLIENTS){Client c=new Client(CLIENTS.size()+1,controller,mode);CLIENTS.add(c);return c;}}
    };
    public IBinder onBind(Intent intent){synchronized(CLIENTS){binds++;}return root.asBinder();}
    public boolean onUnbind(Intent intent){synchronized(CLIENTS){unbinds++;}return true;}
    static final class Client extends IUwbClient.Stub {
        final int id;final boolean controller;final String mode;final byte[] local;final CountDownLatch release=new CountDownLatch(1);
        IRangingSessionCallback callback;IUwbAvailabilityObserver observer;RangingParameters parameters;
        int addressCalls,starts,stops,adds,removes,intervals,notifications,subscribes,unsubscribes,skip,ntfMode,near,far;boolean startReturned,stopReturned;byte[] added,removed,subKey;int sub;
        Client(int id,boolean controller,String mode){this.id=id;this.controller=controller;this.mode=mode;local=new byte[]{0x12,(byte)id};}
        public int getInterfaceVersion(){return VERSION;}
        public boolean isAvailable(){return true;}
        public RangingCapabilities getRangingCapabilities(){RangingCapabilities c=new RangingCapabilities();c.supportsDistance=true;c.supportsAzimuthalAngle=true;c.supportsElevationAngle=true;c.minRangingInterval=100;c.supportedChannels=new int[]{5,9};c.supportedNtfConfigs=new int[]{0,1,2,3};c.supportedConfigIds=new int[]{1,2,3,4,5,6,7};c.supportedSlotDurations=new int[]{1,2};c.supportedRangingUpdateRates=new int[]{1,2,3};c.supportsRangingIntervalReconfigure=true;c.hasBackgroundRangingSupport=false;return c;}
        public UwbAddress getLocalAddress()throws RemoteException{synchronized(this){addressCalls++;}if(mode.equals("prepare_hold"))hold();return address(local);}
        public UwbComplexChannel getComplexChannel(){UwbComplexChannel c=new UwbComplexChannel();c.channel=9;c.preambleIndex=10;return c;}
        void hold()throws RemoteException{try{if(!release.await(25,TimeUnit.SECONDS))throw new RemoteException("Constructed provider hold elapsed");}catch(InterruptedException e){Thread.currentThread().interrupt();throw new RemoteException("Constructed hold interrupted");}}
        public void startRanging(RangingParameters p,IRangingSessionCallback cb)throws RemoteException{
            synchronized(this){starts++;parameters=p;callback=cb;}
            if(mode.equals("start_hold"))hold();
            if(mode.equals("reject"))cb.onRangingSuspended(device(local),IRangingSessionCallback.WRONG_PARAMETERS);
            else if(!mode.equals("delayed_init"))cb.onRangingInitialized(device(local));
            if(mode.equals("init_then_hold"))hold();synchronized(this){startReturned=true;}
        }
        public void stopRanging(IRangingSessionCallback cb)throws RemoteException{synchronized(this){stops++;}if(mode.equals("slow_stop"))hold();if(!mode.equals("silent_stop"))cb.onRangingSuspended(device(local),IRangingSessionCallback.STOP_RANGING_CALLED);synchronized(this){stopReturned=true;}}
        public synchronized void addControlee(UwbAddress a){adds++;added=a.address.clone();}
        public synchronized void addControleeWithSessionParams(RangingControleeParameters p){adds++;added=p.address.address.clone();sub=p.subSessionId;subKey=p.subSessionKey.clone();}
        public void removeControlee(UwbAddress a)throws RemoteException{IRangingSessionCallback cb;synchronized(this){removes++;removed=a.address.clone();cb=callback;}cb.onRangingSuspended(device(a.address),IRangingSessionCallback.STOPPED_BY_PEER);}
        public synchronized void reconfigureRangingInterval(int value){intervals++;skip=value;}
        public synchronized void reconfigureRangeDataNtf(int mode,int near,int far){notifications++;ntfMode=mode;this.near=near;this.far=far;}
        public void subscribeToAvailability(IUwbAvailabilityObserver o)throws RemoteException{synchronized(this){observer=o;subscribes++;}o.onUwbStateChanged(true,2);}
        public synchronized void unsubscribeFromAvailability(){unsubscribes++;observer=null;}
        void emit(String event)throws RemoteException{IRangingSessionCallback cb;RangingParameters p;synchronized(this){cb=callback;p=parameters;}if(cb==null)throw new IllegalStateException("No callback yet");
            if(event.equals("init")){cb.onRangingInitialized(device(local));return;}
            if(event.equals("terminal")){cb.onRangingSuspended(device(local),IRangingSessionCallback.STOP_RANGING_CALLED);return;}
            byte[] remote=p.peerDevices.get(0).address.address;if(event.equals("unknown"))remote=new byte[]{0x66,0x77};
            if(event.equals("peer_init")){cb.onRangingInitialized(device(remote));return;}
            RangingPosition position=new RangingPosition();position.elapsedRealtimeNanos=9007199254740993L;position.distance=new RangingMeasurement();position.distance.value=1.25f;position.distance.confidence=2;position.azimuth=new RangingMeasurement();position.azimuth.value=-0.0f;position.azimuth.confidence=1;position.elevation=new RangingMeasurement();position.elevation.value=-12.5f;position.elevation.confidence=0;cb.onRangingResult(device(remote),position);
        }
        synchronized JSONObject info()throws Exception{JSONObject j=new JSONObject().put("id",id).put("controller",controller).put("mode",mode).put("address_calls",addressCalls).put("starts",starts).put("stops",stops).put("adds",adds).put("removes",removes).put("intervals",intervals).put("skip",skip).put("notifications",notifications).put("notification_mode",ntfMode).put("near",near).put("far",far).put("subscribes",subscribes).put("unsubscribes",unsubscribes).put("start_returned",startReturned).put("stop_returned",stopReturned).put("calling_process_uid",android.os.Process.myUid()).put("added_address",added==null?JSONObject.NULL:Arrays.toString(added)).put("added_sub_session_id",Integer.toUnsignedLong(sub)).put("added_sub_key_bytes",subKey==null?0:subKey.length);
            if(parameters!=null){j.put("session_id",Integer.toUnsignedLong(parameters.sessionId)).put("sub_session_id",Integer.toUnsignedLong(parameters.subSessionId)).put("config_id",parameters.uwbConfigId).put("rate",parameters.rangingUpdateRate).put("slot",parameters.slotDuration).put("aoa_disabled",parameters.isAoaDisabled).put("peer_count",parameters.peerDevices.size()).put("key_bytes",parameters.sessionKeyInfo.length).put("channel",parameters.complexChannel.channel).put("preamble",parameters.complexChannel.preambleIndex).put("notification",parameters.uwbRangeDataNtfConfig.rangeDataNtfConfigType);}
            return j;
        }
    }
}
