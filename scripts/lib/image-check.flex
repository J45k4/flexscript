// Independent system decoder for owned image fixtures; no window/GUI context.
import "host.flex";
import "../../libs/image.flex";
fn ic_jpeg(path){
    let data=h_read(path);let bytes=h_file_size;h_assert(bytes>=4&&load8(data)==255&&load8(data+1)==216,"Expected an actual JPEG stream");let context=image_context();let image=image_decode(context,data,bytes);h_assert(image,image_error(context));let width=image_width(image);let height=image_height(image);h_assert(width>0&&height>0&&image_pixels(image),"JPEG did not decode to actual pixels");let result=h_take(16);store64(result,width);store64(result+8,height);image_free(image);image_context_free(context);return result;
}
