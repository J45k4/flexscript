import "lib/signing.flex";
fn main(argc,argv) {
    h_environment(argc,argv);
    let version=b_option(argc,argv,"--version",b_version());
    let dist=b_option(argc,argv,"--dist-dir","dist");
    sg_sign(h_absolute(dist),version);
    h_print(1,h_cat3("Signed Flexscript ",version," Linux x86-64 release checksums (Ed25519).\n"));
    return 0;
}
