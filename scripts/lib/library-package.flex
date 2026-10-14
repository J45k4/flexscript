import "build.flex";
fn lp_bundle(dist,version) {
    h_assert(b_valid_version(version),"invalid library version");h_mkdir(dist);
    let name=h_cat3("flexscript-libraries-",version,".tar.gz");
    let args=h_args("tar","--sort=name","--mtime=@0","--owner=0","--group=0","--numeric-owner");
    h_add(args,"-czf");h_add(args,h_join(dist,name));
    h_add(args,"VERSION");h_add(args,"libs");h_add(args,"lib");h_add(args,"examples/monolith");h_add(args,"docs/monolith.md");
    h_add(args,"scripts/install.flex");h_add(args,"scripts/lib/build.flex");h_add(args,"scripts/lib/json.flex");h_add(args,"scripts/lib/host.flex");
    h_ok(args);return name;
}
