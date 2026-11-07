import "harness.flex";
fn ps_verify(source,status,message) {
    t_program(source);let before=h_sha(t_fixture);let p=h_run(h_args(t_compiler,"verify",t_fixture,0,0,0));
    if h_status(p)!=status {h_print(2,h_out(p));h_print(2,source);}
    h_check(p,status,0);t_assert(h_has(h_out(p),message),h_cat3(message,": ",h_out(p)));
    t_assert(h_equal(h_sha(t_fixture),before),"verification changed source");
    if status {t_assert(!h_has(h_out(p),"Verified roots: 1/1"),"failed single root reported proved");}
    return p;
}
fn ps_bad(source,message) {
    t_program(source);let p=h_run(h_args(t_compiler,"verify",t_fixture,0,0,0));
    h_check(p,1,0);t_assert(h_has(h_err(p),message),h_err(p));t_assert(t_location(h_err(p)),"missing verifier syntax location");
    t_reject(t_fixture,t_binary,message);return 0;
}
