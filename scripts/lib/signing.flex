// Ed25519 release signer. Key parsing/signing stays inside OpenSSL; no child
// command receives the CI private key and no private key file is created.
import "build.flex";
global sg_crypto=0;
fn sg_symbol(name) {
    if !sg_crypto {
        sg_crypto=ffi_open("libcrypto.so.3");
    }
    h_assert(sg_crypto,"OpenSSL release-signing operation failed");
    let p=ffi_symbol(sg_crypto,name);
    h_assert(p,"OpenSSL release-signing operation failed");
    return p;
}
fn sg_key(pem,private) {
    let bio=ffi_call(sg_symbol("BIO_new_mem_buf"),pem,h_len(pem),0,0,0,0);
    h_assert(bio,"OpenSSL release-signing operation failed");
    let symbol="PEM_read_bio_PUBKEY";
    if private {
        symbol="PEM_read_bio_PrivateKey";
    }
    let key=ffi_call(sg_symbol(symbol),bio,0,0,0,0,0);
    ffi_call(sg_symbol("BIO_free"),bio,0,0,0,0,0);
    h_assert(key,"OpenSSL release-signing operation failed");
    h_assert(ffi_call_i32(sg_symbol("EVP_PKEY_is_a"),key,"ED25519",0,0,0,0)==1,"release public key must be Ed25519");
    return key;
}
fn sg_public(key) {
    let p=h_take(32);
    let size=h_take(8);
    store64(size,32);
    h_assert(ffi_call_i32(sg_symbol("EVP_PKEY_get_raw_public_key"),key,p,size,0,0,0)==1 && load64(size)==32,"release public key must be Ed25519");
    return p;
}
fn sg_sign_message(key,data,n) {
    let context=ffi_call(sg_symbol("EVP_MD_CTX_new"),0,0,0,0,0,0);
    h_assert(context,"OpenSSL release-signing operation failed");
    h_assert(ffi_call_i32(sg_symbol("EVP_DigestSignInit"),context,0,0,0,key,0)==1,"OpenSSL release-signing operation failed");
    let signature=h_take(64);
    let size=h_take(8);
    store64(size,64);
    h_assert(ffi_call_i32(sg_symbol("EVP_DigestSign"),context,signature,size,data,n,0)==1 && load64(size)==64,"OpenSSL release-signing operation failed");
    ffi_call(sg_symbol("EVP_MD_CTX_free"),context,0,0,0,0,0);
    return signature;
}
fn sg_verify_message(key,signature,data,n) {
    let context=ffi_call(sg_symbol("EVP_MD_CTX_new"),0,0,0,0,0,0);
    h_assert(context,"OpenSSL release-signing operation failed");
    let valid=ffi_call_i32(sg_symbol("EVP_DigestVerifyInit"),context,0,0,0,key,0)==1 && ffi_call_i32(sg_symbol("EVP_DigestVerify"),context,signature,64,data,n,0)==1;
    ffi_call(sg_symbol("EVP_MD_CTX_free"),context,0,0,0,0,0);
    return valid;
}
fn sg_message(version,target,manifest) {
    return h_cat3(h_cat3("Flexscript release signature v1\nversion=",version,"\ntarget="),target,h_cat("\n",manifest));
}
fn sg_sign(dist,version) {
    h_assert(b_valid_version(version),"invalid release version");
    h_assert(h_equal(version,b_version()),"release version differs from source VERSION");
    let manifest=h_read(h_join(dist,"SHA256SUMS"));
    h_assert(h_file_size>0 && h_file_size<=65536,"invalid checksum manifest size");
    let expected=h_buffer();
    let prefixes=h_args("flexscript","flexscript-core",0,0,0,0);
    let i=0;
    while i<2 {
        let name=h_cat3(h_at(prefixes,i),"-",h_cat(version,"-linux-x86_64"));
        let file=h_join(dist,name);
        let data=h_read(file);
        h_assert(h_file_size>0 && h_file_size<=67108864,"invalid release binary size");
        h_text(expected,h_cat3(h_sha_bytes(data,h_file_size),"  ",h_cat(name,"\n")));
        i=i+1;
    }
    h_assert(h_equal(manifest,h_data(expected)),"release checksums do not match both compiler assets");
    let public=sg_key(h_read("keys/release-ed25519.pub.pem"),0);
    let anchor=sg_public(public);
    let source=h_read("compiler/main.flex");
    let prefix="fn release_public_key() { return \"";
    let at=h_find(source,prefix);
    h_assert(at>=0,"public key differs from the compiler trust anchor");
    h_assert(h_bytes(source+at+h_len(prefix),h_hex(anchor,32),64) && load8(source+at+h_len(prefix)+64)==34,"public key differs from the compiler trust anchor");
    let private=h_getenv("FLEXSCRIPT_RELEASE_SIGNING_KEY");
    h_assert(private && h_len(private),"FLEXSCRIPT_RELEASE_SIGNING_KEY is required; refusing unsigned release");
    h_assert(h_starts(private,"-----BEGIN PRIVATE KEY-----"),"OpenSSL release-signing operation failed");
    let key=sg_key(private,1);
    h_assert(h_bytes(sg_public(key),anchor,32),"CI signing key does not match the pinned release public key");
    let data=sg_message(version,"linux-x86_64",manifest);
    let signature=sg_sign_message(key,data,h_len(data));
    h_assert(sg_verify_message(public,signature,data,h_len(data)),"OpenSSL release-signing operation failed");
    ffi_call(sg_symbol("EVP_PKEY_free"),key,0,0,0,0,0);
    ffi_call(sg_symbol("EVP_PKEY_free"),public,0,0,0,0,0);
    let random=h_take(8);
    h_assert(syscall(318,random,8,0,0,0,0)==8,"signature staging failed");
    let staged=h_join(dist,h_cat(".signature-",h_hex(random,8)));
    let fd=syscall(2,staged,0x800c1,420,0,0,0);
    h_assert(fd>=0,"signature staging failed");
    let written=h_write(fd,signature,64);
    let closed=syscall(3,fd,0,0,0,0,0);
    if written!=64 || closed<0 || syscall(82,staged,h_join(dist,"SHA256SUMS.sig"),0,0,0,0)<0 {
        syscall(87,staged,0,0,0,0,0);
        h_die("signature publishing failed");
    }
    return signature;
}
