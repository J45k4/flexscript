// Public Android direct-sensor ABI codec. Input is a copied page, not an
// atomic snapshot of a running producer. Freeze the channel before a capture
// requiring stable records. Rows retain physical slot order and raw payloads.
fn sd_error(message){db_last_error=message;db_last_error_details=db_list();db_add(db_last_error_details,db_text("invalid_sensor_record"));db_add(db_last_error_details,db_text(message));return 0;}
fn sd_clear(){db_last_error=0;db_last_error_details=0;return 0;}
fn sd_u32(p){return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn sd_u64(p){return sd_u32(p)|(sd_u32(p+4)<<32);}
fn sensor_direct_records(bytes){
    sd_clear();if db_kind(bytes)!=3 || db_bytes(bytes)%104 || db_bytes(bytes)>32760{return sd_error("A direct-sensor page must contain0..315 complete104-byte records.");}
    let rows=db_list();let at=0;let p=db_word(bytes);
    while at<db_bytes(bytes){
        let counter=sd_u32(p+at+12);
        if !counter{db_add(rows,db_null());}
        else{
            let token=sd_u32(p+at+4);let type=sd_u32(p+at+8);let timestamp=sd_u64(p+at+16);
            if sd_u32(p+at)!=104 || token<1 || token>2147483647 || type<1 || type>2147483647 || timestamp<0 || sd_u64(p+at+88) || sd_u64(p+at+96){return sd_error("Direct-sensor size, token, type, timestamp or reserved fields are invalid; a live page may be torn.");}
            let row=db_list();db_add(row,db_int(token));db_add(row,db_int(type));db_add(row,db_int(counter));db_add(row,db_int(timestamp));db_add(row,db_blob(p+at+24,64));db_add(rows,row);
        }
        at=at+104;
    }
    return rows;
}
fn sensor_direct_f32(payload,index){
    sd_clear();if db_kind(payload)!=3 || db_bytes(payload)!=64 || index<0 || index>15{return sd_error("Float access requires a64-byte sensor payload and index0..15.");}
    let bits=sd_u32(db_word(payload)+index*4);let sign=(bits&2147483648)<<32;let exponent=(bits>>23)&255;let fraction=bits&8388607;
    if exponent==255{return db_real(sign|0x7ff0000000000000|(fraction<<29));}
    if !exponent{
        if !fraction{return db_real(sign);}
        exponent=897;while !(fraction&8388608){fraction=fraction<<1;exponent=exponent-1;}
        return db_real(sign|(exponent<<52)|((fraction&8388607)<<29));
    }
    return db_real(sign|((exponent+896)<<52)|(fraction<<29));
}
fn sensor_direct_i64(payload,index){
    sd_clear();if db_kind(payload)!=3 || db_bytes(payload)!=64 || index<0 || index>7{return sd_error("Integer access requires a64-byte sensor payload and index0..7.");}
    return db_int(sd_u64(db_word(payload)+index*8));
}
// Modulo UINT32_MAX, not2^32: the producer skips zero. Cannot detect full
// cycles, sort physical slots, or prove that a running copy was coherent.
fn sensor_direct_counter_distance(newer,older){
    sd_clear();if newer<1 || newer>4294967295 || older<1 || older>4294967295{sd_error("Direct-sensor counters must be in1..4294967295.");return -1;}
    let distance=newer-older;if distance<0{distance=distance+4294967295;}return distance;
}
