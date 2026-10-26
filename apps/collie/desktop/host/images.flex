// Collie's image policy uses the reusable native image pipeline. Codec libraries
// are isolated in libs/image; no GDK Pixbuf, GObject or GLib image calls here.
import "system.flex";
import "../../../../libs/image.flex";
global si_native_context=0;
fn si_context(){if !si_native_context{si_native_context=image_context();}if !si_native_context{return sh_fail("Cannot initialize image processing");}return si_native_context;}
fn si_shutdown(){image_context_free(si_native_context);si_native_context=0;return 0;}
fn si_image(root,bytes,n,limit){
    if n<1 || n>limit{return sh_fail("Image exceeds its input size limit");}
    let c=si_context();if !c{return 0;}let snapshot=image_preview(c,bytes,n,1536,524288);
    if !snapshot{return sh_fail(image_error(c));}
    let size=image_blob_size(snapshot);let key=h_sha_bytes(image_blob_data(snapshot),size);
    let dir=h_join(root,"images");h_mkdir(dir);let path=h_join(dir,h_cat(key,".jpg"));
    if !sh_atomic(path,image_blob_data(snapshot),size){image_blob_free(snapshot);return 0;}
    let out=j_object();sh_s(out,"type","image");sh_s(out,"image_id",key);
    sh_n(out,"width",image_blob_width(snapshot));sh_n(out,"height",image_blob_height(snapshot));
    sh_n(out,"bytes",size);sh_s(out,"mime","image/jpeg");image_blob_free(snapshot);return out;
}
