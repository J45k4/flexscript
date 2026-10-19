import "../../scripts/lib/host.flex";
import "../../lib/net/smp-retry.flex";
import "smp-retry-bounds-body.flex";
fn main(argc,argv) {h_environment(argc,argv);let r=rb_run();h_print(1,h_cat3("SMP retry32 status=",h_int(r),h_cat3(" checks=",h_int(rb_checks),"\n")));return r;}
