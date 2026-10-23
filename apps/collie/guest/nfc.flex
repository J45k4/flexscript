// Portable NDEF records and wire codec. No Android calls or host filesystem access.
fn ndef_error(code,message){db_last_error=message;db_last_error_details=db_list();db_add(db_last_error_details,db_text(code));db_add(db_last_error_details,db_text(message));return 0;}
fn ndef_clear(){db_last_error=0;db_last_error_details=0;return 0;}
fn ndef_record(tnf,type,id,payload){
    if tnf<0 || tnf>5 || db_kind(type)!=3 || db_kind(id)!=3 || db_kind(payload)!=3{return ndef_error("invalid_ndef","NDEF records require TNF0..5 and binary type/id/payload.");}
    if db_bytes(type)>255 || db_bytes(id)>255{return ndef_error("size_limit","NDEF type and ID fields are at most255 bytes.");}
    if tnf==0 && (db_bytes(type) || db_bytes(id) || db_bytes(payload)){return ndef_error("invalid_ndef","An empty-TNF record cannot carry type, ID or payload.");}
    if tnf==5 && db_bytes(type){return ndef_error("invalid_ndef","An unknown-TNF record cannot carry a type.");}
    let row=db_list();db_add(row,db_int(tnf));db_add(row,type);db_add(row,id);db_add(row,payload);return row;
}
fn ndef_encode(records){
    ndef_clear();if db_kind(records)!=5 || !db_count(records){return ndef_error("invalid_ndef","An NDEF message requires at least one record.");}
    let size=0;let i=0;while i<db_count(records){let r=db_at(records,i);if db_kind(r)!=5 || db_count(r)!=4 || db_kind(db_at(r,0))!=1{return ndef_error("invalid_ndef","Use records built by ndef_record.");}
        if !ndef_record(db_word(db_at(r,0)),db_at(r,1),db_at(r,2),db_at(r,3)){return 0;}let n=db_bytes(db_at(r,3));size=size+3+db_bytes(db_at(r,1))+db_bytes(db_at(r,2))+n;if n>255{size=size+3;}if db_bytes(db_at(r,2)){size=size+1;}if size>32768{return ndef_error("size_limit","NDEF message exceeds the32768-byte VM blob bound.");}i=i+1;}
    let p=alloc(size);let at=0;i=0;while i<db_count(records){let r=db_at(records,i);let type=db_at(r,1);let id=db_at(r,2);let payload=db_at(r,3);let n=db_bytes(payload);let flags=db_word(db_at(r,0));if i==0{flags=flags|128;}if i==db_count(records)-1{flags=flags|64;}if n<=255{flags=flags|16;}if db_bytes(id){flags=flags|8;}
        store8(p+at,flags);store8(p+at+1,db_bytes(type));at=at+2;if n<=255{store8(p+at,n);at=at+1;}else{store8(p+at,(n>>24)&255);store8(p+at+1,(n>>16)&255);store8(p+at+2,(n>>8)&255);store8(p+at+3,n&255);at=at+4;}if db_bytes(id){store8(p+at,db_bytes(id));at=at+1;}
        db_copy(p+at,db_word(type),db_bytes(type));at=at+db_bytes(type);db_copy(p+at,db_word(id),db_bytes(id));at=at+db_bytes(id);db_copy(p+at,db_word(payload),n);at=at+n;i=i+1;}
    return db_blob(p,size);
}
fn ndef_parse(value){
    ndef_clear();if db_kind(value)!=3 || !db_bytes(value){return ndef_error("invalid_ndef","Parse a nonempty NDEF binary blob.");}let p=db_word(value);let bytes=db_bytes(value);let at=0;let first=1;let ended=0;let chunk=0;let chunk_tnf=0;let chunk_type=0;let chunk_id=0;let chunk_bytes=0;let scratch=alloc(bytes);let records=db_list();
    while at<bytes{
        if ended || bytes-at<3{return ndef_error("invalid_ndef","NDEF has trailing data or a truncated header.");}let flags=load8(p+at);let tnf=flags&7;let type_bytes=load8(p+at+1);at=at+2;
        if ((flags&128)!=0)!=first || ((flags&32)!=0 && (flags&64)!=0){return ndef_error("invalid_ndef","NDEF message/chunk flags are inconsistent.");}first=0;let n=0;if flags&16{n=load8(p+at);at=at+1;}else{if bytes-at<4{return ndef_error("invalid_ndef","NDEF has a truncated long length.");}n=(load8(p+at)<<24)|(load8(p+at+1)<<16)|(load8(p+at+2)<<8)|load8(p+at+3);at=at+4;}
        let id_bytes=0;if flags&8{if at>=bytes{return ndef_error("invalid_ndef","NDEF has a truncated ID length.");}id_bytes=load8(p+at);at=at+1;}
        if n<0 || n>bytes-at || type_bytes+id_bytes>bytes-at-n{return ndef_error("invalid_ndef","NDEF fields run past the input.");}
        if chunk{if tnf!=6 || type_bytes || id_bytes || flags&8{return ndef_error("invalid_ndef","NDEF continuation must use unchanged TNF without type/ID.");}}else{if tnf==6 || tnf==7 || (tnf==0 && (type_bytes || id_bytes || n || flags&32)) || (tnf==5 && type_bytes){return ndef_error("invalid_ndef","NDEF record TNF and field lengths disagree.");}}
        let type=db_blob(p+at,type_bytes);at=at+type_bytes;let id=db_blob(p+at,id_bytes);at=at+id_bytes;
        if chunk || flags&32{
            if !chunk{chunk=1;chunk_tnf=tnf;chunk_type=type;chunk_id=id;chunk_bytes=0;}
            if chunk_bytes+n>bytes{return ndef_error("size_limit","Chunked NDEF payload exceeds its input bound.");}db_copy(scratch+chunk_bytes,p+at,n);chunk_bytes=chunk_bytes+n;
            if !(flags&32){let record=ndef_record(chunk_tnf,chunk_type,chunk_id,db_blob(scratch,chunk_bytes));if !record || !db_add(records,record){return ndef_error("size_limit","Too many NDEF records.");}chunk=0;}
        }else{let record=ndef_record(tnf,type,id,db_blob(p+at,n));if !record || !db_add(records,record){return ndef_error("size_limit","Too many NDEF records.");}}
        at=at+n;if flags&64{ended=1;}
    }
    if !ended || chunk{return ndef_error("invalid_ndef","NDEF message is missing its final record or chunk.");}return records;
}
