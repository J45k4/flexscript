// Schema-specific checkpoint sizing and packing of engine-owned RAM rows.
// Trusted baseline x86-64, emitted in Flexscript; no assembler or extra ISA.
// System V RDI=context; preserve RBX/RBP/R12..R15, align the CRC call stack.
// Context: row pointers, count, buffer, capacity, used, directory offset,
// CRC entry, CRC tables. The sizing entry uses only the first two words.
// Writers check every destination bound before storing, including byte payloads.
// Return >=0 (size for sizing, zero for packing), -1 on invalid rows/overflow.
// At 64 fields the bounded emission fits in 16 KiB. RW -> RX, then unmap.
fn fd_pack_native(t,sizing) {
 if fd_crc_code<=0 {return 0;}let columns=load64(t+16);let count=fd_size(columns);if count<1 || count>64 {return 0;}let i=0;
 while i<count {let c=fd_at(columns,i);if load64(c+8)<1 || load64(c+8)>4 || load64(c+16)<0 || load64(c+16)>1 {return 0;}i=i+1;}
 let code=alloc(16384);if code<=0 {return 0;}let a=alloc(32);if a<=0 {syscall(11,code,16384,0,0,0,0);return 0;}let state=fd_alloc(a,24);store64(state+16,a);store64(state+8,fd_vec(a));let labels=fd_alloc(a,32);
 fd_crc_hex(code,state,"555341544155415641574883ec084989fc4531ed");
 if sizing {fd_crc_hex(code,state,"31db");}else {fd_crc_hex(code,state,"498b5c241049035c2420498b6c241049036c2418");} // cursor=base+used, end=base+capacity
 let loop=load64(state);fd_crc_hex(code,state,"4d3b6c2408");fd_scan_jump(code,state,"0f83",1);
 fd_crc_hex(code,state,"498b04244e8b34e8"); // mov r14,[row pointers+r13*8]
 fd_crc_hex(code,state,"4d85f6");fd_scan_jump(code,state,"0f84",3);fd_crc_hex(code,state,"49837e0800");fd_scan_jump(code,state,"0f84",2);
 fd_crc_hex(code,state,"49817e08");fd_crc_emit32(code,state,count);fd_scan_jump(code,state,"0f85",3);
 if sizing {fd_crc_hex(code,state,"4883c308");}else {fd_crc_hex(code,state,"4889e84829d84883f808");fd_scan_jump(code,state,"0f82",3);fd_crc_hex(code,state,"4989df4883c3084531db");}
 // RBX=total size, or destination cursor; R14=owned row. Packing also holds
 // R15=row start, RBP=buffer end, R11=null bitmap. Cell pointers are in RAX.
 i=0;while i<count {let c=fd_at(columns,i);let kind=load64(c+8);let nullable=load64(c+16);fd_crc_hex(code,state,"498b86");fd_crc_emit32(code,state,16+i*8);let null=-1;
  if nullable {fd_crc_hex(code,state,"48833800");null=fd_scan_jump(code,state,"0f84",0);}
  fd_crc_hex(code,state,"488338");fd_crc_emit(code,state,kind);fd_scan_jump(code,state,"0f85",3);
  if sizing {fd_crc_hex(code,state,"4883c308");if kind==2 || kind==3 {fd_crc_hex(code,state,"488b48104881f900001000");fd_scan_jump(code,state,"0f87",3);fd_crc_hex(code,state,"4801cb");}}
  else {fd_crc_hex(code,state,"4889ea4829da4883fa08");fd_scan_jump(code,state,"0f82",3);
   if kind==2 || kind==3 {fd_crc_hex(code,state,"488b48104881f900001000");fd_scan_jump(code,state,"0f87",3);fd_crc_hex(code,state,"4883ea084839d1");fd_scan_jump(code,state,"0f87",3);fd_crc_hex(code,state,"48890b488d7b08488b70084889fb4801cbf3a4");}
   else {fd_crc_hex(code,state,"488b480848890b4883c308");}
  }
  if null>=0 {let done=fd_scan_jump(code,state,"e9",0);fd_scan_patch(code,null,load64(state));if !sizing {fd_crc_hex(code,state,"490fbaeb");fd_crc_emit(code,state,i);}fd_scan_patch(code,done,load64(state));}i=i+1;
 }
 if !sizing {
  // Store mask; call IEEE CRC on [row start,cursor); pack CRC/length and the
  // buffer-relative row offset into its previously reserved directory entry.
  fd_crc_hex(code,state,"4d891fbfffffffff4c89fe4889da4c29fa498b4c243841ff54243035ffffffff48c1e0204889da4c29fa4809d04c89fa492b5424104c89e948c1e10449034c241049034c242848891148894108");
 }
 let next=fd_scan_jump(code,state,"e9",0);store64(labels+16,load64(state)); // tombstone
 if !sizing {fd_crc_hex(code,state,"4c89e848c1e0044903442410490344242848c7000000000048c7400800000000");}
 fd_scan_patch(code,next,load64(state));fd_crc_hex(code,state,"49ffc5");let back=fd_scan_jump(code,state,"e9",0);fd_scan_patch(code,back,loop);
 store64(labels+8,load64(state));if sizing {fd_crc_hex(code,state,"4881fb00000001");fd_scan_jump(code,state,"0f87",3);fd_crc_hex(code,state,"4889d8");}else {fd_crc_hex(code,state,"492b5c241049895c242031c0");}let done=fd_scan_jump(code,state,"e9",0);
 store64(labels+24,load64(state));fd_crc_hex(code,state,"48c7c0ffffffff");fd_scan_patch(code,done,load64(state));fd_crc_hex(code,state,"4883c408415f415e415d415c5b5dc3");let patches=load64(state+8);i=0;while i<fd_size(patches) {let p=fd_at(patches,i);fd_scan_patch(code,load64(p),load64(labels+load64(p+8)*8));i=i+1;}
 let size=load64(state);fd_clear(a);syscall(11,a,32,0,0,0,0);if size>16384 || syscall(10,code,16384,5,0,0,0)<0 {syscall(11,code,16384,0,0,0,0);return 0;}return code;
}
fn fd_pack_size(t) {
 // -2 means unavailable; -1 means invalid/oversized. A zero payload is valid.
 let code=fd_pack_native(t,1);if !code {return -2;}let c=alloc(16);if c<=0 {syscall(11,code,16384,0,0,0,0);return -2;}let rows=load64(t+24);store64(c,load64(rows+16));store64(c+8,fd_size(rows));let result=ffi_call(code,c,0,0,0,0,0);syscall(11,c,16,0,0,0,0);syscall(11,code,16384,0,0,0,0);return result;
}
fn fd_pack_rows(t,b,directory) {
 let n=fd_size(load64(t+24));let used=load64(b);let cap=load64(b+8);if directory<0 || used<0 || cap<used || cap>16777216 || directory>used || n>(used-directory)/16 {return -1;}
 let code=fd_pack_native(t,0);if !code {return 0;}let c=alloc(64);if c<=0 {syscall(11,code,16384,0,0,0,0);return 0;}let rows=load64(t+24);store64(c,load64(rows+16));store64(c+8,fd_size(rows));store64(c+16,load64(b+16));store64(c+24,load64(b+8));store64(c+32,load64(b));store64(c+40,directory);store64(c+48,fd_crc_code);store64(c+56,fd_crc_tables);
 let result=ffi_call(code,c,0,0,0,0,0);if !result {store64(b,load64(c+32));}syscall(11,c,64,0,0,0,0);syscall(11,code,16384,0,0,0,0);if result<0 {return -1;}return 1;
}
