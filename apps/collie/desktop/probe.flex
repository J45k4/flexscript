// Opt-in replay diagnostics. No timer, sampling thread or file polling is added
// to ordinary application execution. A native_probe request is consumed once,
// after event handling/drawing and before the existing event wait.
global cd_probe_path=0;
// Opt-in terminal timing logs carry only a panel ID and cursor coordinates.
global cd_trace_terminal=0;
fn cd_terminal_trace_at(kind,id,x,y,started){
    if !cd_trace_terminal || !id{return 0;}
    if !started{started=gui_monotonic_ns();}let row=j_object();j_set(row,"trace",j_string("terminal"));j_set(row,"event",j_string(kind));j_set(row,"time_ns",j_int(started));j_set(row,"id",j_int(id));j_set(row,"x",j_int(x));j_set(row,"y",j_int(y));h_print(2,h_cat(j_dump(row),"\n"));return 0;
}
fn cd_terminal_trace(kind,id,x,y){return cd_terminal_trace_at(kind,id,x,y,0);}
fn cd_probe_clock(clock,scratch){h_assert(syscall(228,clock,scratch,0,0,0,0)==0,"Cannot sample diagnostic clock");return load64(scratch)*1000000000+load64(scratch+8);}
fn cd_probe_gpu(window){if gui__native{return gr_gl(load64(gui__record(window)+8),46,0x1f01,0,0,0,0,0);}if !gui__call("SDL_GL_GetCurrentContext",0,0,0,0,0,0){return "";}let get=gui__call("SDL_GL_GetProcAddress","glGetString",0,0,0,0,0);if !get{return "";}let name=ffi_call(get,0x1f01,0,0,0,0,0);if !name{return "";}return name;}
fn cd_probe_report(window,path,iterations,waits,source_wakes,zero_waits){
    let scratch=alloc(16);let now=cd_probe_clock(1,scratch);let process=cd_probe_clock(2,scratch);let thread=cd_probe_clock(3,scratch);syscall(11,scratch,16,0,0,0,0);
    let metrics=j_array();let i=0;while i<16{j_push(metrics,j_int(gui_metrics_value(i)));i=i+1;}
    let row=j_object();j_set(row,"backend",j_string(gui_backend_name()));j_set(row,"monotonic_ns",j_int(now));j_set(row,"process_cpu_ns",j_int(process));j_set(row,"thread_cpu_ns",j_int(thread));j_set(row,"iterations",j_int(iterations));j_set(row,"waits",j_int(waits));j_set(row,"source_wakes",j_int(source_wakes));j_set(row,"zero_waits",j_int(zero_waits));j_set(row,"metrics",metrics);j_set(row,"focused",j_bool(gui_focused(window)));j_set(row,"caret_animated",j_bool(ud_caret_animated()));j_set(row,"dirty",j_bool(ud_dirty));let focus="";if ud_focus{focus=load64(ud_focus);}j_set(row,"focus_key",j_string(focus));j_set(row,"width",j_int(gui_width(window)));j_set(row,"height",j_int(gui_height(window)));j_set(row,"pixel_width",j_int(gui_pixel_width(window)));j_set(row,"pixel_height",j_int(gui_pixel_height(window)));j_set(row,"scale",j_int(gui_scale(window)));
    let terminal=cd_workspace_terminal();if terminal{let panel=cd_terminal_panel(j_parse(cd_state),terminal);j_set(row,"terminal_id",j_int(terminal));j_set(row,"terminal_cursor_x",j_int(cj_int(panel,"cursor_x")));j_set(row,"terminal_cursor_y",j_int(cj_int(panel,"cursor_y")));j_set(row,"terminal_output_hash",j_int(ui_hash(cj_text(panel,"output"))));}
    let info=gui_renderer_info(window);h_assert(info,gui_error);j_set(row,"renderer",j_string(load64(info)));j_set(row,"renderer_flags",j_int(gui__u32(info+8)));j_set(row,"gpu_renderer",j_string(cd_probe_gpu(window)));
    if gui__native{
        let p=gui__record(window);let g=load64(p+8);let texture=load64(g+232);let count=0;let bytes=0;
        while texture{let channels=4;if load64(texture+32)==3{channels=1;}bytes=bytes+load64(texture+8)*load64(texture+16)*channels;count=count+1;texture=load64(texture+48);}
        j_set(row,"texture_count",j_int(count));j_set(row,"texture_storage_bytes",j_int(bytes));j_set(row,"draw_batches",j_int(load64(g+240)));let atlas=load64(p+680);let pages=0;let atlas_bytes=0;i=0;while atlas && i<4{let page=atlas+128+i*64;if load64(page){pages=pages+1;let channels=1;if load64(page+8)==4{channels=4;}atlas_bytes=atlas_bytes+1024*1024*channels;}i=i+1;}j_set(row,"atlas_pages",j_int(pages));j_set(row,"atlas_storage_bytes",j_int(atlas_bytes));if gn_shapes{j_set(row,"shape_cache_bytes",j_int(load64(gn_shapes+8)));let transient=load64(gn_shapes+48);let transient_bytes=0;if transient{transient_bytes=load64(transient+48);}j_set(row,"shape_transient_bytes",j_int(transient_bytes));}
    }
    h_save(path,j_dump(row));return 0;
}
