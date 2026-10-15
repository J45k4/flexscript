import "../../lib/net/civil-time.flex";
import "civil-time-vectors.flex";
fn main() {let cases=cv_data();let out=alloc(44);store64(out+36,0x123456789abcdef0);let i=0;while i<128 {let p=cases+i*44;if ct_gmtime(load64(p),out,36)!=out {return 1;}let j=0;while j<36 {if load8(out+j)!=load8(p+8+j) {return 2;}j=j+1;}if load64(out+36)!=0x123456789abcdef0 {return 3;}i=i+1;}if ct_gmtime(-1,out,36) || ct_gmtime(253402300800,out,36) || ct_gmtime(0,out,35) || ct_gmtime(0,0,36) {return 4;}return 0;}
