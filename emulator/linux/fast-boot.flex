import "../../scripts/lib/build.flex";
// Extract only the compressed payload described by this exact bzImage.
// Output lives in the caller's directory; never reuse a different kernel.
fn fast_kernel_u32(p) {return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn fast_kernel(kernel,dir) {
    let image=h_read(kernel);let size=h_file_size;
    h_assert(size>=0x250,"Truncated bzImage");
    let sectors=load8(image+0x1f1);if !sectors {sectors=4;}
    let offset=(sectors+1)*512+fast_kernel_u32(image+0x248);let length=fast_kernel_u32(image+0x24c);
    h_assert(offset<=size && length>8 && length<=size-offset && fast_kernel_u32(image+offset)==0xfd2fb528,"Expected a zstd-compressed bzImage payload for --fast-boot");
    let expected=fast_kernel_u32(image+offset+length-4);
    h_assert(expected>=64 && expected<=1073741824,"Invalid decompressed kernel size");
    let compressed=h_join(dir,"kernel.zst");h_save_bytes(compressed,image+offset,length-4,384);
    let output=h_join(dir,"vmlinux");
    h_print(1,"Decompressing the matching kernel on the host for faster CPU iteration.\n");
    h_ok(h_args("zstd","--decompress","--force","-o",output,compressed));
    let fd=syscall(2,output,0,0,0,0,0);h_assert(fd>=0,"Cannot read decompressed kernel");
    let actual=syscall(8,fd,0,2,0,0,0);h_close(fd);
    h_assert(actual==expected,"Decompressed kernel size mismatch");return output;
}
