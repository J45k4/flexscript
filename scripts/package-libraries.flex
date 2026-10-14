// Development bundle; release packaging additionally verifies bootstrap state.
import "lib/library-package.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let dist=b_option(argc,argv,"--dist-dir","dist");let name=lp_bundle(dist,b_version());
    h_print(1,h_cat3("Bundled ",h_join(dist,name),"\n"));return 0;
}
