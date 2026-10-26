// Optional live-model credentials stay in app-private storage. Tests never
// archive the login or put it in a guest workspace. The restoring parent owns
// recovery even if a worker fails. No implicit discovery of personal logins.
import "android-ui-test.flex";
fn al_path(){return h_cat3("files/credentials/",ut_prefix,"-auth.backup");}
fn al_copy(op,from,to){let args=ut_args("shell","run-as","org.flexscript.collie",op,"-p",from);if h_equal(op,"mv"){args=ut_args("shell","run-as","org.flexscript.collie",op,"-f",from);}h_add(args,to);return ut_ok(args,"");}
fn al_prepare(){
    let auth=cj_text(at_options,"auth");h_assert(h_len(auth)&&h_exists(auth),"Explicit --auth file required for live model I/O");
    ut_ok(ut_args("shell","run-as","org.flexscript.collie","mkdir","-p","files/credentials"),"");
    let p=ut_call(ut_args("shell","run-as","org.flexscript.collie","test","-e","files/credentials/auth.json"),"");let existed=h_status(p)==0;
    j_set(at_extra,"auth_existed",j_bool(existed));j_set(at_extra,"auth_prepared",j_bool(1));at_checkpoint_extra();
    // The backup is atomic and non-overwriting; it never leaves the app UID.
    if existed{al_copy("cp","files/credentials/auth.json",h_cat(al_path(),".tmp"));al_copy("mv",h_cat(al_path(),".tmp"),al_path());}
    j_set(at_extra,"auth_backed_up",j_bool(1));at_checkpoint_extra();
    let login=h_read(auth);h_assert(h_file_size==h_len(login)&&h_file_size>0,"Invalid explicit login file");at_write("files/credentials/auth.json",login);return 0;
}
fn al_cleanup(){
    if !cj_int(at_extra,"auth_prepared"){return 0;}
    if cj_int(at_extra,"auth_existed"){
        if cj_int(at_extra,"auth_backed_up"){al_copy("mv",al_path(),"files/credentials/auth.json");}
        else{let backup=ut_call(ut_args("shell","run-as","org.flexscript.collie","test","-e",al_path()),"");if h_status(backup)==0{al_copy("mv",al_path(),"files/credentials/auth.json");}}
    }else{ut_ok(ut_args("shell","run-as","org.flexscript.collie","rm","-f","files/credentials/auth.json"),"");}ut_ok(ut_args("shell","run-as","org.flexscript.collie","rm","-f",h_cat(al_path(),".tmp")),"");return 0;
}
