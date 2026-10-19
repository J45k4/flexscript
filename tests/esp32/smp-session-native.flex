import "../../scripts/lib/host.flex";
import "../../lib/net/smp-session.flex";
import "smp-session-fixture.flex";
fn oc_report(case_number,step,byte,actual,expected) {h_print(2,h_cat3("SMP OWNER FAIL case=",h_int(case_number),h_cat3(" step=",h_int(step),h_cat3(" offset=",h_int(byte),h_cat3(" actual=",h_int(actual),h_cat3(" expected=",h_int(expected),"\n"))))));return 0;}
fn main(argc,argv) {h_environment(argc,argv);let data=h_read(load64(argv+8));let size=h_file_size;let r=oc_run(data,size);if r {return r;}h_print(1,h_cat3("PASS: SMP owner ",h_int(oc_checks)," independent observations\n"));return 0;}
