// Read-only FAT32 boot-file access in regular-file MBR/GPT disk images.
// No host mount, loop device or guest helper. ASCII boot paths only; long
// filenames are checked against their sequence and short-name checksum.
// State[2048]: map, bytes, partition base/bytes, sector/cluster bytes, FAT
// base/bytes, data base, maximum cluster, root cluster, result cluster/size/
// attributes; LFN scratch at 512. All offsets are checked before dereference.
global fat_message=0;
fn fat_fail(message) {fat_message=message;return 0;}
fn fat_u16(p) {return load8(p)|(load8(p+1)<<8);}
fn fat_u32(p) {return fat_u16(p)|(fat_u16(p+2)<<16);}
fn fat_zero(p,n) {let i=0;while i<n {store8(p+i,0);i=i+1;}return 0;}
fn fat_range(size,offset,n) {return offset>=0 && n>=0 && offset<=size && n<=size-offset;}
fn fat_crc(p,n,skip) {let crc=0xffffffff;let i=0;while i<n {let byte=load8(p+i);if skip && i>=16 && i<20 {byte=0;}crc=crc^byte;let j=0;while j<8 {let bit=crc&1;crc=crc>>1;if bit {crc=crc^0xedb88320;}j=j+1;}i=i+1;}return crc^0xffffffff;}
fn fat_partition(s,index) {
    let map=load64(s);let bytes=load64(s+8);if index<1 || index>128 || bytes<1024 || fat_u16(map+510)!=0xaa55 {return fat_fail("Invalid partition index or disk signature.");}
    let start=0;let length=0;let gpt=0;let i=0;while i<4 {if load8(map+446+i*16+4)==0xee {gpt=1;}i=i+1;}
    if gpt {
        let h=map+512;let size=fat_u32(h+12);let table=load64(h+72);let count=fat_u32(h+80);let stride=fat_u32(h+84);
        if load64(h)!=load64("EFI PART") || fat_u32(h+8)!=0x10000 || size<92 || size>512 || fat_u32(h+20) || load64(h+24)!=1 || load64(h+32)<2 || load64(h+32)>=bytes/512 || load64(h+40)<2 || load64(h+48)<load64(h+40) || load64(h+48)>=load64(h+32) || fat_crc(h,size,1)!=fat_u32(h+16) {return fat_fail("Invalid GPT header or checksum.");}
        if !count || count>4096 || index>count || stride<128 || stride>1024 || (stride&(stride-1)) || table<2 || table>bytes/512 || !fat_range(bytes,table*512,count*stride) || table+(count*stride+511)/512>load64(h+40) {return fat_fail("Invalid GPT partition array bounds.");}
        let p=map+table*512;if fat_crc(p,count*stride,0)!=fat_u32(h+88) {return fat_fail("Invalid GPT partition array checksum.");}p=p+(index-1)*stride;
        if !load64(p) && !load64(p+8) {return fat_fail("Requested GPT partition is empty.");}
        start=load64(p+32);let end=load64(p+40);
        if start<load64(h+40) || end<start || end>load64(h+48) {return fat_fail("GPT partition exceeds usable disk range.");}length=end-start+1;
    }else {
        if index>4 {return fat_fail("Only primary MBR partitions are supported.");}let p=map+446+(index-1)*16;
        let type=load8(p+4);if type!=0x0b && type!=0x0c && type!=0xef {return fat_fail("Requested MBR partition is not FAT32.");}
        start=fat_u32(p+8);length=fat_u32(p+12);
    }
    if start<1 || !length || !fat_range(bytes,start*512,length*512) {return fat_fail("Partition exceeds disk image.");}
    store64(s+16,start*512);store64(s+24,length*512);return 1;
}
fn fat_init(s,map,bytes,index) {
    fat_zero(s,2048);fat_message=0;store64(s,map);store64(s+8,bytes);if !map || bytes<1024 || bytes>1099511627776 {return fat_fail("Invalid FAT32 disk mapping.");}if !fat_partition(s,index) {return 0;}
    let p=map+load64(s+16);let sector=fat_u16(p+11);let sectors=load8(p+13);let reserved=fat_u16(p+14);let copies=load8(p+16);let total=fat_u32(p+32);let fat=fat_u32(p+36);let flags=fat_u16(p+40);
    if fat_u16(p+510)!=0xaa55 || sector<512 || sector>4096 || (sector&(sector-1)) || !sectors || sectors>128 || (sectors&(sectors-1)) || !reserved || copies<1 || copies>2 || fat_u16(p+17) || fat_u16(p+19) || fat_u16(p+22) || !fat || fat_u16(p+42) || (flags&~0x8f) {return fat_fail("Invalid or unsupported FAT32 boot parameters.");}
    let overhead=reserved+copies*fat;if total<=overhead || total>load64(s+24)/sector {return fat_fail("FAT32 volume exceeds partition.");}
    let clusters=(total-overhead)/sectors;let root=fat_u32(p+44);let active=0;if flags&128 {active=flags&15;}
    if clusters<65525 || clusters>=0x0ffffff5 || (clusters+2)>fat*sector/4 || root<2 || root>clusters+1 || active>=copies {return fat_fail("Invalid FAT32 allocation table or root cluster.");}
    store64(s+32,sector);store64(s+40,sectors*sector);store64(s+48,load64(s+16)+(reserved+active*fat)*sector);store64(s+56,fat*sector);store64(s+64,load64(s+16)+overhead*sector);store64(s+72,clusters+1);store64(s+80,root);return 1;
}
fn fat_next(s,cluster) {if cluster<2 || cluster>load64(s+72) {return -1;}return fat_u32(load64(s)+load64(s+48)+cluster*4)&0x0fffffff;}
fn fat_cluster(s,cluster) {if cluster<2 || cluster>load64(s+72) {return 0;}let offset=load64(s+64)+(cluster-2)*load64(s+40);if !fat_range(load64(s+8),offset,load64(s+40)) {return 0;}return load64(s)+offset;}
fn fat_fold(c) {if c>=65 && c<=90 {return c+32;}return c;}
fn fat_equal(a,n,b,m) {if n!=m {return 0;}let i=0;while i<n {if fat_fold(load8(a+i))!=fat_fold(load8(b+i)) {return 0;}i=i+1;}return 1;}
fn fat_checksum(p) {let sum=0;let i=0;while i<11 {sum=(((sum&1)<<7)+(sum>>1)+load8(p+i))&255;i=i+1;}return sum;}
fn fat_short(p,out) {let n=8;while n && load8(p+n-1)==32 {n=n-1;}let i=0;while i<n {store8(out+i,load8(p+i));i=i+1;}let ext=3;while ext && load8(p+8+ext-1)==32 {ext=ext-1;}if ext {store8(out+n,46);n=n+1;i=0;while i<ext {store8(out+n,load8(p+8+i));n=n+1;i=i+1;}}return n;}
fn fat_find(s,cluster,name,length) {
    let pending=0;let check=0;let slots=0;let walked=0;let lfn=s+512;let text=s+1152;
    while cluster>=2 && cluster<=load64(s+72) && walked<1048576 {
        let block=fat_cluster(s,cluster);if !block {return fat_fail("Invalid FAT32 directory cluster.");}let at=0;
        while at<load64(s+40) {
            let p=block+at;let first=load8(p);let attr=load8(p+11);if !first {return fat_fail("Boot file was not found in FAT32 directory.");}
            if first==0xe5 {pending=0;slots=0;}
            else if attr==15 {
                let seq=first&31;if first&64 {pending=seq;slots=seq;check=load8(p+13);fat_zero(lfn,520);}
                if !seq || seq>20 || seq!=pending || load8(p+12) || fat_u16(p+26) || load8(p+13)!=check || (first&0xa0) {pending=0;slots=0;}
                else {let j=0;while j<13 {let off=1+j*2;if j>=5 {off=14+(j-5)*2;}if j>=11 {off=28+(j-11)*2;}let unit=fat_u16(p+off);store8(lfn+((seq-1)*13+j)*2,unit);store8(lfn+((seq-1)*13+j)*2+1,unit>>8);j=j+1;}pending=pending-1;}
            }
            else {
                let match=0;if !(attr&8) {
                    if slots && !pending && check==fat_checksum(p) {let n=0;let valid=1;while n<slots*13 && fat_u16(lfn+n*2) && fat_u16(lfn+n*2)!=65535 {let c=fat_u16(lfn+n*2);if c>127 || c<32 || n>=255 {valid=0;}store8(text+n,c);n=n+1;}if valid {match=fat_equal(name,length,text,n);}}
                    if !match {match=fat_equal(name,length,text,fat_short(p,text));}
                    if match {store64(s+88,(fat_u16(p+20)<<16)|fat_u16(p+26));store64(s+96,fat_u32(p+28));store64(s+104,attr);return 1;}
                }pending=0;slots=0;
            }at=at+32;
        }walked=walked+load64(s+40);cluster=fat_next(s,cluster);
    }return fat_fail("FAT32 directory chain is invalid, cyclic, too large or has no matching file.");
}
// Allocated file bytes plus one trailing zero; caller unmaps size+1. Returns
// zero on failure. Enforce exact chain termination, even for a full last cluster.
fn fat_read(s,path) {
    fat_message=0;let length=0;while length<1024 && load8(path+length) {length=length+1;}if !length || length==1024 {return fat_fail("Invalid FAT32 boot path length.");}
    let at=0;if load8(path)==47 {at=1;}if at==length {return fat_fail("FAT32 boot path names the root directory.");}let cluster=load64(s+80);let depth=0;
    while at<length {let start=at;while at<length && load8(path+at)!=47 {at=at+1;}let n=at-start;
        if !n || n>255 || (n==1 && load8(path+start)==46) || (n==2 && load8(path+start)==46 && load8(path+start+1)==46) || depth>=16 {return fat_fail("Invalid FAT32 boot path component.");}
        if !fat_find(s,cluster,path+start,n) {return 0;}cluster=load64(s+88);depth=depth+1;
        if at<length {if !(load64(s+104)&16) {return fat_fail("FAT32 boot path component is not a directory.");}at=at+1;if at==length {return fat_fail("FAT32 boot path ends at a directory.");}}
    }
    let size=load64(s+96);if (load64(s+104)&16) || size>1073741824 {return fat_fail("FAT32 boot file is a directory or exceeds 1 GiB.");}
    let data=alloc(size+1);if data<0 {return fat_fail("Cannot allocate FAT32 boot file buffer.");}let copied=0;let valid=1;
    if !size {valid=cluster==0;}while copied<size && valid {
        let source=fat_cluster(s,cluster);if !source {valid=0;}else {let n=size-copied;if n>load64(s+40) {n=load64(s+40);}let i=0;while i<n {store8(data+copied+i,load8(source+i));i=i+1;}copied=copied+n;cluster=fat_next(s,cluster);}
    }
    if !valid || (size && cluster<0x0ffffff8) {syscall(11,data,size+1,0,0,0,0);return fat_fail("FAT32 boot file has a truncated, overlong or cyclic cluster chain.");}
    store8(data+size,0);return data;
}
// Mapping stays read-only. Stop the guest before inspecting its boot files.
fn fat_open(s,path,index) {
    fat_zero(s,2048);let fd=syscall(2,path,0xa0000,0,0,0,0);if fd<0 {return fat_fail("Cannot open FAT32 disk image.");}let stat=alloc(256);if stat<0 {syscall(3,fd,0,0,0,0,0);return fat_fail("Cannot allocate disk metadata.");}
    let ok=syscall(5,fd,stat,0,0,0,0)==0;let bytes=load64(stat+48);ok=ok && (fat_u32(stat+24)&0xf000)==0x8000 && bytes>=1024 && bytes<=1099511627776;
    syscall(11,stat,256,0,0,0,0);if !ok {syscall(3,fd,0,0,0,0,0);return fat_fail("Boot disk must be a regular file of at most 1 TiB.");}
    let map=syscall(9,0,bytes,1,2,fd,0);syscall(3,fd,0,0,0,0,0);if map<0 {return fat_fail("Cannot map FAT32 disk image.");}
    if !fat_init(s,map,bytes,index) {syscall(11,map,bytes,0,0,0,0);store64(s,0);return 0;}return 1;
}
fn fat_close(s) {if load64(s) {syscall(11,load64(s),load64(s+8),0,0,0,0);store64(s,0);}return 0;}
