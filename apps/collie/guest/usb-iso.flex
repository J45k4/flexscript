// Copied USB ISO result ABI, little endian. Protocol/status handling is portable.
// Completion of an URB is distinct from successful individual packets or a device effect.
fn uiso_error(message){db_last_error=message;db_last_error_details=db_list();db_add(db_last_error_details,db_text("invalid_usb_iso_frame"));db_add(db_last_error_details,db_text(message));return 0;}
fn uiso_u32(p){return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn uiso_i32(p){let n=uiso_u32(p);if n&2147483648{return n-4294967296;}return n;}
fn uiso_u64(p){return uiso_u32(p)|(uiso_u32(p+4)<<32);}
fn uiso_field(map,key,value){let pair=db_list();db_add(pair,db_text(key));db_add(pair,value);db_add(map,pair);return map;}
fn usb_iso_decode(frame){
    db_last_error=0;db_last_error_details=0;
    if db_kind(frame)!=3 || db_bytes(frame)<64 || db_bytes(frame)>26688{return uiso_error("An ISO frame must be a complete bounded binary result.");}
    let p=db_word(frame);let magic="COLLISO1";let i=0;
    while i<8{if load8(p+i)!=load8(magic+i){return uiso_error("Unknown ISO result signature.");}i=i+1;}
    let flags=uiso_u32(p+12);let count=uiso_u32(p+32);let requested=uiso_u32(p+36);let actual=uiso_u32(p+40);let bytes=uiso_u32(p+44);let elapsed=uiso_u64(p+48);
    if uiso_u32(p+8)!=1 || flags&(-32) || count<1 || count>128 || requested<1 || requested>24576 || bytes!=requested || actual>requested || elapsed<0 || uiso_u32(p+56)!=1 || uiso_u32(p+60)>1 || uiso_u32(p+16)>4095 || uiso_u32(p+28)>count || db_bytes(frame)!=64+count*16+bytes{return uiso_error("Invalid ISO version, flags, bounds or completion fields.");}
    let submitted=flags&1;let reaped=(flags>>1)&1;
    if reaped && !submitted{return uiso_error("An unsubmitted ISO request cannot have a kernel completion.");}
    if uiso_u32(p+60)!=(submitted && !reaped){return uiso_error("An unreaped submitted URB must retain its cleanup requirement.");}
    if !reaped && actual{return uiso_error("An unreaped ISO request cannot report actual packet bytes.");}
    let packets=db_list();let offset=0;let sum=0;i=0;
    while i<count{
        let r=p+64+i*16;let length=uiso_u32(r);let transferred=uiso_u32(r+4);let status=uiso_i32(r+8);let at=uiso_u32(r+12);
        if length<1 || length>16384 || length>requested-offset || transferred>length || at!=offset || status>0 || status<(-4095) || (!reaped && transferred){return uiso_error("Invalid ISO packet length, offset, status or actual byte count.");}
        let row=db_list();uiso_field(row,"requested",db_int(length));uiso_field(row,"actual",db_int(transferred));uiso_field(row,"status",db_int(status));uiso_field(row,"status_known",db_int(reaped));uiso_field(row,"data",db_blob(p+64+count*16+offset,transferred));db_add(packets,row);
        offset=offset+length;sum=sum+transferred;i=i+1;
    }
    if offset!=requested || sum!=actual{return uiso_error("ISO packet totals do not match the result header.");}
    let result=db_list();uiso_field(result,"version",db_int(1));uiso_field(result,"submitted",db_int(submitted));uiso_field(result,"reaped",db_int(reaped));uiso_field(result,"cancel_requested",db_int((flags>>2)&1));uiso_field(result,"deadline_expired",db_int((flags>>3)&1));uiso_field(result,"input",db_int((flags>>4)&1));
    uiso_field(result,"io_errno",db_int(uiso_i32(p+16)));uiso_field(result,"urb_status",db_int(uiso_i32(p+20)));uiso_field(result,"urb_status_known",db_int(reaped));uiso_field(result,"requested_start_frame",db_int(uiso_i32(p+24)));uiso_field(result,"start_frame",db_null());uiso_field(result,"start_frame_known",db_int(0));uiso_field(result,"error_count",db_int(uiso_u32(p+28)));uiso_field(result,"error_count_known",db_int(reaped));uiso_field(result,"requested",db_int(requested));uiso_field(result,"actual",db_int(actual));uiso_field(result,"elapsed_ns",db_int(elapsed));uiso_field(result,"cleanup_required",db_int(uiso_u32(p+60)));uiso_field(result,"packets",packets);return result;
}
