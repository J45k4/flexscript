import "system.flex";
import "../../../../libs/http.flex";
global cn_slots=0;
// Collie stream slots retain their read cursor across service arena compaction.
// 0 HTTP request, 8 body pointer, 16 available bytes, 24 limit, 32 done,
// 40 transport failure, 56 consumed offset, 80 allow truncation, 88 truncated.
fn cn_init(){if cn_slots{return 1;}cn_slots=alloc(16*128);if cn_slots<0{cn_slots=0;return sh_fail("Cannot allocate HTTP requests");}return 1;}
fn cn_url(url){return h_starts(url,"https://") && h_len(url)<=16384;}
fn cn_headers(headers){
    let out=h_buffer();let agent=0;
    if headers && j_kind(headers)==4{let fields=j_value(headers);let i=0;while i<h_count(fields){
        let pair=h_at(fields,i);let name=load64(pair);let value=load64(pair+8);
        if j_kind(value)==2{
            let at=0;while load8(name+at){if !hc_token(load8(name+at)){return sh_fail("Invalid HTTPS header name");}at=at+1;}
            if !at{return sh_fail("Invalid HTTPS header name");}
            let text=j_value(value);at=0;while load8(text+at){let c=load8(text+at);if (c<32 && c!=9) || c==127{return sh_fail("Invalid HTTPS header value");}at=at+1;}
            if hc_equal(name,"user-agent"){agent=1;}
            if hc_equal(name,"accept-encoding"){
                if !hc_equal(h_trim(text),"identity"){return sh_fail("HTTPS supports identity content encoding");}
            }else{h_text(out,name);h_text(out,": ");h_text(out,text);h_text(out,"\r\n");}
        }i=i+1;
    }}if !agent{h_text(out,"User-Agent: collie/0.1\r\n");}return h_data(out);
}
fn cn_start(url,headers,body,limit,timeout,redirects){
    if !cn_url(url){return sh_fail("A credential-free HTTPS URL is required");}if !cn_init(){return 0;}
    let i=0;while i<16 && load64(cn_slots+i*128){i=i+1;}if i==16{return sh_fail("Too many active HTTPS requests");}
    let fields=cn_headers(headers);if !fields{return 0;}
    let options=http_client_options();if !options{return sh_fail("Cannot allocate HTTP options");}
    store64(options,timeout);store64(options+8,limit);store64(options+16,redirects);store64(options+24,1);
    let ca=h_getenv("SSL_CERT_FILE");if !ca{ca=h_getenv("CURL_CA_BUNDLE");}if ca{store64(options+32,ca);}
    let method="GET";let size=0;if body{method="POST";size=h_len(body);}
    let request=http_client_start(method,url,fields,body,size,options);http_client_options_free(options);
    if !request{return sh_fail(http_client_message);}
    let slot=h_zero(cn_slots+i*128,128);store64(slot,request);store64(slot+8,http_client_data(request));store64(slot+24,limit);return slot;
}
fn cn_pump(){
    if !cn_slots{return 0;}let i=0;while i<16{let slot=cn_slots+i*128;let request=load64(slot);
        if request && !load64(slot+32){
            http_client_allow_truncation(request,load64(slot+80));let result=http_client_step(request);
            store64(slot+16,http_client_size(request));store64(slot+88,http_client_truncated(request));
            if result{store64(slot+32,1);store64(slot+40,result<0);}
        }i=i+1;
    }return 0;
}
fn cn_status(slot){return http_client_status(load64(slot));}
fn cn_effective_url(slot){return http_client_url(load64(slot));}
fn cn_error(slot){
    let error=http_client_error(load64(slot));if error{return error;}
    let status=cn_status(slot);if status==401{return "Codex login rejected; update your account login";}
    if status==429{return "Codex usage limit reached";}
    if status<200 || status>=300{return h_cat("HTTPS endpoint returned HTTP ",h_int(status));}return 0;
}
fn cn_close(slot){if !slot || !load64(slot){return 0;}http_client_free(load64(slot));h_zero(slot,128);return 0;}
fn cn_shutdown(){if !cn_slots{return 0;}let i=0;while i<16{cn_close(cn_slots+i*128);i=i+1;}syscall(11,cn_slots,16*128,0,0,0,0);cn_slots=0;return 0;}
