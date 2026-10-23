// Shared grant schema, conservative stored-policy normalization and UI metadata.
import "../lib/state.flex";
// Keep old boolean grants readable. New conversations ask only on first use.
fn cp_mode(saved,key){
    if !saved || j_kind(saved)==0{return "ask";}
    if j_kind(saved)!=4{return "deny";}let value=cj_get(saved,key);if !value && cp_hardware_key(key){return "ask";}
    if value && j_kind(value)==5{if j_value(value){return "allow";}return "deny";}
    if value && j_kind(value)==2 && h_equal(j_value(value),"ask"){return "ask";}
    return "deny";
}
fn cp_value(mode){if h_equal(mode,"ask"){return j_string("ask");}return j_bool(h_equal(mode,"allow"));}
fn cp_choice(key,binding){
    if h_equal(binding,h_cat("ask-",key)){return cp_value("ask");}
    if h_equal(binding,h_cat("allow-",key)){return cp_value("allow");}
    if h_equal(binding,h_cat("deny-",key)){return cp_value("deny");}return 0;
}
fn cp_hardware_key(key){return h_has(",network,wifi,bluetooth,usb,nfc,location,sensors,camera,microphone,audio,haptics,infrared,midi,device_status,biometrics,keystore,screen_capture,accessibility,uwb,secure_element,vpn,cellular,",h_cat3(",",key,","));}
fn cp_hardware_permissions(rows){
    cp_permission(rows,"network","Network connections","Inspect available networks and communicate using a selected Wi-Fi, Ethernet or cellular connection. Model traffic uses its own connection.");
    cp_permission(rows,"wifi","Wi-Fi devices","Discover and connect nearby Wi-Fi devices using supported Android Wi-Fi APIs.");
    cp_permission(rows,"bluetooth","Bluetooth devices","Discover, connect and exchange data with Bluetooth and BLE devices.");
    cp_permission(rows,"usb","USB devices","Inspect and communicate with USB peripherals. Android separately asks before opening a device.");
    cp_permission(rows,"nfc","NFC tags and emulation","Read and exchange commands with nearby NFC tags and use supported card emulation.");
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
    cp_permission(rows,"workers","Manage workers","Start helper agents and ask the model for feedback inside a running program. Workers share this workspace and inherit its permissions.");
    cp_hardware_permissions(rows);
    let policy=j_object();let i=0;while i<j_count(rows){let key=j_s(j_at(rows,i),"key");j_set(policy,key,cp_value(cp_mode(saved,key)));i=i+1;}
    let out=j_object();j_set(out,"policy",policy);j_set(out,"entries",rows);return out;
}
fn cp_entry(key){let entries=j_get(cp_permissions(0),"entries");let i=0;while i<j_count(entries){let entry=j_at(entries,i);if h_equal(j_s(entry,"key"),key){return entry;}i=i+1;}return 0;}
