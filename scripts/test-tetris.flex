import "lib/build.flex";
import "lib/pty.flex";
fn main(argc,argv) {
    h_environment(argc,argv);
    let compiler=h_real(b_option(argc,argv,"--compiler","build/flex"));
    h_mkdir("build");
    let binary=h_absolute("build/tetris");
    h_compile(compiler,"examples/tetris.flex",binary);
    let rules=h_check(h_run(h_args(binary,"--self-test",0,0,0,0)),0,0);
    h_assert(h_has(h_out(rules),"85 checks, 0 failures"),h_out(rules));
    h_print(1,h_out(rules));
    h_assert(h_has(h_out(h_ok(h_args(binary,"--help",0,0,0,0))),"Space: hard drop"),"Tetris help");
    let p=h_check(h_run(h_args(binary,0,0,0,0,0)),1,0);
    h_assert(h_has(h_out(p),"interactive terminal"),"Tetris non-TTY diagnostic");
    let escape=h_take(2);
    store8(escape,27);
    store8(escape+1,0);
    p=hp_open(binary);
    h_until(p,"FLEXSCRIPT TETRIS",3000);
    h_assert(h_has(h_out(p),h_cat(escape,"[?1049h")) && h_has(h_out(p),h_cat(escape,"[?25l")),"Tetris terminal setup");
    let attributes=h_zero(h_take(64),64);
    syscall(16,load64(p+96),0x5401,attributes,0,0,0);
    h_assert((load64(attributes+8)>>32&10)==0,"terminal is canonical or echoing");
    hp_send(p,"p");
    h_until(p,"PAUSED",3000);
    hp_send(p,"p");
    h_until(p,"marks the landing spot",3000);
    let out=h_out(p);
    let at=0;
    let frame=out;
    while load8(out+at) {
        if h_starts(out+at,h_cat(escape,"[2J")) {
            frame=out+at;
        }
        at=at+1;
    }
    h_assert(!h_has(frame,"PAUSED"),"Tetris did not resume");
    hp_send(p,escape);
    hp_send(p,"[D");
    hp_send(p,"s ");
    h_until(p,"SCORE",3000);
    at=0;
    let last=-1;
    while load8(h_out(p)+at) {
        if h_starts(h_out(p)+at,"SCORE  ") {
            last=at;
        }
        at=at+1;
    }
    h_assert(last>=0,"score missing");
    at=last+7;
    let n=0;
    while load8(h_out(p)+at)>=48 && load8(h_out(p)+at)<=57 {
        n=n*10+load8(h_out(p)+at)-48;
        at=at+1;
    }
    h_assert(n>0,"hard drop did not score");
    hp_send(p,"r");
    h_until(p,"SCORE  0",3000);
    hp_resize(p,12,40);
    hp_clear(p);
    h_until(p,"enlarge to 58 x 24",3000);
    hp_resize(p,24,80);
    hp_clear(p);
    h_until(p,"FLEXSCRIPT TETRIS",3000);
    hp_finish(p,"q",0);
    let i=0;
    while i<3 {
        p=hp_open(binary);
        h_until(p,"FLEXSCRIPT TETRIS",3000);
        let signal=0;
        let keys=0;
        if i==0 {
            keys=h_take(2);
            store8(keys,3);
            store8(keys+1,0);
        }else if i==1 {
            signal=15;
        }else {
            signal=2;
        }
        hp_finish(p,keys,signal);
        i=i+1;
    }
    h_print(1,"Terminal checks passed: controls, resize, Q/Ctrl-C/signals and exact restoration.\n");
    return 0;
}
