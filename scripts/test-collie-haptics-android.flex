// Native host driver: actual Android SDK/VM plus independent vibration-service probes.
// The parent restores the original conversation even if the test worker fails.
import "../apps/collie/lib/state.flex";
global ht_adb=0;
global ht_serial=0;
global ht_out=0;
global ht_prefix=0;
global ht_sha=0;
fn ht_args(a,b,c,d,e,f){let args=h_args(ht_adb,"-s",ht_serial,a,b,c);if d{h_add(args,d);}if e{h_add(args,e);}if f{h_add(args,f);}return args;}
fn ht_call(args,input){return h_wait(h_spawn(args,input,0));}
fn ht_ok(args,input){return h_check(ht_call(args,input),0,0);}
fn ht_read(path){let p=ht_call(ht_args("exec-out","run-as","org.flexscript.collie","cat",path,0),"");if h_status(p)!=0 || !h_starts(h_out(p),"{"){return 0;}return c_json(h_out(p));}
fn ht_write(path,text){let command=h_cat3("'umask 077; cat > ",path,"'");let args=ht_args("shell","run-as","org.flexscript.collie","sh","-c",command);ht_ok(args,text);return 0;}
fn ht_start(name,payload){ht_write(h_cat3("files/test/",name,".json"),j_dump(payload));let args=ht_args("shell","am","start","-n","org.flexscript.collie/.MainActivity",0);h_add(args,"--es");h_add(args,"test_case");h_add(args,name);ht_ok(args,"");return 0;}
fn ht_payload(session){let p=j_object();j_set(p,"session",j_string(session));j_set(p,"hardware_preserve_handles",j_bool(1));return p;}
fn ht_result(name,probes){
    let end=net_now()+180000;let last="";let previous="";
    while net_now()<end{
        let r=ht_read(h_cat3("files/test/",name,".result.json"));if r{return r;}
        if probes{
            let p=ht_read(h_cat3("files/workspaces/",ht_prefix,"/haptic-sdk-probe.json"));
            if p && !h_equal(last,cj_text(p,"id")){
                last=cj_text(p,"id");let state=cj_text(p,"state");let text="";let ok=0;let until=net_now()+1000;
                if h_equal(state,"foreground"){ht_ok(ht_args("shell","am","start","-n","org.flexscript.collie/.MainActivity",0),"");ok=1;}
                else{
                    while !ok && net_now()<until{
                        let dump=ht_ok(ht_args("shell","dumpsys","vibrator_manager",0,0,0),"");text=h_out(dump);let start=h_find(text,"CurrentVibration:");let next=-1;if start>=0{next=h_find(text+start,"NextVibration:");}let current="";if start>=0 && next>=0{current=h_slice(text+start,next);}
                        if h_equal(state,"idle"){ok=h_has(current,"null") && !h_has(current,"status = running") && (h_has(text,"currentState = IDLE") || h_has(text,"isVibrating = false"));}
                        else if h_equal(state,"running"){ok=h_has(current,"opPkg=org.flexscript.collie") && h_has(current,"status = running") && h_has(current,cj_text(p,"needle")) && (h_has(text,"currentState = VIBRATING") || h_has(text,"isVibrating = true"));}
                        else if h_equal(state,"composition"){ok=h_has(current,"opPkg=org.flexscript.collie") && h_has(current,"Primitive") && h_has(current,"status = running");}
                        else if h_equal(state,"envelope"){ok=h_has(current,"opPkg=org.flexscript.collie") && h_has(current,cj_text(p,"needle")) && h_has(current,"status = running") && (h_has(text,"currentState = VIBRATING") || h_has(text,"isVibrating = true"));}
                        else if h_equal(state,"targeted"){ok=h_has(current,"opPkg=org.flexscript.collie") && h_has(current,"status = running") && h_has(current,cj_text(p,"needle"));}
                        else if h_equal(state,"predefined"){
                            let id=cj_int(p,"duration");let name="CLICK";if id==1{name="DOUBLE_CLICK";}else if id==2{name="TICK";}else if id==5{name="HEAVY_CLICK";}else{h_assert(id==0,"Invalid SDK predefined-effect probe");}
                            ok=h_has(current,"opPkg=org.flexscript.collie") && h_has(current,"status = running") && h_has(current,h_cat3("Prebaked{effect=",name,","));
                            let marker=h_cat3("Prebaked=",name,"(");let at=0;while !ok && load8(text+at){let end=h_find(text+at,"\n");if end<0{end=h_len(text+at);}let line=h_slice(text+at,end);if h_has(line,"org.flexscript.collie") && h_has(line,marker) && h_has(line,"finished") && !h_has(previous,line){ok=1;}at=at+end;if load8(text+at){at=at+1;}}
                        }
                        if !ok{h_sleep(10);}
                    }
                    h_save(h_join(ht_out,h_cat3("haptic-sdk-probe-",last,".txt")),text);
                }
                h_assert(ok,h_cat3("Actual vibration service did not establish ",state,h_cat("; probe ",last)));
                ht_write(h_cat3("files/workspaces/",ht_prefix,"/haptic-sdk-probe.done"),last);previous=text;
            }
        }
        h_sleep(20);
    }
    h_die("Haptic fixture result deadline expired; parent will stop the owned app and restore its conversation");return 0;
}
fn ht_valid_name(name){let n=h_len(name);if n<1 || n>80{return 0;}let i=0;while i<n{let c=load8(name+i);if !((c>=48&&c<=57)||(c>=65&&c<=90)||(c>=97&&c<=122)||c==45||c==95){return 0;}i=i+1;}return 1;}
fn ht_worker(){
    let p=ht_payload(ht_prefix);let grants=j_object();j_set(grants,"haptics",j_bool(1));j_set(p,"initial_permissions",grants);j_set(p,"hardware_tests",j_bool(1));j_set(p,"hardware_haptic_tests",j_bool(1));let name=h_cat(ht_prefix,"-run");ht_start(name,p);let result=ht_result(name,1);h_assert(cj_int(result,"ok"),j_dump(result));let sdk=cj_get(result,"hardware");h_assert(cj_int(sdk,"ok"),j_dump(sdk));
    j_set(sdk,"apk_sha256",j_string(ht_sha));j_set(sdk,"serial",j_string(ht_serial));j_set(sdk,"sdk_service_probes_verified",j_bool(1));j_save(h_join(ht_out,"haptics-android-report.json"),sdk);let rows=cj_get(sdk,"checks");let i=0;while i<j_count(rows){h_print(1,h_cat3("PASS ",j_value(j_at(rows,i)),"\n"));i=i+1;}h_print(1,h_cat(h_int(j_count(rows))," actual Android haptic checks passed\n"));return 0;
}
fn main(argc,argv){
    h_environment(argc,argv);ht_adb="/opt/android-sdk/platform-tools/adb";h_timeout=45000;let worker=0;let i=1;
    while i<argc{let arg=load64(argv+i*8);if h_equal(arg,"--worker"){worker=1;}else{i=i+1;h_assert(i<argc,"Missing haptic test argument value");let value=load64(argv+i*8);if h_equal(arg,"--out"){ht_out=h_real(value);}else if h_equal(arg,"--serial"){ht_serial=value;}else if h_equal(arg,"--prefix"){ht_prefix=value;}else if h_equal(arg,"--sha"){ht_sha=value;}else{h_die(h_cat("Unknown haptic test argument: ",arg));}}i=i+1;}
    h_assert(ht_out && ht_serial && h_starts(ht_serial,"emulator-"),"Provide --out and an owned unlocked --serial emulator-N");let suffix=ht_serial+9;i=0;h_assert(h_len(suffix)>0,"Invalid emulator serial");while load8(suffix+i){h_assert(load8(suffix+i)>=48 && load8(suffix+i)<=57,"Invalid emulator serial");i=i+1;}
    if worker{h_assert(ht_prefix && ht_valid_name(ht_prefix) && ht_sha && h_len(ht_sha)==64,"Invalid private worker arguments");return ht_worker();}
    let apk=h_join(ht_out,"collie.apk");h_assert(h_exists(apk),"Missing collie.apk");let sha=ht_ok(h_args(h_executable("sha256sum"),apk,0,0,0,0),"");ht_sha=h_slice(h_out(sha),64);let path=ht_ok(ht_args("shell","pm","path","org.flexscript.collie",0,0),"");let installed=h_out(path);h_assert(h_starts(installed,"package:/data/app/"),"Missing installed Collie package");let length=h_find(installed,"\n");h_assert(length>8,"Invalid installed APK path");installed=h_slice(installed+8,length-8);let actual=ht_ok(ht_args("shell","sha256sum",installed,0,0,0),"");h_assert(h_bytes(h_out(actual),ht_sha,64),"Installed APK differs from the exact requested artifact");
    ht_ok(ht_args("shell","run-as","org.flexscript.collie","mkdir","-p","files/test"),"");let prefs=ht_ok(ht_args("exec-out","run-as","org.flexscript.collie","cat","shared_prefs/MainActivity.xml",0),"");let xml=h_out(prefs);let tag="name=\"session\">";let offset=h_find(xml,tag);h_assert(offset>=0,"No original conversation; open Collie first");offset=offset+h_len(tag);let end=h_find(xml+offset,"<");h_assert(end>0,"Invalid original session preference");let original=h_slice(xml+offset,end);h_assert(ht_valid_name(original),"Unsafe original session ID");let before=ht_read(h_cat3("files/workspaces/",original,"/session.json"));h_assert(before,"Original session is not readable; unlock the owned emulator");
    ht_prefix=h_cat3("haptic-hw-",h_int(syscall(39,0,0,0,0,0,0)),h_cat("-",h_int(net_now())));let recovery=j_object();j_set(recovery,"prefix",j_string(ht_prefix));j_set(recovery,"original",j_string(original));j_save(h_join(ht_out,"haptics-recovery.json"),recovery);
    let args=h_args(h_real(load64(argv)),"--worker","--out",ht_out,"--serial",ht_serial);h_add(args,"--prefix");h_add(args,ht_prefix);h_add(args,"--sha");h_add(args,ht_sha);let child=h_spawn(args,"",0);let deadline=net_now()+210000;let timed=0;while h_status(child)==-999 || load64(child+40)>=0 || load64(child+48)>=0{h_pump(child,10);if net_now()>=deadline{h_stop(child);timed=1;}}
    h_save(h_join(ht_out,"haptics-worker.stdout"),h_out(child));h_save(h_join(ht_out,"haptics-worker.stderr"),h_err(child));
    ht_ok(ht_args("shell","am","force-stop","org.flexscript.collie",0,0),"");let restore=ht_payload(original);j_set(restore,"resume_only",j_bool(1));let name=h_cat(ht_prefix,"-restore");ht_start(name,restore);let restored=ht_result(name,0);h_assert(cj_int(restored,"ok"),"Could not restore original conversation; preserve recovery file");let after=ht_read(h_cat3("files/workspaces/",original,"/session.json"));h_assert(after && h_equal(j_dump(cj_get(before,"messages")),j_dump(cj_get(after,"messages"))) && h_equal(j_dump(cj_get(before,"permissions")),j_dump(cj_get(after,"permissions"))),"Original messages/permissions changed; preserve owned workspace for recovery");
    ht_ok(ht_args("shell","run-as","org.flexscript.collie","rm","-rf",h_cat("files/workspaces/",ht_prefix)),"");let clean=ht_args("shell","run-as","org.flexscript.collie","rm","-f",0);h_add(clean,h_cat3("files/test/",ht_prefix,"-run.json"));h_add(clean,h_cat3("files/test/",ht_prefix,"-run.result.json"));h_add(clean,h_cat3("files/test/",ht_prefix,"-restore.json"));h_add(clean,h_cat3("files/test/",ht_prefix,"-restore.result.json"));ht_ok(clean,"");h_print(1,h_out(child));h_print(2,h_err(child));h_assert(!timed && h_status(child)==0,"Haptic worker failed; original conversation restored and owned workspace removed");
    let report=c_json(h_read(h_join(ht_out,"haptics-android-report.json")));j_set(report,"original_conversation_restored",j_bool(1));j_set(report,"owned_workspace_removed",j_bool(1));j_save(h_join(ht_out,"haptics-android-report.json"),report);h_print(1,"PASS original conversation/permissions restored and owned haptic workspace removed\n");return 0;
}
