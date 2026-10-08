import "lib/harness.flex";
import "lib/build.flex";
import "lib/signing.flex";
import "lib/tls-fixture.flex";
global tu_compiler=0;
global tu_payload=0;
global tu_wrong=0;
global tu_broken=0;
global tu_hanging=0;
global tu_key=0;
global tu_other_key=0;
global tu_version=0;
global tu_future=0;
global tu_name=0;
global tu_url=0;
global tu_server_dir=0;
global tu_dir=0;
global tu_install=0;
global tu_before=0;
fn tu_build(name,text) {
    let source=h_join(t_work,h_cat(name,".flex"));
    let binary=h_join(t_work,name);
    h_save(source,text);
    h_compile(t_compiler,source,binary);
    return binary;
}
fn tu_copy(from,to,mode) {
    let p=h_read(from);
    h_save_bytes(to,p,h_file_size,mode);
    h_assert(syscall(90,to,mode,0,0,0,0)==0,"fixture chmod");
    return 0;
}
fn tu_stat(path) {
    let p=h_take(144);
    h_assert(syscall(4,path,p,0,0,0,0)==0,"fixture stat failed");
    return p;
}
fn tu_sign(manifest,version,target,key) {
    let message=sg_message(version,target,manifest);
    return sg_sign_message(key,message,h_len(message));
}
fn tu_metadata(tag) {
    return h_cat3("{\"tag_name\":\"",tag,"\",\"draft\":false,\"prerelease\":false,\"assets\":[{\"tag_name\":\"ignore nested fields\"}],\"body\":\"Unicode ✓ and \\\"escapes\\\"\",\"number\":-1.25e3}");
}
fn tu_setting(key,value) {
    let o=j_object();
    j_set(o,key,j_string(value));
    return o;
}
fn tu_fixture(name,settings) {
    tu_dir=h_join(t_work,name);
    h_mkdir(tu_dir);
    tu_install=h_join(tu_dir,"flex");
    tu_copy(tu_compiler,tu_install,489);
    tu_before=tu_stat(tu_install);
    let metadata=tu_metadata(tu_future);
    let node=j_get(settings,"metadata");
    if node {
        metadata=j_value(node);
    }
    h_save(h_join(tu_dir,"metadata"),metadata);
    let binary=tu_payload;
    node=j_get(settings,"binary");
    if node {
        binary=j_value(node);
    }
    tu_copy(binary,h_join(tu_dir,"binary"),384);
    let manifest=h_cat3(h_sha(binary),"  ",h_cat(tu_name,"\n"));
    node=j_get(settings,"manifest");
    if node {
        manifest=j_value(node);
    }
    h_save(h_join(tu_dir,"manifest"),manifest);
    let signature=0;
    let size=64;
    node=j_get(settings,"signature");
    if node {
        signature=j_value(node);
        size=j_n(settings,"signature_size");
    }else {
        let version=tu_future;
        node=j_get(settings,"sign_version");
        if node {
            version=j_value(node);
        }
        let key=tu_key;
        node=j_get(settings,"sign_key");
        if node {
            key=j_value(node);
        }
        signature=tu_sign(manifest,version,"linux-x86_64",key);
    }
    h_save_bytes(h_join(tu_dir,"signature"),signature,size,384);
    tu_copy(tu_wrong,h_join(tu_dir,"replacement"),384);
    let control=j_object();
    node=j_get(settings,"control");
    if node {
        control=node;
    }
    j_set(control,"target",j_string(tu_install));
    j_save(h_join(tu_dir,"control"),control);
    h_save(h_join(tu_server_dir,"current"),tu_dir);
    return 0;
}
fn tu_no_staging(dir) {
    let names=h_entries(dir);
    let i=0;
    while i<h_count(names) {
        h_assert(!h_starts(h_at(names,i),"flex.upgrade."),"upgrade staging directory leaked");
        i=i+1;
    }
    return 0;
}
fn tu_unchanged() {
    h_assert(h_equal(h_sha(tu_install),h_sha(tu_compiler)),"installation changed on rejection");
    let after=tu_stat(tu_install);
    h_assert(load64(after+8)==load64(tu_before+8) && load64(after+24)==load64(tu_before+24) && load64(after+32)==load64(tu_before+32),"installation metadata changed on rejection");
    tu_no_staging(tu_dir);
    return 0;
}
fn tu_requests(count) {
    let text=h_cat(tu_url,"/releases/latest\n");
    if count>=2 {
        text=h_cat(text,h_cat3(tu_url,"/download/",h_cat3(tu_future,"/SHA256SUMS", "\n")));
    }
    if count>=3 {
        text=h_cat(text,h_cat3(tu_url,"/download/",h_cat(tu_future,"/SHA256SUMS.sig\n")));
    }
    if count>=4 {
        text=h_cat(text,h_cat3(tu_url,"/download/",h_cat3(tu_future,"/",h_cat(tu_name,"\n"))));
    }
    h_assert(h_equal(h_read(h_join(tu_dir,"requests")),text),"unexpected release request sequence");
    return 0;
}
fn tu_reject(name,message,settings) {
    tu_fixture(name,settings);
    let p=h_run(h_args(tu_install,"upgrade",0,0,0,0));
    h_check(p,1,0);
    h_assert(h_has(h_err(p),message),h_err(p));
    tu_unchanged();
    t_checks=t_checks+1;
    return 0;
}
fn tu_control(key,value) {
    let settings=j_object();
    let control=j_object();
    j_set(control,key,j_string(value));
    j_set(settings,"control",control);
    return settings;
}
fn tu_signed(signature,n) {
    let settings=j_object();
    j_set(settings,"signature",j_int(signature));
    j_set(settings,"signature_size",j_int(n));
    return settings;
}
fn tu_success() {
    h_check(h_run(h_args(tu_install,"upgrade",0,0,0,0)),0,0);
    h_assert(h_equal(h_sha(tu_install),h_sha(tu_payload)),"successful upgrade binary differs");
    let after=tu_stat(tu_install);
    h_assert(load64(after+24)==load64(tu_before+24) && load64(after+32)==load64(tu_before+32),"upgrade lost mode or ownership");
    tu_no_staging(tu_dir);
    t_checks=t_checks+1;
    return 0;
}
fn tu_ready(p) {
    let end=net_now()+5000;
    while !h_exists(h_join(tu_dir,"ready")) {
        h_pump(p,5);
        h_assert(h_status(p)==-999,h_err(p));
        h_assert(net_now()<end,"HTTPS fixture did not start");
    }
    return 0;
}
fn suite(compiler) {
    t_init(compiler);
    tu_version=b_version();
    let split=h_len(tu_version)-1;
    while split>=0 && load8(tu_version+split)!=46 {
        split=split-1;
    }
    tu_future=h_cat(h_slice(tu_version,split+1),h_int(h_number(tu_version+split+1)+1));
    tu_name=h_cat3("flexscript-",tu_future,"-linux-x86_64");
    let private=h_join(t_work,"private.pem");
    let other=h_join(t_work,"other.pem");
    h_ok(h_args("openssl","genpkey","-algorithm","ED25519","-out",private));
    h_ok(h_args("openssl","genpkey","-algorithm","ED25519","-out",other));
    tu_key=sg_key(h_read(private),1);
    tu_other_key=sg_key(h_read(other),1);
    let public=sg_public(tu_key);
    tu_server_dir=h_join(t_work,"server");
    h_mkdir(tu_server_dir);
    let server=sf_start(tu_server_dir,2);
    tu_url=sf_url;
    let environment=h_env;
    h_setenv("SSL_CERT_FILE",h_join(tu_server_dir,"localhost.pem"));
    let source=b_flatten(0);
    let original_key_prefix="fn release_public_key() { return \"";
    let at=h_find(source,original_key_prefix);
    h_assert(at>=0,"fixture trust anchor missing");
    let from=h_slice(source+at+h_len(original_key_prefix),64);
    source=h_replace(source,from,h_hex(public,32));
    source=h_replace(source,"https://api.github.com/repos/J45k4/flexscript/releases/latest",h_cat(tu_url,"/releases/latest"));
    source=h_replace(source,"https://github.com/J45k4/flexscript/releases/download/",h_cat(tu_url,"/download/"));
    tu_compiler=tu_build("test-compiler",source);
    tu_payload=tu_build("future",h_replace(source,h_cat3("fn compiler_version() { return \"",tu_version,"\"; }"),h_cat3("fn compiler_version() { return \"",tu_future,"\"; }")));
    h_check(h_run(h_args(tu_payload,"--version",0,0,0,0)),0,h_cat3("flexscript ",tu_future,"\n"));
    tu_wrong=tu_build("wrong","fn main(){return 0;}");
    tu_broken=tu_build("broken","fn main(){return 7;}");
    tu_hanging=tu_build("hanging","fn main(){syscall(7,0,0,60000,0,0,0);return 0;}");
    tu_fixture("success",j_object());
    tu_success();
    tu_requests(4);
    h_check(h_run(h_args(tu_install,"--version",0,0,0,0)),0,h_cat3("flexscript ",tu_future,"\n"));
    h_save(h_join(tu_dir,"module.flex"),"fn hello(){return 42;}");
    h_save(h_join(tu_dir,"program.flex"),"import \"module.flex\";fn main(){return hello();}");
    let binary=h_join(tu_dir,"program");
    h_compile(tu_install,h_join(tu_dir,"program.flex"),binary);
    h_check(h_run(h_args(binary,0,0,0,0,0)),42,0);
    tu_fixture("symlink",j_object());
    let launcher=h_join(tu_dir,"launcher");
    h_assert(syscall(88,"flex",launcher,0,0,0,0)==0,"launcher symlink");
    h_check(h_run(h_args(launcher,"upgrade",0,0,0,0)),0,0);
    let link=h_take(32);
    let n=syscall(89,launcher,link,32,0,0,0);
    h_assert(n==4 && h_bytes(link,"flex",4),"launcher symlink replaced");
    h_assert(h_equal(h_sha(tu_install),h_sha(tu_payload)),"symlink upgrade failed");
    tu_no_staging(tu_dir);
    t_checks=t_checks+1;
    let names=h_args("check","equal","older",0,0,0);
    let expected=h_args("Upgrade available:","Already up to date","newer than the latest",0,0,0);
    let i=0;
    while i<3 {
        let settings=j_object();
        if i==1 {
            j_set(settings,"metadata",j_string(tu_metadata(tu_version)));
        }else if i==2 {
            j_set(settings,"metadata",j_string("{\"tag_name\":\"0.0.0\"}"));
        }
        tu_fixture(h_at(names,i),settings);
        let args=h_args(tu_install,"upgrade",0,0,0,0);
        if i==0 {
            h_add(args,"--check");
        }
        let p=h_check(h_run(args),0,0);
        h_assert(h_has(h_out(p),h_at(expected,i)),h_out(p));
        tu_unchanged();
        tu_requests(1);
        t_checks=t_checks+1;
        i=i+1;
    }
    let bad=j_parse(h_read("tests/tooling/upgrade-metadata.json"));
    i=0;
    while i<j_count(bad) {
        tu_reject(h_cat("json-",h_int(i)),"Invalid latest-release metadata",tu_setting("metadata",j_value(j_at(bad,i))));
        i=i+1;
    }
    let tags=h_args("","../0.0.3","v0.0.3","0.0.3-beta","0.0","0.0.3.1");
    h_add(tags,"00.0.3");
    h_add(tags,"0.0.03");
    h_add(tags,"0.0.-1");
    h_add(tags,"0.0.1000000000");
    h_add(tags,"0.0.3\\u0000");
    i=0;
    while i<h_count(tags) {
        tu_reject(h_cat("tag-",h_int(i)),"numeric major.minor.patch",tu_setting("metadata",h_cat3("{\"tag_name\":\"",h_at(tags,i),"\"}")));
        i=i+1;
    }
    tu_reject("metadata-limit","size limit",tu_setting("metadata",h_repeat(" ",65537)));
    tu_reject("manifest-limit","size limit",tu_setting("manifest",h_repeat(" ",65537)));
    names=h_args("metadata","manifest","signature","binary",0,0);
    i=0;
    while i<4 {
        tu_reject(h_cat("https-fail-",h_at(names,i)),"command failed",tu_control("fail",h_at(names,i)));
        i=i+1;
    }
    let manifest=h_cat3(h_sha(tu_payload),"  ",h_cat(tu_name,"\n"));
    let good=tu_sign(manifest,tu_future,"linux-x86_64",tu_key);
    tu_reject("missing-signature","command failed",tu_control("fail","signature"));
    tu_requests(3);
    tu_reject("empty-signature","signature verification failed",tu_signed(good,0));
    tu_requests(3);
    tu_reject("short-signature","signature verification failed",tu_signed(good,63));
    tu_requests(3);
    let changed=h_take(65);
    h_copy(changed,good,64);
    store8(changed+64,0);
    tu_reject("long-signature","size limit",tu_signed(changed,65));
    tu_requests(3);
    let settings=j_object();
    j_set(settings,"sign_key",j_int(tu_other_key));
    tu_reject("wrong-key","signature verification failed",settings);
    tu_requests(3);
    tu_reject("version-replay","signature verification failed",tu_setting("sign_version",tu_version));
    tu_requests(3);
    h_copy(changed,good,64);
    store8(changed,load8(changed)^1);
    tu_reject("damaged-signature","signature verification failed",tu_signed(changed,64));
    tu_requests(3);
    settings=tu_signed(good,64);
    j_set(settings,"binary",j_string(tu_wrong));
    j_set(settings,"manifest",j_string(h_cat3(h_sha(tu_wrong),"  ",h_cat(tu_name,"\n"))));
    tu_reject("replaced-manifest","signature verification failed",settings);
    tu_requests(3);
    let upper=h_slice(manifest,h_len(manifest));
    i=0;
    while i<64 {
        let c=load8(upper+i);
        if c>=97 && c<=102 {
            store8(upper+i,c-32);
        }
        i=i+1;
    }
    settings=tu_signed(good,64);
    j_set(settings,"manifest",j_string(upper));
    tu_reject("changed-manifest-byte","signature verification failed",settings);
    tu_requests(3);
    tu_reject("wrong-target","signature verification failed",tu_signed(tu_sign(manifest,tu_future,"linux-aarch64",tu_key),64));
    tu_requests(3);
    tu_fixture("signature-no-tools",j_object());
    h_setenv("PATH","/no/executables");
    tu_success();
    h_env=environment;
    h_setenv("SSL_CERT_FILE",h_join(tu_server_dir,"localhost.pem"));
    let manifests=h_args("",h_cat(h_repeat("0",64),"  other-file\n"),h_cat3(h_repeat("z",64),"  ",h_cat(tu_name,"\n")),h_cat3(h_repeat("0",64)," ",h_cat(tu_name,"\n")),h_repeat(h_cat3(h_repeat("0",64),"  ",h_cat(tu_name,"\n")),2),"malformed\n");
    i=0;
    while i<6 {
        tu_reject(h_cat("manifest-",h_int(i)),"checksums do not uniquely",tu_setting("manifest",h_at(manifests,i)));
        i=i+1;
    }
    tu_reject("checksum","SHA-256 checksum mismatch",tu_setting("manifest",h_cat3(h_repeat("0",64),"  ",h_cat(tu_name,"\n"))));
    let text=h_join(t_work,"artifact-text");
    h_save(text,"not ELF");
    tu_reject("text","not a native Linux",tu_setting("binary",text));
    let data=h_read(tu_payload);
    let size=h_file_size;
    let truncated=h_join(t_work,"artifact-truncated");
    h_save_bytes(truncated,data,size-1,384);
    tu_reject("truncated","not a native Linux",tu_setting("binary",truncated));
    store8(data+18,3);
    store8(data+19,0);
    let arch=h_join(t_work,"artifact-architecture");
    h_save_bytes(arch,data,size,384);
    tu_reject("architecture","not a native Linux",tu_setting("binary",arch));
    tu_reject("version-mismatch","version does not match",tu_setting("binary",tu_wrong));
    tu_reject("probe-failed","command failed",tu_setting("binary",tu_broken));
    tu_fixture("uppercase",tu_setting("manifest",h_cat3(h_slice(upper,64)," *",h_cat(tu_name,"\r\n"))));
    tu_success();
    tu_fixture("no-newline",tu_setting("manifest",h_slice(manifest,h_len(manifest)-1)));
    tu_success();
    tu_fixture("no-curl",j_object());
    let env=h_env;
    h_setenv("PATH",tu_dir);
    let p=h_check(h_run(h_args(tu_install,"upgrade","--check",0,0,0)),0,0);
    h_assert(h_has(h_out(p),"Upgrade available:"),h_out(p));
    tu_unchanged();
    t_checks=t_checks+1;
    p=h_check(h_run(h_args(tu_install,"upgrade","--unknown",0,0,0)),1,0);
    h_assert(h_has(h_err(p),"Usage: flex upgrade"),h_err(p));
    tu_unchanged();
    t_checks=t_checks+1;
    h_env=env;
    tu_fixture("changed-target",tu_control("replace","yes"));
    p=h_check(h_run(h_args(tu_install,"upgrade",0,0,0,0)),1,0);
    h_assert(h_has(h_err(p),"changed during upgrade"),h_err(p));
    h_assert(h_equal(h_sha(tu_install),h_sha(tu_wrong)),"fixture did not replace target");
    tu_no_staging(tu_dir);
    t_checks=t_checks+1;
    tu_fixture("collision",tu_control("collision","yes"));
    p=h_spawn(h_args(tu_install,"upgrade",0,0,0,0),"",0);
    h_save(h_join(tu_dir,"parent-pid"),h_int(load64(p)));
    h_check(h_wait(p),1,0);
    h_assert(h_has(h_err(p),"Cannot create staging directory"),h_err(p));
    h_assert(h_equal(h_sha(tu_install),h_sha(tu_compiler)),"collision changed target");
    let collision=h_cat3(tu_install,".upgrade.",h_int(load64(p)));
    h_assert(h_equal(h_read(h_join(collision,"sentinel")),"keep me"),"collision sentinel changed");
    t_checks=t_checks+1;
    tu_fixture("concurrent",tu_control("hold","binary"));
    p=h_spawn(h_args(tu_install,"upgrade",0,0,0,0),"",0);
    tu_ready(p);
    let second=h_check(h_run(h_args(tu_install,"upgrade",0,0,0,0)),1,0);
    h_assert(h_has(h_err(second),"Another upgrade"),h_err(second));
    h_save(h_join(tu_dir,"continue"),"");
    h_check(h_wait(p),0,0);
    h_assert(h_equal(h_sha(tu_install),h_sha(tu_payload)),"concurrent upgrade failed");
    tu_no_staging(tu_dir);
    t_checks=t_checks+1;
    i=0;
    while i<2 {
        let signal=2;
        if i {
            signal=15;
        }
        tu_fixture(h_cat("signal-",h_int(signal)),tu_control("hold","binary"));
        p=h_spawn(h_args(tu_install,"upgrade",0,0,0,0),"",0);
        tu_ready(p);
        syscall(62,load64(p),signal,0,0,0,0);
        h_check(h_wait(p),128+signal,0);
        h_assert(h_has(h_err(p),"interrupted"),h_err(p));
        tu_unchanged();
        h_save(h_join(tu_dir,"continue"),"");
        t_checks=t_checks+1;
        i=i+1;
    }
    tu_fixture("probe-interrupt",tu_setting("binary",tu_hanging));
    p=h_spawn(h_args(tu_install,"upgrade",0,0,0,0),"",0);
    let stage=h_cat3(tu_install,".upgrade.",h_int(load64(p)));
    let end=net_now()+5000;
    while !h_exists(h_join(stage,"compiler")) {
        h_pump(p,5);
        h_assert(h_status(p)==-999 && net_now()<end,"probe did not start");
    }
    syscall(62,load64(p),15,0,0,0,0);
    h_check(h_wait(p),143,0);
    tu_unchanged();
    t_checks=t_checks+1;
    if syscall(107,0,0,0,0,0,0)!=0 {
        tu_fixture("permissions",j_object());
        let parent=h_join(tu_dir,"installation");
        h_mkdir(parent);
        let relocated=h_join(parent,"flex");
        syscall(82,tu_install,relocated,0,0,0,0);
        let control=j_object();
        j_set(control,"target",j_string(relocated));
        j_save(h_join(tu_dir,"control"),control);
        syscall(90,parent,365,0,0,0,0);
        h_check(h_run(h_args(relocated,"upgrade","--check",0,0,0)),0,0);
        p=h_check(h_run(h_args(relocated,"upgrade",0,0,0,0)),1,0);
        h_assert(h_has(h_err(p),"installation permissions"),h_err(p));
        h_assert(h_equal(h_sha(relocated),h_sha(tu_compiler)),"permissions changed target");
        tu_no_staging(parent);
        syscall(90,parent,493,0,0,0,0);
        t_checks=t_checks+1;
    }
    let harness=tu_build("sha-harness",h_cat(h_replace(b_flatten(0),"fn main(argc, argv)","fn original_main(argc, argv)"),"\nfn main(argc,argv){if !up_init(){return 1;}let fd=syscall(2,load64(argv+8),0,0,0,0,0);if fd<0{return 2;}let data=alloc(1048576);let n=0;let more=1;while more {let got=syscall(0,fd,data+n,1048576-n,0,0,0);if got<0{return 3;}if !got {more=0;}else {n=n+got;}}print(1,up_sha256(data,n));return 0;}"));
    let sizes=h_args("1","55","56","63","64","65");
    h_add(sizes,"119");
    h_add(sizes,"120");
    h_add(sizes,"127");
    h_add(sizes,"128");
    h_add(sizes,"129");
    h_add(sizes,"1024");
    i=0;
    while i<15 {
        let mark=h_mark();
        let message="";
        let n=0;
        if i==1 {
            message="abc";
            n=3;
        }else if i==2 {
            message=h_repeat("a",1000000);
            n=1000000;
        }else if i>2 {
            n=h_number(h_at(sizes,i-3));
            message=h_take(n);
            let k=0;
            while k<n {
                store8(message+k,k%256);
                k=k+1;
            }
        }
        let file=h_join(t_work,"message");
        h_save_bytes(file,message,n,384);
        h_check(h_run(h_args(harness,file,0,0,0,0)),0,h_sha_bytes(message,n));
        t_checks=t_checks+1;
        h_reset(mark);
        i=i+1;
    }
    h_stop(server);
    h_env=environment;
    return t_done();
}
fn main(argc,argv) {
    return t_entry(argc,argv);
}
