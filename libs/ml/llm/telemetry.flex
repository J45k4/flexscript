// Read-only AMD driver telemetry, sampled by the UI (never launches GPU work).
// Device-wide activity is distinct from the model's launch/wave configuration.
import "../../../lib/hip.flex";
import "../../tui/tui.flex";
import "../../../scripts/lib/json.flex";
global lt_enabled=0;
global lt_preferred_width=34;
global lt_path=0;
global lt_hwmon=0;
global lt_device=0;
global lt_backend=0;
global lt_name=0;
global lt_read_buffer=0;
global lt_busy=-1;
global lt_mem_busy=-1;
global lt_vram_used=-1;
global lt_vram_total=-1;
global lt_temperature=-1;
global lt_hotspot=-1;
global lt_power=-1;
global lt_power_cap=-1;
global lt_clock=-1;
global lt_memory_clock=-1;
global lt_samples=0;
global lt_rates=0;
global lt_sample_count=0;
global lt_last_tick=0;
global lt_output_tokens=0;
global lt_previous_tokens=0;
global lt_first_tick=0;
global lt_request_tick=0;
global lt_first_ms=-1;
global lt_decode_x10=0;
global lt_wave_size=0;
global lt_workers=0;
global lt_worker_threads=0;
global lt_resident_bytes=0;
global lt_os_history=0;
global lt_os_count=0;
global lt_os_token=0;
global lt_os_duration=0;
global lt_os_work=0;
global lt_os_minimum=0;
global lt_os_maximum=0;
fn lt_profile_reset() {lt_os_count=0;lt_os_token=0;lt_os_duration=0;lt_os_work=0;return 0;}
fn lt_profile(records) {
    if !lt_os_history {lt_os_history=h_take(8*64*8);}let i=0;
    while i<j_count(records) {let e=j_at(records,i);let token=j_n(e,"token");if token>lt_os_token {
        let categories=j_need(e,"categories_x10");h_assert(j_count(categories)==7,"invalid GPU worker profile");let k=0;
        while k<7 {let value=j_value(j_at(categories,k));if value<0 {value=0;}if value>1000 {value=1000;}store64(lt_os_history+(k*64+lt_os_count%64)*8,value);k=k+1;}
        lt_os_work=j_n(e,"work_x10");lt_os_minimum=j_n(e,"worker_min_x10");lt_os_maximum=j_n(e,"worker_max_x10");
        store64(lt_os_history+(7*64+lt_os_count%64)*8,lt_os_work);lt_os_count=lt_os_count+1;lt_os_token=token;lt_os_duration=j_n(e,"duration_us");}
        i=i+1;}return 0;
}
fn lt_width() {let width=lt_preferred_width;let maximum=tu_cols-61;if width>maximum {width=maximum;}if width<26 {width=26;}return width;}
fn lt_resize(column) {lt_preferred_width=tu_cols-column;if lt_preferred_width<26 {lt_preferred_width=26;}if lt_preferred_width>tu_cols-61 {lt_preferred_width=tu_cols-61;}return 0;}
fn lt_graph_width() {let width=lt_width()-4;if width>64 {width=64;}return width;}
fn lt_visible() {return lt_enabled && tu_cols>=110 && tu_rows>=20;}
fn lt_columns() {if tu_clip {return tu_cols;}if lt_visible() {return tu_cols-lt_width()-1;}return tu_cols;}
fn lt_read(path) {
    if !path {return -1;}let fd=syscall(2,path,0x80800,0,0,0,0);if fd<0 {return -1;}
    let n=syscall(0,fd,lt_read_buffer,127,0,0,0);h_close(fd);if n<=0 {return -1;}store8(lt_read_buffer+n,0);
    let i=0;let value=0;while i<n && load8(lt_read_buffer+i)>=48 && load8(lt_read_buffer+i)<=57 {value=value*10+load8(lt_read_buffer+i)-48;i=i+1;}
    if !i {return -1;}return value;
}
fn lt_sensor(base,name) {if !base {return -1;}return lt_read(h_join(base,name));}
fn lt_init(device,backend) {
    lt_device=device;lt_backend=backend;lt_path=0;lt_hwmon=0;lt_name="GPU sensors unavailable";
    if !lt_read_buffer {lt_read_buffer=h_take(128);lt_samples=h_take(64*8);lt_rates=h_take(64*8);}
    lt_profile_reset();lt_sample_count=0;lt_last_tick=0;lt_busy=-1;lt_mem_busy=-1;lt_vram_used=-1;lt_vram_total=-1;lt_temperature=-1;lt_hotspot=-1;lt_power=-1;lt_power_cap=-1;lt_clock=-1;lt_memory_clock=-1;
    let fixture=h_getenv("FLEX_LLM_GPU_SYSFS");
    if fixture {lt_path=fixture;lt_name="GPU driver sensors";}
    else if h_equal(backend,"hip") || h_equal(backend,"rdna") {
        let bus=h_take(64);let ordinal=h_number(device);
        if !hip_call("hipDeviceGetPCIBusId",bus,64,ordinal,0,0,0) {let path=h_join("/sys/bus/pci/devices",bus);if h_exists(h_join(path,"gpu_busy_percent")) {lt_path=path;}}
        if lt_path {let name=hip_device_name(ordinal);if name {lt_name=name;}}
    }
    if lt_path && h_exists(h_join(lt_path,"hwmon")) {let entries=h_entries(h_join(lt_path,"hwmon"));let i=0;
        while i<h_count(entries) {let name=h_at(entries,i);if h_starts(name,"hwmon") {lt_hwmon=h_join(h_join(lt_path,"hwmon"),name);}i=i+1;}}
    return 0;
}
fn lt_tick(tick,busy) {
    if !lt_enabled || !lt_visible() {return 0;}if lt_last_tick && tick-lt_last_tick<500 {return 0;}
    let mark=tu_mark();
    lt_busy=lt_sensor(lt_path,"gpu_busy_percent");lt_mem_busy=lt_sensor(lt_path,"mem_busy_percent");
    lt_vram_used=lt_sensor(lt_path,"mem_info_vram_used");lt_vram_total=lt_sensor(lt_path,"mem_info_vram_total");
    lt_temperature=lt_sensor(lt_hwmon,"temp1_input");lt_hotspot=lt_sensor(lt_hwmon,"temp2_input");
    lt_power=lt_sensor(lt_hwmon,"power1_average");lt_power_cap=lt_sensor(lt_hwmon,"power1_cap");
    lt_clock=lt_sensor(lt_hwmon,"freq1_input");lt_memory_clock=lt_sensor(lt_hwmon,"freq2_input");
    let rate=0;if lt_last_tick && busy && lt_output_tokens>=lt_previous_tokens {rate=(lt_output_tokens-lt_previous_tokens)*10000/(tick-lt_last_tick);}
    if busy && lt_first_tick && tick>lt_first_tick {lt_decode_x10=(lt_output_tokens-1)*10000/(tick-lt_first_tick);}
    store64(lt_samples+(lt_sample_count%64)*8,lt_busy);store64(lt_rates+(lt_sample_count%64)*8,rate);lt_sample_count=lt_sample_count+1;
    lt_previous_tokens=lt_output_tokens;lt_last_tick=tick;tu_reset(mark);return 1;
}
fn lt_request(tick) {lt_profile_reset();lt_request_tick=tick;lt_first_tick=0;lt_first_ms=-1;lt_output_tokens=0;lt_previous_tokens=0;lt_decode_x10=0;return 0;}
fn lt_token(tick) {lt_output_tokens=lt_output_tokens+1;if !lt_first_tick {lt_first_tick=tick;lt_first_ms=tick-lt_request_tick;}return 0;}
fn lt_done(tokens,elapsed,first) {lt_first_ms=first/1000;lt_decode_x10=0;if tokens>1 && elapsed>first {lt_decode_x10=(tokens-1)*10000000/(elapsed-first);}return 0;}
fn lt_decimal(value,divisor) {if value<0 {return "n/a";}let tenths=value*10/divisor;return h_cat3(h_int(tenths/10),".",h_int(tenths%10));}
fn lt_unit(value,divisor,unit) {if value<0 {return "n/a";}return h_cat(h_int(value/divisor),unit);}
fn lt_percent(value) {if value<0 {return "n/a";}return h_cat(h_int(value),"%");}
fn lt_bar(value,total,width) {
    let filled=0;if value>=0 && total>0 {filled=value*width/total;}if filled>width {filled=width;}if filled<0 {filled=0;}
    if value<0 || total<=0 {return h_repeat("·",width);}return h_cat(h_repeat("█",filled),h_repeat("░",width-filled));
}
fn lt_spark_count(samples,width,maximum,sample_count) {
    let out=h_buffer();let count=sample_count;if count>width {count=width;}let first=sample_count-count;let i=0;
    if maximum<=0 {maximum=1;while i<count {let v=load64(samples+((first+i)%64)*8);if v>maximum {maximum=v;}i=i+1;}}
    h_text(out,h_repeat("·",width-count));i=0;let blocks="▁▂▃▄▅▆▇█";
    while i<count {let value=load64(samples+((first+i)%64)*8);if value<0 {h_text(out,"·");}else {let level=value*7/maximum;if level>7 {level=7;}h_append(out,blocks+level*3,3);}i=i+1;}return h_data(out);
}
fn lt_spark(samples,width,maximum) {return lt_spark_count(samples,width,maximum,lt_sample_count);}
fn lt_profile_value(kind) {return load64(lt_os_history+(kind*64+(lt_os_count-1)%64)*8);}
fn lt_profile_percent(value) {return h_cat(lt_decimal(value,10),"%");}
fn lt_profile_track(out,row,kind,name,color) {
    lt_put(out,row,h_cat3(name," ",lt_profile_percent(lt_profile_value(kind))),color);
    lt_put(out,row+1,lt_spark_count(lt_os_history+kind*64*8,lt_graph_width(),1000,lt_os_count),color);return 0;
}
fn lt_profile_draw(out) {
    lt_put(out,20,"GPU OS SELF PROFILE","1;36");lt_put(out,21,h_cat3("Token ",h_int(lt_os_token),h_cat(" | ",lt_unit(lt_os_duration,1," us"))),"90");
    lt_put(out,22,h_cat3("Work ",lt_profile_percent(lt_os_work),h_cat3(" | ",lt_profile_percent(lt_os_minimum),h_cat("–",lt_profile_percent(lt_os_maximum)))),"32");
    lt_put(out,23,h_cat3("Matrix ",lt_percent(lt_profile_value(0)/10),h_cat(" | Attn ",lt_percent(lt_profile_value(1)/10))),"36");
    lt_put(out,24,h_cat3("Sync ",lt_percent(lt_profile_value(6)/10),h_cat(" | Sample ",lt_percent(lt_profile_value(5)/10))),"33");
    lt_put(out,25,h_cat3("Worker 0 • last ",h_int(lt_graph_width())," tokens →"),"90");
    lt_profile_track(out,26,0,"Matrix","36");lt_profile_track(out,28,1,"Attention","35");lt_profile_track(out,30,6,"Grid wait","33");
    lt_profile_track(out,32,5,"Sampling","32");lt_profile_track(out,34,2,"Normalization","36");lt_profile_track(out,36,3,"Rotary","35");
    lt_profile_track(out,38,4,"Elementwise","36");lt_profile_track(out,40,7,"Worker work","32");
    lt_put(out,42,"Stage %: worker 0 timings.","90");lt_put(out,43,"Work includes local sync.","90");lt_put(out,44,"Wave occupancy n/a","90");return 0;
}
fn lt_put(out,row,text,color) {
    if row>tu_rows {return 0;}let left=tu_cols-lt_width()+1;tu_pos(out,row,left);h_text(out,h_cat3(tu_escape,"[",h_cat(h_int(lt_width()),"X")));
    h_text(out,h_cat3(tu_escape,"[",h_cat(color,"m")));let i=0;let column=0;
    while load8(text+i) && column<lt_width()-1 {let next=tu_next(text,i);let width=tu_width(tu_code(text,i));if column+width<=lt_width()-1 {h_append(out,text+i,next-i);}column=column+width;i=next;}
    h_text(out,h_cat(tu_escape,"[0m"));return 0;
}
fn lt_draw(out,runtime,stage,context_used,context_limit,demo) {
    if !lt_visible() {return 0;}let row=1;while row<=tu_rows {tu_pos(out,row,tu_cols-lt_width());h_text(out,tu_ansi("@[90m│@[0m"));lt_put(out,row,"","0");row=row+1;}
    lt_put(out,1,"GPU MONITOR  ↔ drag divider","1;36");lt_put(out,2,lt_name,"90");lt_put(out,3,h_cat("Device-wide | ",stage),"90");
    lt_put(out,5,h_cat("GPU busy     ",lt_percent(lt_busy)),"1;36");lt_put(out,6,lt_bar(lt_busy,100,lt_graph_width()),"36");lt_put(out,7,lt_spark(lt_samples,lt_graph_width(),100),"36");
    lt_put(out,8,h_cat("Memory busy  ",lt_percent(lt_mem_busy)),"35");
    let vram="VRAM         n/a";if lt_vram_used>=0 && lt_vram_total>0 {vram=h_cat3("VRAM ",lt_decimal(lt_vram_used,1073741824),h_cat3(" / ",lt_decimal(lt_vram_total,1073741824)," GiB"));}
    lt_put(out,9,vram,"1;35");lt_put(out,10,lt_bar(lt_vram_used,lt_vram_total,lt_graph_width()),"35");
    lt_put(out,11,h_cat3("Temp ",lt_unit(lt_temperature,1000,"°C"),h_cat(" | hotspot ",lt_unit(lt_hotspot,1000,"°C"))),"33");
    lt_put(out,12,h_cat3("Power ",lt_unit(lt_power,1000000," W"),h_cat(" / ",lt_unit(lt_power_cap,1000000," W"))),"33");
    lt_put(out,13,h_cat3("Core ",lt_unit(lt_clock,1000000,"MHz"),h_cat(" | mem ",lt_unit(lt_memory_clock,1000000,"MHz"))),"90");
    let unit=" tok/s";if demo {unit=" chars/s";}lt_put(out,15,h_cat3("Decode ",lt_decimal(lt_decode_x10,10),unit),"1;32");lt_put(out,16,lt_spark(lt_rates,lt_graph_width(),0),"32");
    lt_put(out,17,h_cat("First token ",lt_unit(lt_first_ms,1," ms")),"90");let context="Context      n/a";
    if context_used>=0 && context_limit>0 {context=h_cat3("Context ",h_int(context_used),h_cat(" / ",h_int(context_limit)));}
    lt_put(out,18,context,"36");lt_put(out,19,lt_bar(context_used,context_limit,lt_graph_width()),"36");if lt_os_count && h_equal(runtime,"gpu-os") {return lt_profile_draw(out);}lt_put(out,20,h_cat("Runtime ",runtime),"90");
    let waves="Wave launch  n/a";if lt_workers && lt_wave_size && lt_worker_threads {waves=h_cat3(h_int(lt_workers)," workers | ",h_cat(h_int(lt_worker_threads/lt_wave_size)," waves/worker"));}
    lt_put(out,21,waves,"90");lt_put(out,22,"Wave occupancy  n/a","90");lt_put(out,23,"Needs profiling counters","90");
    lt_put(out,24,h_cat3("Model ",lt_decimal(lt_resident_bytes,1073741824)," GiB resident"),"90");return 0;
}
