import "lib/harness.flex";
import "lib/signing.flex";
fn ts_verify(harness,key,signature,message,n,valid,key_size,sig_size) {
    let packet=h_take(120+n);
    store64(packet,key_size);
    store64(packet+8,sig_size);
    store64(packet+16,n);
    h_copy(packet+24,key,32);
    h_copy(packet+56,signature,64);
    h_copy(packet+120,message,n);
    let path=h_join(t_work,"packet");
    h_save_bytes(path,packet,120+n,384);
    let env=h_env;
    h_setenv("PATH","/no/executables");
    let status=1;
    if valid {
        status=0;
    }
    h_check(h_run(h_args(harness,path,0,0,0,0)),status,0);
    h_env=env;
    t_checks=t_checks+1;
    return 0;
}
fn ts_refuse(tool,tree,message,version) {
    syscall(87,h_join(tree,"dist/SHA256SUMS.sig"),0,0,0,0,0);
    let args=h_args(tool,0,0,0,0,0);
    if version {
        h_add(args,"--version");
        h_add(args,version);
    }
    let p=h_wait(h_spawn(args,"",tree));
    h_check(p,1,0);
    h_assert(h_has(h_err(p),message),h_err(p));
    h_assert(!h_exists(h_join(tree,"dist/SHA256SUMS.sig")),"signature published on failure");
    let secret=h_getenv("FLEXSCRIPT_RELEASE_SIGNING_KEY");
    if secret && h_len(secret) {
        h_assert(!h_has(h_out(p),secret) && !h_has(h_err(p),secret),"signer leaked private key");
    }
    t_checks=t_checks+1;
    return 0;
}
fn suite(compiler) {
    t_init(compiler);
    let version=b_version();
    t_program(h_cat(h_read("lib/signature.flex"),"\nfn main(argc,argv){let fd=syscall(2,load64(argv+8),0,0,0,0,0);if fd<0{return 2;}let data=alloc(4096);let size=syscall(0,fd,data,4096,0,0,0);syscall(3,fd,0,0,0,0,0);if size<120{return 2;}if ed25519_verify(data+24,load64(data),data+56,load64(data+8),data+120,load64(data+16)){return 0;}return 1;}"));
    t_compile();
    let harness=t_binary;
    let vectors=j_parse(h_read("tests/tooling/ed25519.json"));
    let i=0;
    let key=0;
    let sig=0;
    let msg=0;
    let size=0;
    while i<j_count(vectors) {
        let vector=j_at(vectors,i);
        key=h_unhex(j_value(j_at(vector,0)));
        msg=h_unhex(j_value(j_at(vector,1)));
        size=h_len(j_value(j_at(vector,1)))/2;
        sig=h_unhex(j_value(j_at(vector,2)));
        ts_verify(harness,key,sig,msg,size,1,32,64);
        let changed=h_take(size+1);
        h_copy(changed,msg,size);
        store8(changed+size,0);
        ts_verify(harness,key,sig,changed,size+1,0,32,64);
        let copy=h_take(64);
        h_copy(copy,key,32);
        store8(copy,load8(copy)^1);
        ts_verify(harness,copy,sig,msg,size,0,32,64);
        h_copy(copy,sig,64);
        store8(copy,load8(copy)^1);
        ts_verify(harness,key,copy,msg,size,0,32,64);
        h_copy(copy,sig,64);
        store8(copy+63,load8(copy+63)^1);
        ts_verify(harness,key,copy,msg,size,0,32,64);
        let order=h_unhex("edd3f55c1a631258d69cf7a2def9de140000000000000000000000000000000010");
        h_copy(copy,sig,64);
        let k=0;
        let carry=0;
        while k<32 {
            let sum=load8(copy+32+k)+load8(order+k)+carry;
            store8(copy+32+k,sum&255);
            carry=sum>>8;
            k=k+1;
        }
        ts_verify(harness,key,copy,msg,size,0,32,64);
        i=i+1;
    }
    let sizes=h_args("0","31","33",0,0,0);
    i=0;
    while i<3 {
        ts_verify(harness,key,sig,msg,size,0,h_number(h_at(sizes,i)),64);
        i=i+1;
    }
    sizes=h_args("0","63","65",0,0,0);
    i=0;
    while i<3 {
        ts_verify(harness,key,sig,msg,size,0,32,h_number(h_at(sizes,i)));
        i=i+1;
    }
    let tree=h_join(t_work,"signer");
    h_mkdir(h_join(tree,"keys"));
    h_mkdir(h_join(tree,"compiler"));
    h_mkdir(h_join(tree,"dist"));
    h_save(h_join(tree,"VERSION"),h_cat(version,"\n"));
    let tool=h_join(t_work,"sign-release");
    h_compile(t_compiler,"scripts/sign-release.flex",tool);
    let private=h_join(t_work,"private.pem");
    h_ok(h_args("openssl","genpkey","-algorithm","ED25519","-out",private));
    let public=h_ok(h_args("openssl","pkey","-in",private,"-pubout",0));
    h_save(h_join(tree,"keys/release-ed25519.pub.pem"),h_out(public));
    let public_key=sg_key(h_out(public),0);
    let anchor=sg_public(public_key);
    let compiler_path=h_join(tree,"compiler/main.flex");
    let compiler_text=h_cat3("fn release_public_key() { return \"",h_hex(anchor,32),"\"; }");
    h_save(compiler_path,compiler_text);
    let manifest=h_buffer();
    let prefixes=h_args("flexscript","flexscript-core",0,0,0,0);
    let contents=h_args("full compiler","core compiler",0,0,0,0);
    i=0;
    while i<2 {
        let name=h_cat3(h_at(prefixes,i),"-",h_cat(version,"-linux-x86_64"));
        h_save(h_join(tree,h_cat("dist/",name)),h_at(contents,i));
        h_text(manifest,h_cat3(h_sha_bytes(h_at(contents,i),h_len(h_at(contents,i))),"  ",h_cat(name,"\n")));
        i=i+1;
    }
    let manifest_path=h_join(tree,"dist/SHA256SUMS");
    h_save(manifest_path,h_data(manifest));
    let environment=h_env;
    h_setenv("FLEXSCRIPT_RELEASE_SIGNING_KEY",h_read(private));
    h_check(h_wait(h_spawn(h_args(tool,0,0,0,0,0),"",tree)),0,0);
    let signature=h_read(h_join(tree,"dist/SHA256SUMS.sig"));
    h_assert(h_file_size==64,"signature length");
    let message=sg_message(version,"linux-x86_64",h_data(manifest));
    ts_verify(harness,anchor,signature,message,h_len(message),1,32,64);
    let wrong=sg_message(version,"linux-aarch64",h_data(manifest));
    ts_verify(harness,anchor,signature,wrong,h_len(wrong),0,32,64);
    ts_verify(harness,anchor,signature,message,h_len(message)-1,0,32,64);
    h_setenv("FLEXSCRIPT_RELEASE_SIGNING_KEY",0);
    ts_refuse(tool,tree,"required; refusing unsigned",0);
    let other=h_join(t_work,"other.pem");
    h_ok(h_args("openssl","genpkey","-algorithm","ED25519","-out",other));
    h_setenv("FLEXSCRIPT_RELEASE_SIGNING_KEY",h_read(other));
    ts_refuse(tool,tree,"does not match",0);
    h_setenv("FLEXSCRIPT_RELEASE_SIGNING_KEY","invalid");
    ts_refuse(tool,tree,"OpenSSL release-signing operation failed",0);
    h_setenv("FLEXSCRIPT_RELEASE_SIGNING_KEY",h_read(private));
    let versions=h_args("v0.0.4","00.0.4","0.0.1000000000","99.99.99",0,0);
    i=0;
    while i<4 {
        ts_refuse(tool,tree,"version",h_at(versions,i));
        i=i+1;
    }
    let uppercase=h_slice(h_data(manifest),h_size(manifest));
    i=0;
    while i<h_size(manifest) {
        let c=load8(uppercase+i);
        if c>=97 && c<=122 {
            store8(uppercase+i,c-32);
        }
        i=i+1;
    }
    h_save(manifest_path,uppercase);
    ts_refuse(tool,tree,"checksums do not match",0);
    h_save(manifest_path,h_data(manifest));
    let asset=h_join(tree,h_cat3("dist/flexscript-",version,"-linux-x86_64"));
    h_save(asset,"tampered compiler");
    ts_refuse(tool,tree,"checksums do not match",0);
    h_save(asset,"full compiler");
    h_save(compiler_path,h_cat3("fn release_public_key() { return \"",h_repeat("0",64),"\"; }"));
    ts_refuse(tool,tree,"differs from the compiler trust anchor",0);
    h_env=environment;
    return t_done();
}
fn main(argc,argv) {
    return t_entry(argc,argv);
}
