// Bounded ZIP/JAR/APK transport for native host tools. zlib supplies compression;
// archive validation, names, ownership and packaging remain ordinary Flexscript.
import "host.flex";
global az_library=0;
fn az_z(name){if !az_library{az_library=ffi_open("libz.so.1");h_assert(az_library,"Host ZIP tooling needs zlib");}let p=ffi_symbol(az_library,name);h_assert(p,h_cat("Missing zlib function: ",name));return p;}
fn az_u16(p){return load8(p)|(load8(p+1)<<8);}
fn az_u32(p){return az_u16(p)|(az_u16(p+2)<<16);}
fn az_p16(p,n){store8(p,n);store8(p+1,n>>8);return p;}
fn az_p32(p,n){az_p16(p,n);az_p16(p+2,n>>16);return p;}
fn az_name(name){
    let n=h_len(name);if !n||n>4096||load8(name)==47{return 0;}let start=0;let i=0;
    while i<=n{let c=load8(name+i);if c==92||(c>0&&c<32){return 0;}if !c||c==47{let size=i-start;if !size||(size==1&&load8(name+start)==46)||(size==2&&load8(name+start)==46&&load8(name+start+1)==46){return 0;}start=i+1;if i==n-1&&c==47{return 1;}}i=i+1;}return 1;
}
// Archive: original bytes/length/entries. Entry: name/method/packed size/raw
// size/CRC/packed bytes/cached raw bytes; no pointers to caller-owned buffers.
fn az_open(path){
    let data=h_read(path);let n=h_file_size;h_assert(n>=22,"Truncated ZIP archive");let at=n-22;let floor=n-65557;if floor<0{floor=0;}let end=-1;
    while at>=floor&&end<0{if az_u32(data+at)==0x06054b50&&at+22+az_u16(data+at+20)==n{end=at;}at=at-1;}
    h_assert(end>=0,"Missing ZIP central directory");let count=az_u16(data+end+10);let offset=az_u32(data+end+16);let size=az_u32(data+end+12);
    h_assert(!az_u16(data+end+4)&&!az_u16(data+end+6)&&az_u16(data+end+8)==count&&count<65535&&offset!=0xffffffff&&size!=0xffffffff,"ZIP64 or multidisk archive is unsupported");
    h_assert(offset+size<=end,"ZIP central directory exceeds archive");let capacity=count;if !capacity{capacity=1;}let entries=h_vec_sized(capacity);at=offset;let i=0;
    while i<count{
        h_assert(at+46<=offset+size&&az_u32(data+at)==0x02014b50,"Invalid ZIP central entry");let p=data+at;let names=az_u16(p+28);let extra=az_u16(p+30);let comment=az_u16(p+32);let flags=az_u16(p+8);let method=az_u16(p+10);let packed=az_u32(p+20);let raw=az_u32(p+24);let local=az_u32(p+42);
        h_assert(names>0&&at+46+names+extra+comment<=offset+size&&raw<=33554432&&packed<=67108864&&!az_u16(p+34)&&!(flags&1)&&(method==0||method==8),"Unsupported or oversized ZIP member");
        let name=h_slice(p+46,names);h_assert(h_len(name)==names&&az_name(name),"Invalid ZIP member path");
        h_assert(local+30<=offset&&az_u32(data+local)==0x04034b50&&az_u16(data+local+8)==method,"Invalid ZIP local header");
        let local_name=az_u16(data+local+26);let begin=local+30+local_name+az_u16(data+local+28);
        h_assert(local_name==names&&local+30+names<=offset&&h_bytes(data+local+30,name,names)&&begin+packed<=offset,"ZIP member data exceeds archive");
        let entry=h_zero(h_take(56),56);store64(entry,name);store64(entry+8,method);store64(entry+16,packed);store64(entry+24,raw);store64(entry+32,az_u32(p+16));store64(entry+40,data+begin);h_add_sized(entries,entry);
        at=at+46+names+extra+comment;i=i+1;
    }
    h_assert(at==offset+size,"ZIP central directory size mismatch");let archive=h_take(24);store64(archive,data);store64(archive+8,n);store64(archive+16,entries);return archive;
}
fn az_find(archive,name){let entries=load64(archive+16);let i=0;let found=0;while i<h_count(entries){let e=h_at(entries,i);if h_equal(load64(e),name){h_assert(!found,"Duplicate ZIP member");found=e;}i=i+1;}return found;}
fn az_crc(data,n){return ffi_call(az_z("crc32"),0,data,n,0,0,0)&0xffffffff;}
fn az_data(entry){
    h_assert(entry,"Required ZIP member is absent");if load64(entry+48){return load64(entry+48);}let packed=load64(entry+16);let n=load64(entry+24);let result=load64(entry+40);
    if load64(entry+8)==8{
        let stream=h_zero(h_take(112),112);result=h_take(n+1);store64(stream,load64(entry+40));az_p32(stream+8,packed);store64(stream+24,result);az_p32(stream+32,n+1);
        let version=ffi_call(az_z("zlibVersion"),0,0,0,0,0,0);h_assert(ffi_call(az_z("inflateInit2_"),stream,-15,version,112,0,0)==0,"ZIP inflater initialization failed");
        let status=ffi_call(az_z("inflate"),stream,4,0,0,0,0)&0xffffffff;let used=load64(stream+16);let written=load64(stream+40);let closed=ffi_call(az_z("inflateEnd"),stream,0,0,0,0,0);
        h_assert(status==1&&closed==0&&used==packed&&written==n,"Invalid compressed ZIP payload");
    }else{h_assert(packed==n,"Stored ZIP member size mismatch");}
    h_assert(az_crc(result,n)==load64(entry+32),"ZIP payload CRC mismatch");store64(entry+48,result);return result;
}
fn az_new(name,data,n,compress){
    h_assert(az_name(name)&&n>=0&&n<=33554432,"Invalid ZIP output member");let entry=h_zero(h_take(56),56);store64(entry,name);store64(entry+24,n);store64(entry+32,az_crc(data,n));store64(entry+48,data);
    let packed=data;let size=n;
    if compress{
        let stream=h_zero(h_take(112),112);let version=ffi_call(az_z("zlibVersion"),0,0,0,0,0,0);
        h_assert(h_ffi8(az_z("deflateInit2_"),stream,-1,8,-15,8,0,version,112)==0,"ZIP compressor initialization failed");
        let capacity=ffi_call(az_z("deflateBound"),stream,n,0,0,0,0);h_assert(capacity>0&&capacity<=67108864,"ZIP compression bound");packed=h_take(capacity);
        store64(stream,data);az_p32(stream+8,n);store64(stream+24,packed);az_p32(stream+32,capacity);
        let status=ffi_call(az_z("deflate"),stream,4,0,0,0,0)&0xffffffff;size=load64(stream+40);let closed=ffi_call(az_z("deflateEnd"),stream,0,0,0,0,0);h_assert(status==1&&closed==0,"ZIP compression failed");store64(entry+8,8);
    }
    store64(entry+16,size);store64(entry+40,packed);return entry;
}
fn az_file(name,path,compress){let data=h_read(path);return az_new(name,data,h_file_size,compress);}
fn az_write(path,entries){
    h_assert(h_count(entries)<65535,"ZIP member count exceeds bounded format");let output=h_buffer();let central=h_buffer();let i=0;
    while i<h_count(entries){
        let e=h_at(entries,i);let name=load64(e);let names=h_len(name);h_assert(names>0&&names<=4096&&az_name(name),"Invalid ZIP output name");let j=0;while j<i{h_assert(!h_equal(load64(h_at(entries,j)),name),"Duplicate ZIP output name");j=j+1;}
        let local=h_size(output);let header=h_zero(h_take(30),30);az_p32(header,0x04034b50);az_p16(header+4,20);az_p16(header+6,0x800);az_p16(header+8,load64(e+8));az_p16(header+12,33);az_p32(header+14,load64(e+32));az_p32(header+18,load64(e+16));az_p32(header+22,load64(e+24));az_p16(header+26,names);
        h_append(output,header,30);h_text(output,name);h_append(output,load64(e+40),load64(e+16));
        header=h_zero(h_take(46),46);az_p32(header,0x02014b50);az_p16(header+4,788);az_p16(header+6,20);az_p16(header+8,0x800);az_p16(header+10,load64(e+8));az_p16(header+14,33);az_p32(header+16,load64(e+32));az_p32(header+20,load64(e+16));az_p32(header+24,load64(e+24));az_p16(header+28,names);az_p32(header+38,0x81a40000);az_p32(header+42,local);h_append(central,header,46);h_text(central,name);i=i+1;
    }
    let offset=h_size(output);h_append(output,h_data(central),h_size(central));let end=h_zero(h_take(22),22);az_p32(end,0x06054b50);az_p16(end+8,h_count(entries));az_p16(end+10,h_count(entries));az_p32(end+12,h_size(central));az_p32(end+16,offset);h_append(output,end,22);h_assert(h_size(output)<=67108864,"ZIP output exceeds64MiB");return h_save_bytes(path,h_data(output),h_size(output),420);
}
