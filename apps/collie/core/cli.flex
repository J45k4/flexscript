import "tui.flex";

fn collie_worker(operation) {
    let text=c_read("/proc/self/fd/0",16777216);
    if !text {h_print(1,j_dump(c_error("Invalid or oversized adapter request.")));return 0;}
    let request=c_json(text);let config=j_need(request,"config");let reply=0;
    ce_enabled=c_flag(config,"events");
    if h_equal(operation,"model") {
        co_message_fd=-1;let fd=j_get(request,"message_fd");
        if fd && j_kind(fd)==1 && j_value(fd)>=3 {co_message_fd=j_value(fd);}
        reply=co_generate(config,j_need(request,"messages"),j_n(request,"step"));
    }
    else if h_equal(operation,"auth") {
        // Validate in the credential worker; return no tokens to the UI host.
        if co_auth(j_s(config,"auth_file")) {reply=j_object();j_set(reply,"ok",j_bool(1));}
        else {reply=c_error(co_problem);}
    }
    else if h_equal(operation,"model_info") {reply=co_model_info(config);}
    else if h_equal(operation,"compact") {reply=co_compact(config,j_need(request,"messages"));}
    else if h_equal(operation,"run") {reply=cp_execute_history(config,j_s(request,"source"),j_get(request,"history"));}
    else {reply=c_error("Unknown host adapter operation.");}
    h_print(1,j_dump(reply));return 0;
}
fn collie_options() {
    h_print(1,"Usage: collie [options] ['task']\n  No arguments opens the TUI using Codex auth.json and gpt-6.1-sol.\n  No task opens the interactive terminal UI. A quoted task uses plain output.\n  --tui               Open the terminal UI, optionally starting with 'task'\n  --history-dir PATH  TUI sessions (default XDG_STATE_HOME/collie/sessions)\n  --resume latest|ID  Resume a saved TUI conversation\n  --model MODEL       Codex model ID (default gpt-6.1-sol)\n  --auth-file PATH    Codex ChatGPT auth.json (defaults to CODEX_HOME/auth.json)\n  --compiler PATH     Native Flexscript compiler with VM support\n  --replay PATH       Offline JSON array of source replies\n  --max-steps N       Model reply limit, 1..32 (default 8)\n  --stream            Preview code (stderr in plain mode; expanded in TUI)\n  --trace [PATH]      Save source and observations (default collie-trace.json)\n  --trace=PATH        Explicit trace filename; trace files use mode 0600\n  --context-window N  Override window, capped by the model's advertised maximum\n  --auto-compact N    Override compaction threshold, capped at 90% of the window\n  TUI: /compact compacts now; automatic compaction is enabled by default.\n");return 0;
}
fn collie_help() {
    collie_options();h_print(1,"  --workspace PATH    Persistent FlexDB file (default: one empty workspace per session)\n  TUI: /context shows limits; /compact [N|default] manages compaction.\n  Guest db_* API: tables, schemas, transactions, rows and read-only history.\n");return 0;
}
fn collie_default_compiler() {
    let directory=h_dir(h_real("/proc/self/exe"));
    let names=h_args("flex-android","flex","flexscript","stage2",0,0);
    let roots=h_args(directory,h_join(directory,"../../../build"),0,0,0,0);
    let i=0;while i<h_count(roots) {
        let j=0;while j<h_count(names) {
            let candidate=h_join(h_at(roots,i),h_at(names,j));
            if syscall(21,candidate,1,0,0,0,0)==0 {return candidate;}
            j=j+1;
        }
        i=i+1;
    }
    return "../../build/flex-android";
}
fn collie_cli(argc,argv) {
    h_environment(argc,argv);
    if argc==3 && h_equal(load64(argv+8),"--adapter") {return collie_worker(load64(argv+16));}
    if argc==3 && h_equal(load64(argv+8),"--read-session") {return cu_read_session(load64(argv+16));}
    if argc==2 && h_equal(load64(argv+8),"--turn-worker") {
        let mask=h_take(8);store64(mask,0);syscall(14,2,mask,0,8,0,0);
        let text=c_read("/proc/self/fd/0",16777216);h_assert(text,"invalid turn request");let config=c_json(text);ce_enabled=1;return collie_loop(config);
    }
    let config=j_object();let model="";let replay="";let auth=0;
    let compiler=h_getenv("COLLIE_COMPILER");if !compiler {compiler=collie_default_compiler();}
    let prompt=0;let trace="";let trace_candidate=0;let max_steps=8;let stream=0;let i=1;let positional=0;let tui=0;let history="";let resume="";
    while i<argc {
        let arg=load64(argv+i*8);
        if !positional && h_equal(arg,"--help") {return collie_help();}
        if !positional && h_equal(arg,"--") {positional=1;}
        else if !positional && h_equal(arg,"--stream") {stream=1;}
        else if !positional && h_equal(arg,"--tui") {tui=1;}
        else if !positional && h_equal(arg,"--trace") {
            trace=h_absolute("collie-trace.json");trace_candidate=0;
            if i+1<argc && !h_starts(load64(argv+(i+1)*8),"--") {
                i=i+1;trace_candidate=load64(argv+i*8);trace=h_absolute(trace_candidate);
            }
        }else if !positional && h_starts(arg,"--trace=") {
            h_assert(h_len(arg+8)>0,"--trace= needs a filename");
            trace=h_absolute(arg+8);trace_candidate=0;
        }
        else if !positional && h_starts(arg,"--") {
            h_assert(i+1<argc,"option needs a value");i=i+1;let value=load64(argv+i*8);
            if h_equal(arg,"--model") {model=value;}
            else if h_equal(arg,"--replay") {replay=h_absolute(value);}
            else if h_equal(arg,"--auth-file") {auth=h_absolute(value);}
            else if h_equal(arg,"--compiler") {compiler=value;}
            else if h_equal(arg,"--max-steps") {max_steps=h_number(value);}
            else if h_equal(arg,"--history-dir") {history=h_absolute(value);tui=1;}
            else if h_equal(arg,"--resume") {resume=value;tui=1;}
            else if h_equal(arg,"--workspace") {j_set(config,"workspace_file",j_string(h_absolute(value)));}
            else if h_equal(arg,"--context-window") {let n=h_number(value);h_assert(n>0 && n<=1000000000,"invalid context window");j_set(config,"model_context_window",j_int(n));}
            else if h_equal(arg,"--auto-compact") {let n=h_number(value);h_assert(n>0 && n<=1000000000,"invalid auto-compact limit");j_set(config,"model_auto_compact_token_limit",j_int(n));}
            else {h_die("unknown Collie option");}
        }else {h_assert(!prompt,"pass the task as one quoted argument");prompt=arg;}
        i=i+1;
    }
    // With no other task, the argument after bare --trace is the task. This
    // supports both --trace 'task' and the existing --trace PATH 'task' syntax.
    if !prompt && trace_candidate {prompt=trace_candidate;trace=h_absolute("collie-trace.json");}
    if !prompt {tui=1;prompt="";}else {h_assert(h_len(prompt)>0 && h_len(prompt)<=16384,"task must contain 1..16384 bytes");}
    let default_model=!h_len(model);if default_model {model="gpt-6.1-sol";}
    h_assert(max_steps>=1 && max_steps<=32,"--max-steps must be 1..32");
    compiler=h_real(h_executable(compiler));
    h_assert(syscall(21,h_executable("bwrap"),1,0,0,0,0)==0,"Bubblewrap (bwrap) is required");
    h_assert(syscall(21,h_executable("prlimit"),1,0,0,0,0)==0,"prlimit is required");
    if !auth {auth=co_auth_path();}
    j_set(config,"prompt",j_string(prompt));j_set(config,"model",j_string(model));
    j_set(config,"auth_file",j_string(auth));j_set(config,"compiler",j_string(compiler));
    j_set(config,"max_steps",j_int(max_steps));j_set(config,"replay",j_string(replay));
    j_set(config,"trace_file",j_string(trace));j_set(config,"stream",j_bool(stream));
    j_set(config,"history_dir",j_string(history));j_set(config,"resume",j_string(resume));
    if default_model && !h_len(replay) {
        let request=j_object();j_set(request,"config",config);let result=collie_adapter(config,"auth",request);let error=j_get(result,"error");
        if error {h_print(2,h_cat3("Collie: ",j_value(error),"\n"));return 1;}
    }
    if tui {return collie_tui(config);}return collie_loop(config);
}
