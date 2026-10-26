// Opt-in live smoke test. Never run from ordinary CI: consumes account usage.
// responses-live --api [model] uses OPENAI_API_KEY with api.openai.com.
// responses-live AUTH_FILE [model] uses Collie's ChatGPT/Codex Responses route.
// No credentials, raw event bodies, private reasoning or account details logged.
import "../../apps/collie/desktop/host/network.flex";
import "../../apps/collie/providers/codex.flex";
global rl_output=0;
global rl_events=0;
global rl_complete=0;
global rl_failed=0;
global rl_usage=0;
global rl_delta_ms=0;
global rl_started=0;

fn rl_event(raw) {
    if h_equal(raw,"[DONE]") {return 0;}
    let event=sj_parse(raw);if !event || j_kind(event)!=4 {rl_failed=1;return 0;}
    rl_events=rl_events+1;let kind=cj_text(event,"type");
    if h_equal(kind,"response.output_text.delta") {
        if !rl_delta_ms {rl_delta_ms=net_now()-rl_started;}
        h_text(rl_output,cj_text(event,"delta"));
    }else if h_equal(kind,"response.completed") {
        let response=cj_get(event,"response");
        if !h_equal(cj_text(response,"status"),"completed") {rl_failed=1;}
        else {rl_complete=1;rl_usage=cj_get(response,"usage");}
    }else if h_equal(kind,"response.failed") || h_equal(kind,"response.incomplete") || h_equal(kind,"error") {rl_failed=1;}
    return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);rl_output=h_buffer();
    if argc<2 {h_print(2,"Usage: responses-live --api|AUTH_FILE [model]\n");return 2;}
    let source=load64(argv+8);let model="gpt-6.1-sol";if argc>2 {model=load64(argv+16);}
    let api=h_equal(source,"--api");let headers=j_object();let url="https://api.openai.com/v1/responses";
    if api {
        let key=h_getenv("OPENAI_API_KEY");if !key || !h_len(key) {h_print(2,"OPENAI_API_KEY is required for --api\n");return 2;}
        sh_s(headers,"Authorization",h_cat("Bearer ",key));sh_s(headers,"Content-Type","application/json");sh_s(headers,"Accept","text/event-stream");
    }else {
        let auth=co_auth(source);if !auth {h_print(2,"Selected Codex credentials are unavailable\n");return 2;}
        let transport=co_transport(auth);url=cj_text(transport,"url");headers=cj_get(transport,"headers");
    }
    let body=j_object();sh_s(body,"model",model);sh_s(body,"instructions","This is a transport smoke test. Follow the user's short output instruction. Do not use tools.");
    let parts=j_array();let part=sh_s(j_object(),"type","input_text");sh_s(part,"text","Reply with exactly: Flexscript native HTTP generation works.");j_push(parts,part);
    let messages=j_array();let message=sh_s(j_object(),"role","user");j_set(message,"content",parts);j_push(messages,message);
    j_set(body,"input",messages);sh_b(body,"stream",1);sh_b(body,"store",0);
    let reasoning=sh_s(j_object(),"effort","low");j_set(body,"reasoning",reasoning);
    if api {sh_n(body,"max_output_tokens",128);}
    rl_started=net_now();let slot=cn_start(url,headers,j_dump(body),1048576,120000,0);
    if !slot {h_print(2,se);return 1;}
    let cursor=0;let data="";let first_ms=0;
    while !load64(slot+32) {
        cn_pump();let bytes=load64(slot+8);let end=load64(slot+16);
        if end>0 && !first_ms {first_ms=net_now()-rl_started;}
        let at=cursor;while at<end {
            if load8(bytes+at)==10 {
                let n=at-cursor;if n && load8(bytes+cursor+n-1)==13 {n=n-1;}
                let line=h_slice(bytes+cursor,n);
                if h_starts(line,"data:") {
                    let value=line+5;while load8(value)==32 {value=value+1;}
                    if h_len(data) {data=h_cat3(data,"\n",value);}else {data=value;}
                }else if !n && h_len(data) {rl_event(data);data="";}
                cursor=at+1;
            }at=at+1;
        }if !load64(slot+32) {h_sleep(1);}
    }
    let report=j_object();sh_s(report,"endpoint",url);sh_s(report,"model",model);
    sh_n(report,"http_status",cn_status(slot));sh_n(report,"elapsed_ms",net_now()-rl_started);
    sh_n(report,"first_body_ms",first_ms);sh_n(report,"first_text_delta_ms",rl_delta_ms);
    sh_n(report,"events",rl_events);sh_n(report,"response_bytes",load64(slot+16));
    sh_s(report,"output",h_data(rl_output));sh_b(report,"completed",rl_complete);
    let error=http_client_error(load64(slot));if error {sh_s(report,"transport_error",error);}
    if rl_usage {
        sh_n(report,"input_tokens",cj_int(rl_usage,"input_tokens"));sh_n(report,"output_tokens",cj_int(rl_usage,"output_tokens"));
    }
    let success=cn_status(slot)==200 && !error && rl_complete && !rl_failed && h_equal(h_trim(h_data(rl_output)),"Flexscript native HTTP generation works.");
    sh_b(report,"success",success);cn_close(slot);cn_shutdown();h_print(1,j_dump(report));h_print(1,"\n");
    if !success {return 1;}return 0;
}
