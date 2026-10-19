import "crc-native.flex";
global fd_crc_tables=0;
// Linux x86-64 single-file transaction log. No journal/WAL sidecar.
fn fd_io(fd,p,n,offset,write) {
    let done=0;while done<n {let kind=17;if write {kind=18;}let r=syscall(kind,fd,p+done,n-done,offset+done,0,0);if r==-4 {}else if r<=0 {return 0;}else {done=done+r;}}return 1;
}
fn fd_sync(fd) {let r=syscall(74,fd,0,0,0,0,0);while r==-4 {r=syscall(74,fd,0,0,0,0,0);}return r==0;}
fn fd_crc_init() {
    if fd_crc_tables {return fd_crc_tables;}let tables=alloc(16384);if tables<=0 {fd_panic();}let i=0;
    while i<256 {let crc=i;let j=0;while j<8 {crc=(crc>>1)^(0xedb88320*(crc&1));j=j+1;}store64(tables+i*8,crc);i=i+1;}
    let slice=1;while slice<8 {i=0;while i<256 {let crc=load64(tables+(slice-1)*2048+i*8);store64(tables+slice*2048+i*8,(crc>>8)^load64(tables+(crc&255)*8));i=i+1;}slice=slice+1;}
    fd_crc_tables=tables;return tables;
}
// Standard IEEE CRC32, slicing eight bytes at a time; same file checksums.
fn fd_crc(crc,p,n) {
    if n<0 {return crc&4294967295;}let tables=fd_crc_tables;if !tables {tables=fd_crc_init();}let native=fd_crc_code;if !native {native=fd_crc_native_init();}if native>0 {return ffi_call(native,crc,p,n,tables,0,0);}
    let i=0;
    while i<=n-8 {let word=load64(p+i)^(crc&4294967295);
        crc=load64(tables+14336+(word&255)*8)^load64(tables+12288+((word>>8)&255)*8)^load64(tables+10240+((word>>16)&255)*8)^load64(tables+8192+((word>>24)&255)*8)^load64(tables+6144+((word>>32)&255)*8)^load64(tables+4096+((word>>40)&255)*8)^load64(tables+2048+((word>>48)&255)*8)^load64(tables+((word>>56)&255)*8);i=i+8;
    }
    while i<n {crc=(crc>>8)^load64(tables+((crc^load8(p+i))&255)*8);i=i+1;}return crc&4294967295;
}
fn fd_header(a) {let p=fd_alloc(a,32);fd_copy(p,"FLEXDB01",8);store64(p+8,1);store64(p+16,32);store64(p+24,0);return p;}
fn fd_open_storage(db,path) {
    let fd=syscall(2,path,0xa00c2,384,0,0,0);
    if fd==-17 {fd=syscall(2,path,0xa0002,0,0,0,0);}if fd<0 {return fd_error(db,"cannot open database file");}
    store64(db+24,fd);let stat=fd_alloc(db,144);
    if syscall(73,fd,6,0,0,0,0)<0 {return fd_error(db,"database is already open (exclusive lock)");}
    // Inspect size after locking: another creator/writer may have finished
    // between open and flock. Never initialize a now-populated file.
    if syscall(5,fd,stat,0,0,0,0)<0 || (load64(stat+24)&61440)!=32768 {return fd_error(db,"database must be a regular file");}
    let named=fd_alloc(db,144);if syscall(4,path,named,0,0,0,0)<0 || load64(stat)!=load64(named) || load64(stat+8)!=load64(named+8) {return fd_error(db,"database path was replaced during open; retry");}
    let size=load64(stat+48);
    if size==0 {
        if !fd_io(fd,fd_header(db),32,0,1) || !fd_sync(fd) {return fd_error(db,"cannot initialize database");}
        // Make creation durable as well as the file's contents.
        let n=fd_len(path);let i=n-1;while i>=0 && load8(path+i)!=47 {i=i-1;}
        let parent=".";if i>=0 {let bytes=i;if !bytes {bytes=1;}parent=fd_alloc(db,bytes+1);fd_copy(parent,path,bytes);store8(parent+bytes,0);}
        let dir=syscall(2,parent,0x90000,0,0,0,0);
        if dir<0 {return fd_error(db,"cannot open database directory");}
        let ok=fd_sync(dir);syscall(3,dir,0,0,0,0,0);if !ok {return fd_error(db,"cannot sync database directory");}size=32;
    }
    let header=fd_alloc(db,32);
    if size<32 || !fd_io(fd,header,32,0,0) {return fd_error(db,"invalid FlexDB header or version");}
    let base=(fd_bytes(header,"FLEXDB02",8) && load64(header+8)==2 || fd_bytes(header,"FLEXDB03",8) && load64(header+8)==3) && load64(header+16)==32 && load64(header+24)==1;
    let legacy=fd_bytes(header,"FLEXDB01",8) && load64(header+8)==1 && load64(header+16)==32 && load64(header+24)==0;
    if !base && !legacy {return fd_error(db,"invalid FlexDB header or version");}if base && size<128 {return fd_error(db,"incomplete base checkpoint");}store64(db+192,base);
    // A completed footer identifies the authoritative checkpoint without a
    // mutable header/root slot. Torn tails use the ordinary recovery scan.
    let offset=32;let sequence=0;let pending_blobs=0;
    if size>=80 {
        let tail=fd_alloc(db,48);if !fd_io(fd,tail,48,size-48,0) {return fd_error(db,"cannot read file tail");}
        if fd_footer_ok(tail) && (fd_bytes(tail,"FLEXEND2",8) || (fd_bytes(tail,"FLEXEND3",8) && load64(tail+24)>0) || fd_bytes(tail,"FLEXCPE1",8)) {
            let cp=load64(tail+24);let start=load64(tail+16);if cp<32 || cp>start || start>size-80 {return fd_error(db,"invalid checkpoint footer location");}
            if !fd_cp_load(db,cp,size) {return 0;}offset=load64(db+152);sequence=load64(db+160);
            if load64(tail+8)<sequence || (fd_bytes(tail,"FLEXCPE1",8) && (start!=cp || offset!=size)) {return fd_error(db,"invalid checkpoint tail sequence");}
        }
    }
    let scratch=alloc(32);if scratch<=0 {fd_panic();}let ok=1;
    while offset<size && ok {
        let remain=size-offset;
        if remain<32 {if base && offset==32 {ok=fd_error(db,"incomplete base checkpoint");}else {size=offset;}}
        else {
            let h=fd_alloc(scratch,64);if !fd_io(fd,h,32,offset,0) {ok=fd_error(db,"cannot read transaction header");}
            else if fd_bytes(h,"FLEXBL01",8) {
                if !pending_blobs {pending_blobs=offset;}if remain<64 {size=offset;}else if !fd_io(fd,h+32,32,offset+32,0) {ok=fd_error(db,"cannot read blob header");}else {let result=fd_blob_recover(db,h,offset,size,scratch);if !result {ok=0;}else if result==2 {size=offset;}else {offset=offset+112+load64(h+8);}}
            }
            else if fd_bytes(h,"FLEXCP01",8) || fd_bytes(h,"FLEXCP02",8) || fd_bytes(h,"FLEXCP03",8) || fd_bytes(h,"FLEXCP04",8) {
                if !fd_cp_header_ok(h) || (offset!=32 && (!base || load64(db+144)) && load64(h+16)!=sequence) {ok=fd_error(db,"invalid checkpoint header");}
                else if remain<load64(h+8)+80 {if base && offset==32 {ok=fd_error(db,"incomplete base checkpoint");}else {size=offset;}}
                else if !fd_cp_load(db,offset,size) {ok=0;}
                else {sequence=load64(db+160);offset=load64(db+152);pending_blobs=0;}
            }
            else {
                let external=fd_bytes(h,"FLEXTX03",8);let modern=fd_bytes(h,"FLEXTX02",8) || external;let overhead=48;if modern {overhead=80;}
                if (!modern && !fd_bytes(h,"FLEXTX01",8)) || load64(h+8)<8 || load64(h+8)>16777216 || load64(h+16)!=sequence+1 || ((load64(h+24)>>32)&4294967295)!=(fd_crc(4294967295,h,24)^4294967295) {ok=fd_error(db,"invalid transaction header");}
                else {
                    let n=load64(h+8);if remain<overhead+n {size=offset;}
                    else {
                        let p=fd_alloc(scratch,n+overhead-32);
                        if !fd_io(fd,p,n+overhead-32,offset+32,0) {ok=fd_error(db,"cannot read transaction");}
                        else {
                            let footer=p+n;let footer_ok=fd_bytes(footer,"FLEXEND1",8) && load64(footer+8)==sequence+1;
                            if modern {let expected="FLEXEND2";if external {expected="FLEXEND3";}footer_ok=fd_bytes(footer,expected,8) && load64(footer+8)==sequence+1 && load64(footer+16)==offset && load64(footer+24)==load64(db+144) && fd_footer_ok(footer);}
                            if !footer_ok || (fd_crc(fd_crc(4294967295,h,24),p,n)^4294967295)!=(load64(h+24)&4294967295) {ok=fd_error(db,"transaction checksum or footer mismatch");}
                            else if !fd_replay_version(db,p,n,external) {ok=fd_error(db,"invalid transaction contents");}
                            else {sequence=sequence+1;offset=offset+overhead+n;pending_blobs=0;}
                        }
                    }
                }
            }
        }
        fd_clear(scratch);
    }
    fd_clear(scratch);syscall(11,scratch,32,0,0,0,0);if !ok {return 0;}if base && !load64(db+144) {return fd_error(db,"incomplete base checkpoint");}if pending_blobs {offset=pending_blobs;}
    if offset<load64(stat+48) {if syscall(77,fd,offset,0,0,0,0)<0 || !fd_sync(fd) {return fd_error(db,"cannot recover incomplete transaction");}}
    store64(db+56,offset);store64(db+64,sequence);let bs=load64(db+232);if bs {store64(bs+56,offset);}return 1;
}
fn fd_write_transaction(db) {
    let a=load64(db+72);let b=load64(db+80);let n=load64(b);let sequence=load64(db+64)+1;
    let h=fd_alloc(a,32);let bs=load64(db+232);let external=bs && load64(bs+80);let modern=load64(db+144)!=0 || external;let magic="FLEXTX01";if modern {magic="FLEXTX02";}if external {magic="FLEXTX03";}fd_copy(h,magic,8);store64(h+8,n);store64(h+16,sequence);
    let payload_crc=fd_crc(fd_crc(4294967295,h,24),load64(b+16),n)^4294967295;let header_crc=fd_crc(4294967295,h,24)^4294967295;
    store64(h+24,payload_crc|(header_crc<<32));
    let tail=0;let bytes=16;let offset=load64(db+56);if modern {let end_magic="FLEXEND2";if external {end_magic="FLEXEND3";}tail=fd_footer(a,end_magic,sequence,offset,load64(db+144));bytes=48;}else {tail=fd_alloc(a,16);fd_copy(tail,"FLEXEND1",8);store64(tail+8,sequence);}
    let fd=load64(db+24);
    if !fd_io(fd,h,32,offset,1) || !fd_io(fd,load64(b+16),n,offset+32,1) || !fd_io(fd,tail,bytes,offset+32+n,1) || !fd_sync(fd) {
        store64(db+48,2);return fd_error(db,"commit I/O failed; close and reopen (outcome uncertain)");
    }
    store64(db+56,offset+32+bytes+n);store64(db+64,sequence);return 1;
}
