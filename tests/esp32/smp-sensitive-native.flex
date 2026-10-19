import "../../scripts/lib/host.flex";
import "../../lib/net/smp-durable.flex";
import "smp-sensitive-fixture.flex";
fn sk_allocate(n) {return alloc(n);}
fn sk_report(point) {h_print(2,h_cat3("SMP SENSITIVE FAIL ",h_int(point),"\n"));return 0;}
fn dc_report(a,b,c,d,e) {return 0;}
fn main() {let r=sk_run();if r {return r;}h_print(1,h_cat3("PASS: SMP sensitive ",h_int(sk_checks)," independent observations\n"));return 0;}
