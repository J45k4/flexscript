// Real loopback transport fixture. It never contacts a user's browser.
import "cdp.flex";
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==3 || argc==4,"Usage: cdp-http PORT DEADLINE_MS [OWNED_CHILD]");
    cd_port=h_number(load64(argv+8));
    if argc==4{cd_chrome=h_spawn(h_args(load64(argv+24),0,0,0,0,0),"",0);}
    let body=cd_http_timeout("/fixture",h_number(load64(argv+16)));
    if cd_chrome{h_stop(cd_chrome);}h_print(1,body);return 0;
}
