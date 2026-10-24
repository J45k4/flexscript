package org.flexscript.collie;

import android.nfc.NfcAdapter;
import android.nfc.cardemulation.PollingFrame;
import android.os.Build;
import java.util.List;
import org.json.JSONObject;

/** Copies public SDK values only. Frame interpretation belongs to Flexscript. */
final class HardwareHcePolling {
    static final int MAX_BATCH=64;

    static JSONObject info(NfcAdapter adapter,boolean hce)throws Exception {
        boolean api=Build.VERSION.SDK_INT>=35, supported=api&&hce;
        JSONObject value=VmHardware.object("frames_api",api,"supported",supported,
            "observe_supported",supported?Api35.observeSupported(adapter):false,
            "observe_enabled",supported?Api35.observeEnabled(adapter):false,
            "maximum_frame_bytes",VmHardware.MAX_BYTES,"maximum_callback_frames",MAX_BATCH,
            "filter_registration_implemented",true,"observe_control_implemented",true,
            "maximum_filters",HardwareHceControls.MAX_FILTERS,"maximum_control_results",HardwareHceControls.MAX_RESULTS,
            "maximum_filter_text",HardwareHceControls.MAX_FILTER_TEXT);
        return value;
    }

    static void frames(HardwareHce.Session session,List<?> frames) {
        if(Build.VERSION.SDK_INT<35)return;
        synchronized(session) {
            if(!session.accepts()||session.mode==2)return;
            if(frames==null) {
                session.event("error","code","invalid_sdk_value","message","Android delivered a null polling-frame list.");
                return;
            }
            int total=frames.size(),count=Math.min(total,MAX_BATCH);
            String batch="hce-poll-"+java.util.UUID.randomUUID();
            for(int i=0;i<count;i++) {
                try {
                    JSONObject frame=Api35.frame(frames.get(i));
                    session.event("polling_frame","batch",batch,"index",i,"total",total,
                        "frame",frame,"sdk_callback",true);
                }catch(Exception error) {
                    session.event("error","code",error instanceof VmHardware.Failure?((VmHardware.Failure)error).code:"invalid_sdk_value",
                        "message",MainActivity.safe(error),"batch",batch,"index",i,"total",total);
                }
            }
            if(total>count)session.event("polling_batch_truncated","batch",batch,"total",total,
                "copied",count,"dropped_frames",total-count,"sdk_callback",true);
        }
    }

    // Keep newer SDK symbols behind the runtime gate for older Android devices.
    private static final class Api35 {
        static boolean observeSupported(NfcAdapter adapter){return adapter.isObserveModeSupported();}
        static boolean observeEnabled(NfcAdapter adapter){return adapter.isObserveModeEnabled();}
        static JSONObject frame(Object value)throws Exception {
            if(!(value instanceof PollingFrame))throw new VmHardware.Failure("invalid_sdk_value","Expected an Android PollingFrame.");
            PollingFrame frame=(PollingFrame)value;
            byte[] bytes=frame.getData();
            if(bytes==null)throw new VmHardware.Failure("invalid_sdk_value","Android delivered null polling-frame bytes.");
            if(bytes.length>VmHardware.MAX_BYTES)throw new VmHardware.Failure("size_limit","Polling-frame bytes exceed32KiB; the frame was not truncated.");
            return VmHardware.object("type",frame.getType(),"data",VmHardware.bytes(bytes),
                "timestamp_us",frame.getTimestamp(),"vendor_specific_gain",frame.getVendorSpecificGain(),
                "triggered_auto_transact",frame.getTriggeredAutoTransact());
        }
    }
}
