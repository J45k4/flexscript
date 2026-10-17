import "../../scripts/lib/host.flex";
import "../../lib/net/smp-durable.flex";
import "smp-durable-max-body.flex";
fn dm_allocate(n) {return alloc(n);}
fn dm_release(p) {return 0;}
fn dm_arena_clean() {return 1;}
fn main(argc,argv) {h_environment(argc,argv);let r=dm_run();h_print(1,h_cat3("SMP durable-max status=",h_int(r),h_cat3(" checks=",h_int(dm_checks),"\n")));return r;}
