// Ed25519 verification through OpenSSL 3. Keys are raw 32-byte public keys;
// signatures are raw 64-byte signatures. Returns 1 only for a valid signature.
global signature_library=0;
global signature_key_new=0;
global signature_key_free=0;
global signature_ctx_new=0;
global signature_ctx_free=0;
global signature_verify_init=0;
global signature_verify=0;
fn signature_init() {
    if signature_library {return 1;}
    let lib=ffi_open("libcrypto.so.3");if !lib {return 0;}
    signature_key_new=ffi_symbol(lib,"EVP_PKEY_new_raw_public_key_ex");
    signature_key_free=ffi_symbol(lib,"EVP_PKEY_free");
    signature_ctx_new=ffi_symbol(lib,"EVP_MD_CTX_new");
    signature_ctx_free=ffi_symbol(lib,"EVP_MD_CTX_free");
    signature_verify_init=ffi_symbol(lib,"EVP_DigestVerifyInit");
    signature_verify=ffi_symbol(lib,"EVP_DigestVerify");
    if !signature_key_new || !signature_key_free || !signature_ctx_new
        || !signature_ctx_free || !signature_verify_init || !signature_verify {
        // A partially initialized library must not be considered usable.
        let close=ffi_symbol(lib,"dlclose");if close {ffi_call(close,lib,0,0,0,0,0);}
        return 0;
    }
    signature_library=lib;return 1;
}
fn ed25519_verify(public_key,key_size,sig,sig_size,message,size) {
    if !public_key || key_size!=32 || !sig || sig_size!=64 || !message || size<0 {return 0;}
    if !signature_init() {return 0;}
    let key=ffi_call(signature_key_new,0,"ED25519",0,public_key,32,0);
    if !key {return 0;}
    let ctx=ffi_call(signature_ctx_new,0,0,0,0,0,0);let valid=0;
    // Pure Ed25519 uses a NULL digest and one-shot verification, not a prehash.
    if ctx {
        if ffi_call_i32(signature_verify_init,ctx,0,0,0,key,0)==1 {
            valid=ffi_call_i32(signature_verify,ctx,sig,64,message,size,0)==1;
        }
        ffi_call(signature_ctx_free,ctx,0,0,0,0,0);
    }
    ffi_call(signature_key_free,key,0,0,0,0,0);return valid;
}
