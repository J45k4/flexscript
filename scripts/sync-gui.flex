// Run from the Flexscript root. A standalone app vendors this library snapshot;
// updates originate here, never in the application's platform copy.
import "lib/json.flex";
fn main(argc,argv) {
    h_environment(argc,argv);
    h_assert(argc==2 || (argc==3 && h_equal(load64(argv+16),"--check")),"Usage: sync-gui PLATFORM-DIRECTORY [--check]");
    let target=load64(argv+8);let checking=argc==3;
    h_assert(h_isdir(target),"Platform directory must already exist");
    let files=j_object();let index=0;
    while index<4 {
        let name="gui.flex";let source="libs/gui.flex";
        if index==1 {name="gui/window.flex";source="libs/gui/window.flex";}
        if index==2 {name="gui/canvas.flex";source="libs/gui/canvas.flex";}
        if index==3 {name="gui/gl.flex";source="libs/gui/gl.flex";}
        let dest=h_join(target,name);let content=h_read(source);
        let digest=h_out(h_check(h_run(h_args("sha256sum",source,0,0,0,0)),0,0));
        h_assert(h_len(digest)>=64,"SHA256 result is truncated");store8(digest+64,0);
        j_set(files,name,j_string(digest));
        if checking {h_assert(h_equal(content,h_read(dest)),h_cat("GUI snapshot differs: ",name));}
        else {h_mkdir(h_join(target,"gui"));h_save(dest,content);}
        index=index+1;
    }
    let metadata=j_object();j_set(metadata,"library",j_string("Flexscript libs/gui"));
    j_set(metadata,"source",j_string("https://github.com/J45k4/flexscript"));
    j_set(metadata,"snapshot",j_string("Workspace source snapshot; SHA256 pins each file"));
    j_set(metadata,"files",files);let provenance=h_join(target,"gui-provenance.json");
    if checking {
        let stored=j_parse(h_read(provenance));
        h_assert(h_equal(j_dump(stored),j_dump(metadata)),"GUI provenance differs; sync the snapshot");
    }else {j_save(provenance,metadata);}
    h_print(1,"GUI library snapshot verified.\n");return 0;
}
