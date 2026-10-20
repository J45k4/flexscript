// Native, credential-free model fixture. Real turn loop, native tools and VM adapter.
import "../core/cli.flex";

fn fixture_has_checkpoint(messages) {let i=0;while i<j_count(messages) {if co_compaction(j_at(messages,i)) {return 1;}i=i+1;}return 0;}
fn fixture_workspace(prompt,step,messages) {
    let program="";let expected="";let answer="";
    if h_equal(prompt,"db seed") {expected="stored\n";answer="Workspace saved.";program="fn main(){if db_count(db_tables())!=0 || !db_begin(){return 1;}let s=db_schema();db_column(s,\"value\",2,0);if !db_create(\"memo\",s){return 2;}let v=db_values();db_add(v,db_text(\"remembered\\n\"));if !db_insert(\"memo\",v) || !db_commit(){return 3;}return say(\"stored\\n\");}";}
    else if h_equal(prompt,"db recall") {expected="remembered\n";answer="Workspace recalled.";program="fn main(){let row=db_get(\"memo\",1);if db_kind(row)!=5 || db_count(db_columns(\"memo\"))!=2{return 1;}return say(db_word(db_cell(row,0)));}";}
    else if h_equal(prompt,"db evolve") {expected="evolved\n";answer="Schema evolved.";program="fn main(){if !db_begin() || !db_add_column(\"memo\",\"phase\",1,0,db_int(7)) || !db_rename_column(\"memo\",\"value\",\"memory\") || !db_commit(){return 1;}return say(\"evolved\\n\");}";}
    else if h_equal(prompt,"db inspect") {expected="empty\n";answer="Workspace is empty.";program="fn main(){if db_count(db_tables())!=0{return 1;}return say(\"empty\\n\");}";}
    else if h_equal(prompt,"db history") {expected="found\n";answer="Archived seed request found.";program="fn main(){let rows=db_history(0,128);let i=0;while i<db_count(rows){let s=db_word(db_cell(db_at(rows,i),1));if db_len(s)==7 && load8(s)==100 && load8(s+3)==115{return say(\"found\\n\");}i=i+1;}return 1;}";}
    else {h_die("unknown workspace fixture");}
    if !step {return h_cat("fn say(s){syscall(1,1,s,db_len(s),0,0,0);return 0;}",program);}
    let last=j_at(messages,j_count(messages)-1);h_assert(h_equal(j_s(last,"type"),"custom_tool_call_output"),"missing workspace tool result");let observation=c_json(j_s(last,"output"));h_assert(j_n(observation,"exit_code")==0 && h_equal(j_s(observation,"stdout"),expected),"workspace execution did not produce expected data");return answer;
}
fn fixture_compact() {
    let request=c_json(c_read("/proc/self/fd/0",16777216));let messages=j_need(request,"messages");let config=j_need(request,"config");let body=co_compact_request(j_s(config,"model"),messages);let input=j_need(body,"input");h_assert(h_equal(j_s(j_at(input,j_count(input)-1),"type"),"compaction_trigger"),"missing compaction trigger");h_assert(j_count(j_need(body,"tools"))==1 && h_equal(j_s(j_at(j_need(body,"tools"),0),"name"),"flexscript"),"compaction lost tool definition");
    let mode="ok";let path=h_getenv("COLLIE_FIXTURE_COMPACT_MODE");if path {let text=c_read(path,1024);if text {mode=h_trim(text);}}
    if h_equal(mode,"failure") {h_print(1,j_dump(c_error("Fixture compaction failed.")));return 0;}
    if h_equal(mode,"slow") {h_sleep(3000);}
    let item=j_object();j_set(item,"type",j_string("compaction"));let cipher="fixture-encrypted-checkpoint";if h_equal(mode,"nonreducing") {cipher=h_repeat("x",100000);}j_set(item,"encrypted_content",j_string(cipher));let output=j_array();if !h_equal(mode,"malformed") {j_push(output,item);}
    let response=j_object();j_set(response,"status",j_string("completed"));j_set(response,"output",output);let event=j_object();j_set(event,"type",j_string("response.completed"));j_set(event,"response",response);let stream=h_cat3("data: ",j_dump(event),"\n\n");
    co_compact_mode=1;co_problem=0;http_buffer=stream;http_start=0;http_end=h_len(stream);co_chunked=0;co_remaining=h_len(stream);co_chunk_crlf=0;co_body_size=0;co_body_eof=0;co_line=h_take(8193);let result=co_receive();
    let reply=c_error(co_problem);if result {reply=j_object();j_set(reply,"item",result);}h_print(1,j_dump(reply));return 0;
}

fn fixture_model() {
    let request=c_json(c_read("/proc/self/fd/0",16777216));let config=j_need(request,"config");
    ce_enabled=c_flag(config,"events");co_message_fd=j_n(request,"message_fd");co_stream_reset();
    let prompt=j_s(config,"prompt");let step=j_n(request,"step");let text="Fixture reply.";let source=0;let streamed=0;
    let call_id=co_new_call_id();let item_id=h_cat("ctc_",call_id);
    if h_equal(prompt,"context exceeded") && !fixture_has_checkpoint(j_need(request,"messages")) {let error=c_error("Context length exceeded.");j_set(error,"context_exceeded",j_bool(1));h_print(1,j_dump(error));return 0;}
    if h_equal(prompt,"slow") {co_stream_delta("First streamed chunk ");h_sleep(3000);text="First streamed chunk last chunk";co_stream_delta("last chunk");streamed=1;}
    else if h_equal(prompt,"slow code") {text="";co_source_delta("fn main(){",item_id);h_sleep(3000);source="fn main(){return 0;}";co_source_delta("return 0;}",item_id);streamed=1;}
    else {
        if h_starts(prompt,"db ") {let value=fixture_workspace(prompt,step,j_need(request,"messages"));text=value;if !step {source=value;text="";}}
        else if h_starts(prompt,"Remember ") {text=h_cat("Remembered: ",prompt+9);}
        else if h_equal(prompt,"Recall") {let messages=j_need(request,"messages");let found=0;let i=0;while i<j_count(messages) {let m=j_at(messages,i);let content=c_string(m,"content");let role=c_string(m,"role");if role && h_equal(role,"user") && content && h_starts(content,"Remember ") {found=content+9;}i=i+1;}h_assert(found,"conversation context was lost");text=h_cat("Recalled: ",found);}
        else if h_equal(prompt,"code") {text="42 is the actual VM result.";if !step {text="I will calculate.\n";source="fn main(){let s=\"42\\n\";syscall(1,1,s,3,0,0,0);return 0;}";}}
        else if h_equal(prompt,"failure") {text="Recovered from the compiler error.";if !step {text="";source="fn main(){return missing_function();}";}}
        else if h_equal(prompt,"literal tags") {text="<FLEXSCRIPT>fn main(){return 0;}</FLEXSCRIPT> is ordinary text.";}
        else if h_equal(prompt,"unknown tool") {text="";source="fn main(){return 0;}";}
        else if h_equal(prompt,"host failure") {text="";source="fn main(){return 0;}";}
        else if h_equal(prompt,"worker crash") {syscall(60,7,0,0,0,0,0);}
        else if h_equal(prompt,"controls") {text=tu_ansi("Safe @[2Jtext");}
        else if h_equal(prompt,"context exceeded") {text="Recovered from context exhaustion.";}
        else if h_equal(prompt,"mid compact") {text="Mid-turn compaction kept the VM result: 42.";if !step {text="";source="fn main(){let s=\"42\\n\";syscall(1,1,s,3,0,0,0);return 0;}";}else {h_assert(fixture_has_checkpoint(j_need(request,"messages")),"missing mid-turn checkpoint");}}
    }
    if !streamed {co_stream_delta(text);if source {co_source_delta(source,item_id);}}
    let output=j_array();
    if h_len(text) {let part=j_object();j_set(part,"type",j_string("output_text"));j_set(part,"text",j_string(text));let content=j_array();j_push(content,part);let message=j_object();j_set(message,"type",j_string("message"));j_set(message,"role",j_string("assistant"));j_set(message,"content",content);j_push(output,message);}
    if source {let call=j_object();j_set(call,"type",j_string("custom_tool_call"));j_set(call,"name",j_string("flexscript"));if h_equal(prompt,"unknown tool") {j_set(call,"name",j_string("shell"));}j_set(call,"id",j_string(item_id));j_set(call,"call_id",j_string(call_id));j_set(call,"status",j_string("completed"));j_set(call,"input",j_string(source));j_push(output,call);}
    let reply=co_output(output);if !reply {h_print(1,j_dump(c_error(co_problem)));return 0;}
    if h_equal(prompt,"usage one") || h_equal(prompt,"usage two") {
        let usage=j_object();let input=100;let output_tokens=20;if h_equal(prompt,"usage two") {input=200;output_tokens=30;}
        j_set(usage,"input_tokens",j_int(input));j_set(usage,"output_tokens",j_int(output_tokens));j_set(reply,"usage",usage);
    }
    if h_equal(prompt,"grow context") || (h_equal(prompt,"mid compact") && !step) {let usage=j_object();j_set(usage,"input_tokens",j_int(6000));j_set(usage,"output_tokens",j_int(100));j_set(reply,"usage",usage);}
    h_print(1,j_dump(reply));return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);
    if argc==3 && h_equal(load64(argv+8),"--adapter") && h_equal(load64(argv+16),"model") {return fixture_model();}
    if argc==3 && h_equal(load64(argv+8),"--adapter") && h_equal(load64(argv+16),"compact") {return fixture_compact();}
    if argc==3 && h_equal(load64(argv+8),"--adapter") && h_equal(load64(argv+16),"run") {
        let request=c_json(c_read("/proc/self/fd/0",16777216));let config=j_need(request,"config");
        if h_equal(j_s(config,"prompt"),"host failure") {h_print(1,j_dump(c_error("Fixture isolated VM could not start.")));return 0;}
        let result=cp_execute_history(config,j_s(request,"source"),j_get(request,"history"));h_print(1,j_dump(result));return 0;
    }
    return collie_cli(argc,argv);
}
