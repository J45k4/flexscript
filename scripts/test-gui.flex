import "lib/harness.flex";
global test_gui_display=0;
fn suite(compiler) {
    t_init(compiler);let root=h_absolute(".");let library=h_join(t_work,"events.so");
    let args=h_args("cc","-shared","-fPIC","-O2","tests/gui/events.c","-o");h_add(args,library);h_add(args,"-ldl");h_ok(args);
    h_compile(t_compiler,"tests/gui/window.flex",t_binary);
    let env=h_env;h_setenv("SDL_VIDEODRIVER","dummy");
    let result=h_check(h_run(h_args(t_binary,library,0,0,0,0)),0,0);h_print(1,h_out(result));
    t_assert(h_has(h_out(result),"checks passed"),"headless GUI integration");
    h_setenv("SDL_VIDEODRIVER","flexscript-no-such-driver");
    result=h_check(h_run(h_args(t_binary,library,"--failure",0,0,0)),0,0);h_print(1,h_out(result));
    t_assert(h_has(h_out(result),"unavailable-display checks passed"),"display failure explained");
    h_setenv("SDL_VIDEODRIVER","dummy");
    let example=h_join(t_work,"example");h_compile(t_compiler,"examples/gui/window.flex",example);
    h_check(h_run(h_args(example,"3",0,0,0,0)),0,0);t_checks=t_checks+1;
    let gl=h_join(t_work,"opengl");h_compile(t_compiler,"examples/gui/opengl.flex",gl);t_checks=t_checks+1;
    let compat=h_join(t_work,"compat");h_compile(t_compiler,"tests/gui/compat.flex",compat);
    h_check(h_run(h_args(compat,0,0,0,0,0)),0,0);t_checks=t_checks+1;
    if test_gui_display {
        // Live acceptance is explicit and never silently skipped on failure.
        h_env=env;h_setenv("SDL_VIDEODRIVER","x11");
        result=h_check(h_run(h_args(t_binary,library,"--gl",0,0,0)),0,0);h_print(1,h_out(result));t_checks=t_checks+1;
        let display=h_join(t_work,"display");h_compile(t_compiler,"tests/gui/display.flex",display);
        result=h_run(h_args(display,example,gl,library,0,0));h_print(1,h_out(result));h_check(result,0,0);t_checks=t_checks+1;
    }
    h_env=env;return t_done();
}
fn main(argc,argv) {
    h_environment(argc,argv);let compiler="build/flex";let report=0;let i=1;
    while i<argc {
        let arg=load64(argv+i*8);
        if h_equal(arg,"--gui") {test_gui_display=1;}
        else if h_equal(arg,"--report") {i=i+1;h_assert(i<argc,"--report needs a path");report=load64(argv+i*8);}
        else {compiler=arg;}i=i+1;
    }
    let checks=suite(compiler);
    if report {let item=j_object();j_set(item,"compiler",j_string(h_absolute(compiler)));j_set(item,"checks",j_int(checks));j_set(item,"display",j_int(test_gui_display));j_save(report,item);}return 0;
}
