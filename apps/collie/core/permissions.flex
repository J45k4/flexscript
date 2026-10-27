// Shared grant schema, conservative stored-policy normalization and UI metadata.
import "../lib/state.flex";
// Reviewer selection is independent of capability grants. Deny stays denied.
fn cp_reviewer(saved){if h_equal(cj_text(saved,"approval_reviewer"),"auto_review"){return "auto_review";}return "user";}
fn cp_profile(saved){if h_equal(cj_text(saved,"permission_profile"),"workspace"){return "workspace";}return "custom";}
fn cp_workspace_key(key){return h_has(",files_read,files_write,db_read,db_write,",h_cat3(",",key,","));}
fn cp_effective(saved,key,mode){
    if h_equal(cp_profile(saved),"workspace") && !h_equal(mode,"deny"){
        if cp_workspace_key(key){return "allow";}return "ask";
    }return mode;
}
// A feedback/image effect continues an already-reviewed VM operation. This
// ticket is produced only by the trusted capability broker, never by the guest.
fn cp_deferred_allowed(saved,key,signal){
    let mode=cp_mode(saved,key);if h_equal(mode,"allow"){return 1;}
    if !h_equal(mode,"ask") || !h_equal(cp_reviewer(saved),"auto_review"){return 0;}
    let keys=cj_get(signal,"reviewed_permissions");if !keys || j_kind(keys)!=3{return 0;}let i=0;while i<j_count(keys){if h_equal(j_value(j_at(keys,i)),key){return 1;}i=i+1;}return 0;
}
// Keep old boolean grants readable. New conversations ask only on first use.
fn cp_mode(saved,key){
    if !saved || j_kind(saved)==0{return "ask";}
    if j_kind(saved)!=4{return "deny";}let value=cj_get(saved,key);if !value && (cp_hardware_key(key) || h_equal(cp_profile(saved),"workspace")){return cp_effective(saved,key,"ask");}
    if value && j_kind(value)==5{if j_value(value){return cp_effective(saved,key,"allow");}return "deny";}
    if value && j_kind(value)==2 && h_equal(j_value(value),"ask"){return cp_effective(saved,key,"ask");}
    return "deny";
}
fn cp_value(mode){if h_equal(mode,"ask"){return j_string("ask");}return j_bool(h_equal(mode,"allow"));}
fn cp_choice(key,binding){
    if h_equal(key,"permission_profile"){
        if h_equal(binding,"profile-custom"){return j_string("custom");}
        if h_equal(binding,"profile-workspace"){return j_string("workspace");}return 0;
    }
    if h_equal(key,"approval_reviewer"){
        if h_equal(binding,"reviewer-user"){return j_string("user");}
        if h_equal(binding,"reviewer-auto"){return j_string("auto_review");}return 0;
    }
    if h_equal(binding,h_cat("ask-",key)){return cp_value("ask");}
    if h_equal(binding,h_cat("allow-",key)){return cp_value("allow");}
    if h_equal(binding,h_cat("deny-",key)){return cp_value("deny");}return 0;
}
fn cp_hardware_key(key){return h_has(",network,wifi,bluetooth,usb,nfc,input,location,sensors,camera,microphone,audio,haptics,infrared,midi,device_status,biometrics,keystore,screen_capture,accessibility,uwb,secure_element,vpn,cellular,documents,",h_cat3(",",key,","));}
fn cp_hardware_permissions(rows){
    cp_permission(rows,"network","Network connections","Inspect available networks and communicate using a selected Wi-Fi, Ethernet or cellular connection. Model traffic uses its own connection.");
    cp_permission(rows,"wifi","Wi-Fi devices","Discover and connect nearby Wi-Fi devices using supported Android Wi-Fi APIs.");
    cp_permission(rows,"bluetooth","Bluetooth devices","Discover, connect and exchange data with Bluetooth and BLE devices, or register as an input device for a paired host.");
    cp_permission(rows,"usb","USB devices","Inspect and communicate with USB peripherals. Android separately asks before opening a device.");
    cp_permission(rows,"nfc","NFC tags and emulation","Read and exchange commands with nearby NFC tags and use supported card emulation.");
    cp_permission(rows,"documents","Selected folders","Read and change documents inside folders you explicitly choose with Android. Read-only selections cannot be written. Folder approval is separate from this conversation permission.");
    cp_permission(rows,"input","Input devices and events","Inspect input devices and observe touch, stylus, keyboard, mouse and gamepad events delivered to Collie while it is visible.");
    cp_permission(rows,"location","Location and GNSS","Read location updates, satellite status and supported GNSS measurements.");
    cp_permission(rows,"sensors","Phone sensors","Read available motion, environment and activity sensor measurements.");
    cp_permission(rows,"camera","Camera and flashlight","Capture images or camera frames and control supported camera settings and the torch.");
    cp_permission(rows,"microphone","Microphone","Record audio through supported input devices.");
    cp_permission(rows,"audio","Audio playback","Play generated audio and use supported audio output devices.");
    cp_permission(rows,"haptics","Vibration","Play supported vibration effects and patterns.");
    cp_permission(rows,"infrared","Infrared transmitter","Send infrared remote-control patterns when an emitter is available.");
    cp_permission(rows,"midi","MIDI devices","Connect and exchange messages with MIDI devices.");
    cp_permission(rows,"device_status","Battery and thermal status","Read battery, charging and supported thermal measurements.");
    cp_permission(rows,"biometrics","Biometric authentication","Ask Android to authenticate you. Fingerprint and face templates remain with Android.");
    cp_permission(rows,"keystore","Hardware-backed keys","Create and use this conversation's Android Keystore keys.");
    cp_permission(rows,"screen_capture","Screen capture","Capture a screen or app after Android's separate session approval.");
    cp_permission(rows,"accessibility","Accessibility interaction","Use an explicitly enabled accessibility service to inspect exposed UI and perform actions.");
    cp_permission(rows,"uwb","Ultra-wideband ranging","Measure distance to compatible peers when UWB hardware is available.");
    cp_permission(rows,"secure_element","Secure-element applets","Communicate with applets permitted by the phone's secure-element access rules.");
    cp_permission(rows,"vpn","VPN routing","Read and route IP packets for selected apps using an Android-approved VPN interface. Android separately asks before allowing VPN access.");cp_permission(rows,"cellular","Cellular diagnostics","Read SIM subscription metadata, signal strength and service status. Cell identifiers additionally require Location access. Android separately asks for phone-state permission.");return 0;
}
fn cp_permission(keys,key,title,detail){let row=j_object();j_set(row,"key",j_string(key));j_set(row,"title",j_string(title));j_set(row,"detail",j_string(detail));j_push(keys,row);return 0;}
fn cp_permissions(saved){
    let rows=j_array();
    cp_permission(rows,"internet","Internet access","Fetch web pages and APIs over HTTPS. Your ChatGPT connection stays available when this is off.");
    cp_permission(rows,"files_read","Read workspace files","Read files, list folders, and view text or images in this conversation's private workspace.");
    cp_permission(rows,"files_write","Write workspace files","Create folders and create or replace workspace files.");
    cp_permission(rows,"db_read","Read database","Read tables, columns and saved rows in this conversation's FlexDB.");
    cp_permission(rows,"db_write","Write database","Create tables, change schemas, and add, update or delete saved rows.");
    cp_permission(rows,"history","Read past messages","Search and read saved conversations, previous programs and results. Conversations with this permission off are excluded from recall.");
    cp_permission(rows,"workers","Model tools and workers","Start helper agents, ask the model for feedback, and generate images inside a running program. Workers share this workspace and inherit its permissions.");
    cp_hardware_permissions(rows);
    let policy=j_object();let i=0;while i<j_count(rows){let key=j_s(j_at(rows,i),"key");j_set(policy,key,cp_value(cp_mode(saved,key)));i=i+1;}
    j_set(policy,"approval_reviewer",j_string(cp_reviewer(saved)));
    j_set(policy,"permission_profile",j_string(cp_profile(saved)));
    let out=j_object();j_set(out,"policy",policy);j_set(out,"entries",rows);return out;
}
fn cp_entry(key){let entries=j_get(cp_permissions(0),"entries");let i=0;while i<j_count(entries){let entry=j_at(entries,i);if h_equal(j_s(entry,"key"),key){return entry;}i=i+1;}return 0;}
// Canonical effective grants are persisted, so platform services see the same
// limits as the VM. Customizing one capability keeps all other current limits.
fn cp_update(saved,key,value){
    let old=j_get(cp_permissions(saved),"policy");let next=c_json(j_dump(old));
    if h_equal(key,"permission_profile"){
        if !value || j_kind(value)!=2 || !(h_equal(j_value(value),"custom") || h_equal(j_value(value),"workspace")){return c_error("Invalid permission profile.");}
    }else if h_equal(key,"approval_reviewer"){
        if !value || j_kind(value)!=2 || !(h_equal(j_value(value),"user") || h_equal(j_value(value),"auto_review")){return c_error("Invalid approval mode.");}
    }else{
        if !cp_entry(key) || !value || (j_kind(value)!=5 && !(j_kind(value)==2 && h_equal(j_value(value),"ask"))){return c_error("Invalid permission setting.");}
        j_set(next,"permission_profile",j_string("custom"));
    }
    j_set(next,key,value);let out=cp_permissions(next);let policy=j_get(out,"policy");let entries=j_get(out,"entries");let revoked=j_array();let i=0;
    while i<j_count(entries){let name=j_s(j_at(entries,i),"key");let before=cp_mode(old,name);let after=cp_mode(policy,name);if !h_equal(after,"allow") && !h_equal(before,after){j_push(revoked,j_string(name));}i=i+1;}j_set(out,"revoked",revoked);return out;
}
