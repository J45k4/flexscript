// Schema-specific validated checkpoint scalar scans. Trusted x86-64 code is
// emitted in Flexscript and sealed RW -> RX. It calls the same IEEE CRC helper,
// checks each directory page/row and every encoded field, and skips RAM rows.
// System V: RDI=context. Preserve RBX/RBP/R12..R15 and call with aligned RSP.
// Context words: body, body bytes, metadata bytes, directory, RAM row pointers,
// checkpoint row count, scalar output, column count, column pointers, selected
// column, CRC code, CRC tables, directory CRCs, directory page flags.
// Column count/kinds/nullability/target are baked from the validated schema.
// At <=64 columns the fixed code plus the largest field sequence fits <16 KiB.
// Return 0 success; 1 directory CRC; 2 row bounds; 3 row CRC; 4 null mask;
// 5 typed encoding/length/nullability. No partially filled view escapes failure.
fn fd_scan_jump(code,state,op,label) {
 fd_crc_hex(code,state,op);let at=load64(state);fd_crc_emit32(code,state,0);if label {let node=fd_alloc(load64(state+16),16);store64(node,at);store64(node+8,label);fd_push(load64(state+16),load64(state+8),node);}return at;
}
fn fd_scan_patch(code,at,target) {let rel=target-at-4;let i=0;while i<4 {store8(code+at+i,(rel>>(i*8))&255);i=i+1;}return 1;}
fn fd_scan_crc_call(code,state) {fd_crc_hex(code,state,"498b4c245841ff54245035ffffffff");return 1;}
fn fd_scan_native(t,col) {
 if fd_crc_code<=0 {return 0;}let columns=load64(t+16);let count=fd_size(columns);if count<1 || count>64 {return 0;}let required=0;let i=0;
 while i<count {let c=fd_at(columns,i);let kind=load64(c+8);let nullable=load64(c+16);if kind<1 || kind>4 || nullable<0 || nullable>1 {return 0;}if !nullable {required=required|(1<<i);}i=i+1;}
 let code=alloc(16384);if code<=0 {return 0;}let a=alloc(32);if a<=0 {syscall(11,code,16384,0,0,0,0);return 0;}let state=fd_alloc(a,24);store64(state+16,a);store64(state+8,fd_vec(a));let labels=fd_alloc(a,72);
 fd_crc_hex(code,state,"555341544155415641574883ec084989fc4531ed");let loop=load64(state);
 fd_crc_hex(code,state,"4d3b6c2428");fd_scan_jump(code,state,"0f83",6); // i >= rows -> success
 fd_crc_hex(code,state,"498b4424204a833ce800");fd_scan_jump(code,state,"0f85",7); // RAM row -> next
 fd_crc_hex(code,state,"4d89ee49c1ee08498b44246842803c3000");let checked=fd_scan_jump(code,state,"0f85",0);
 // Directory page CRC: length=min(4096,rows*16-page*4096).
 fd_crc_hex(code,state,"bfffffffff498b7424184c89f048c1e00c4801c6498b54242848c1e2044829c24881fa00100000");let length=fd_scan_jump(code,state,"0f86",0);fd_crc_hex(code,state,"ba00100000");fd_scan_patch(code,length,load64(state));fd_scan_crc_call(code,state);
 fd_crc_hex(code,state,"498b5424604a3b04f2");fd_scan_jump(code,state,"0f85",1);fd_crc_hex(code,state,"498b44246842c6043001");fd_scan_patch(code,checked,load64(state));
 // Directory entry offset and packed (CRC32,length). Zero entry is a tombstone.
 fd_crc_hex(code,state,"4c89e848c1e004498b5424184c8b34024c8b7c02084c89f04c09f8");fd_scan_jump(code,state,"0f84",7);
 fd_crc_hex(code,state,"4489fd4883fd08");fd_scan_jump(code,state,"0f82",2);fd_crc_hex(code,state,"4d3b742410");fd_scan_jump(code,state,"0f82",2);fd_crc_hex(code,state,"4d3b742408");fd_scan_jump(code,state,"0f87",2);
 fd_crc_hex(code,state,"498b4424084c29f04839c5");fd_scan_jump(code,state,"0f87",2);fd_crc_hex(code,state,"4d03342449c1ef20bfffffffff4c89f64889ea");fd_scan_crc_call(code,state);fd_crc_hex(code,state,"4439f8");fd_scan_jump(code,state,"0f85",3);
 fd_crc_hex(code,state,"4d8b3e");if count<64 {fd_crc_hex(code,state,"4c89f848c1e8");fd_crc_emit(code,state,count);fd_crc_hex(code,state,"4885c0");fd_scan_jump(code,state,"0f85",4);}
 if required {fd_crc_hex(code,state,"48b8");i=0;while i<8 {fd_crc_emit(code,state,(required>>(i*8))&255);i=i+1;}fd_crc_hex(code,state,"4985c7");fd_scan_jump(code,state,"0f85",5);}
 // RBX=cursor, RBP=end, R15=null mask, R14=selected scalar (null -> zero).
 fd_crc_hex(code,state,"498d5e084c01f54531f6");i=0;
 while i<count {let c=fd_at(columns,i);let kind=load64(c+8);let skip=-1;if load64(c+16) {fd_crc_hex(code,state,"490fbae7");fd_crc_emit(code,state,i);skip=fd_scan_jump(code,state,"0f82",0);}
  fd_crc_hex(code,state,"4889e84829d84883f808");fd_scan_jump(code,state,"0f82",5);
  if kind==2 || kind==3 {fd_crc_hex(code,state,"488b034883c308483d00001000");fd_scan_jump(code,state,"0f87",5);fd_crc_hex(code,state,"4889ea4829da4839d0");fd_scan_jump(code,state,"0f87",5);fd_crc_hex(code,state,"4801c3");}
  else {if i==col {fd_crc_hex(code,state,"4c8b33");}fd_crc_hex(code,state,"4883c308");}if skip>=0 {fd_scan_patch(code,skip,load64(state));}i=i+1;
 }
 fd_crc_hex(code,state,"4839eb");fd_scan_jump(code,state,"0f85",5);fd_crc_hex(code,state,"4c89e848c1e004498b5424304801d04c893048c7400801000000");
 store64(labels+7*8,load64(state));fd_crc_hex(code,state,"49ffc5");let back=fd_scan_jump(code,state,"e9",0);fd_scan_patch(code,back,loop);
 store64(labels+6*8,load64(state));fd_crc_hex(code,state,"31c0");fd_scan_jump(code,state,"e9",8);i=1;
 while i<=5 {store64(labels+i*8,load64(state));fd_crc_hex(code,state,"b8");fd_crc_emit32(code,state,i);fd_scan_jump(code,state,"e9",8);i=i+1;}
 store64(labels+8*8,load64(state));fd_crc_hex(code,state,"4883c408415f415e415d415c5b5dc3");let patches=load64(state+8);i=0;while i<fd_size(patches) {let node=fd_at(patches,i);fd_scan_patch(code,load64(node),load64(labels+load64(node+8)*8));i=i+1;}
 let size=load64(state);fd_clear(a);syscall(11,a,32,0,0,0,0);if size>16384 || syscall(10,code,16384,5,0,0,0)<0 {syscall(11,code,16384,0,0,0,0);return 0;}return code;
}
fn fd_scan_fill(t,col,view) {
 let code=fd_scan_native(t,col);if !code {return 0;}let a=load64(view);let c=fd_alloc(a,112);store64(c,load64(t+72));store64(c+8,load64(t+104));store64(c+16,load64(t+112));store64(c+24,load64(t+64));store64(c+32,load64(load64(t+24)+16));store64(c+40,load64(t+80));store64(c+48,load64(view+24));store64(c+56,fd_size(load64(t+16)));store64(c+64,load64(load64(t+16)+16));store64(c+72,col);store64(c+80,fd_crc_code);store64(c+88,fd_crc_tables);store64(c+96,load64(t+88));store64(c+104,load64(t+96));let result=ffi_call(code,c,0,0,0,0,0);syscall(11,code,16384,0,0,0,0);if !result {return 1;}let message="invalid checkpoint row values";if result==1 {message="checkpoint directory checksum mismatch";}if result==2 {message="invalid checkpoint row bounds";}if result==3 {message="checkpoint row checksum mismatch";}if result==4 {message="invalid checkpoint null mask";}fd_corrupt(load64(t),message);return -1;
}
