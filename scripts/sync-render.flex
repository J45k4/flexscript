// Standalone applications vendor a pinned library snapshot, like sync-gui.
import "lib/json.flex";
fn main(argc,argv) {
    h_environment(argc,argv);h_assert(argc==2 || (argc==3 && h_equal(load64(argv+16),"--check")),"Usage: sync-render PLATFORM-DIRECTORY [--check]");
    let target=load64(argv+8);let checking=argc==3;h_assert(h_isdir(target),"Platform directory must exist");
    let sources=h_args("libs/render.flex","libs/render/device.flex","libs/render/numeric.flex","libs/render/camera.flex","libs/render/scene.flex","lib/ffi-words.flex");
    h_add(sources,"libs/render/shaders/water-vertex.seta");h_add(sources,"libs/render/shaders/water-fragment.seta");h_add(sources,"libs/render/shaders/atmosphere-vertex.seta");h_add(sources,"libs/render/shaders/atmosphere-fragment.seta");
    let files=j_object();let i=0;while i<h_count(sources) {
        let source=h_at(sources,i);let name=h_slice(source+5,h_len(source)-5);if i==5 {name="ffi-words.flex";}
        let content=h_read(source);let original=h_sha_bytes(content,h_len(content));
        if i==4 {content=h_replace(content,"../../lib/ffi-words.flex","../ffi-words.flex");}
        let digest=h_sha_bytes(content,h_len(content));let entry=j_object();
        j_set(entry,"upstreamPath",j_string(source));j_set(entry,"upstreamSha256",j_string(original));j_set(entry,"sha256",j_string(digest));j_set(files,name,entry);
        let dest=h_join(target,name);if checking {h_assert(h_equal(content,h_read(dest)),h_cat("Renderer snapshot differs: ",name));}
        else {h_mkdir(h_join(target,"render/shaders"));h_save(dest,content);}i=i+1;
    }
    let meta=j_object();j_set(meta,"library",j_string("Flexscript libs/render"));j_set(meta,"source",j_string("https://github.com/J45k4/flexscript"));j_set(meta,"snapshot",j_string("Workspace source snapshot; SHA256 pins each file. Only the word FFI import is relocated."));j_set(meta,"files",files);
    let provenance=h_join(target,"render-library-provenance.json");if checking {h_assert(h_equal(j_dump(j_parse(h_read(provenance))),j_dump(meta)),"Renderer provenance differs");}else {j_save(provenance,meta);}
    h_print(1,"Renderer library snapshot verified.\n");return 0;
}
