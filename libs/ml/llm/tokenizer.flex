// Byte-level BPE in Flexscript. GLib supplies Unicode NFC and PCRE token splits;
// vocab lookup, ranked merges, added tokens and byte decoding stay here.
import "../../../scripts/lib/json.flex";
import "../../../lib/ffi.flex";
import "limits.flex";
global qt_vocab=0;
global qt_merges=0;
global qt_tokens=0;
global qt_bytes=0;
global qt_added=0;
global qt_regex=0;
global qt_glib=0;
global qt_normalize=0;
global qt_match=0;
global qt_pos=0;
global qt_next=0;
global qt_free=0;
global qt_match_free=0;
global qt_overflow=0;
global qt_limit=40959;
fn qt_token_add(result,id) {if h_count(result)<qt_limit {h_add_sized(result,id);}else {qt_overflow=1;}return 0;}
fn qt_hash(s) {let h=2166136261;let i=0;while load8(s+i) {h=((h^load8(s+i))*16777619)&4294967295;i=i+1;}return h&524287;}
fn qt_lookup(s,insert,id) {
    let at=qt_hash(s);let tries=0;
    while tries<524288 {let slot=qt_vocab+at*16;let key=load64(slot);
        if !key {h_assert(insert,h_cat("token missing from vocabulary: ",s));store64(slot,s);store64(slot+8,id);return id;}
        if h_equal(key,s) {h_assert(!insert,"duplicate vocabulary spelling");return load64(slot+8);}
        at=(at+1)&524287;tries=tries+1;
    }h_die("vocabulary hash table full");return 0;
}
fn qt_pair(a,b,insert,value) {
    let key=((a+1)<<32)|(b+1);let at=((a*2654435761)^b)&524287;let tries=0;
    while tries<524288 {let slot=qt_merges+at*16;let old=load64(slot);
        if !old {if !insert {return 0;}store64(slot,key);store64(slot+8,value);return value;}
        if old==key {h_assert(!insert,"duplicate BPE merge");return load64(slot+8);}
        at=(at+1)&524287;tries=tries+1;
    }h_die("merge hash table full");return 0;
}
fn qt_vocab_read() {
    j_expect(123);j_ws();let count=0;
    while load8(j_source+j_offset)!=125 {
        let s=j_parse_string();j_ws();j_expect(58);let id=j_parse_value();h_assert(j_kind(id)==1,"invalid vocabulary ID");let n=j_value(id);
        h_assert(n>=0 && n<200000 && !load64(qt_tokens+n*8),"invalid/duplicate vocabulary ID");qt_lookup(s,1,n);store64(qt_tokens+n*8,s);count=count+1;j_ws();
        if load8(j_source+j_offset)==44 {j_offset=j_offset+1;j_ws();}else {h_assert(load8(j_source+j_offset)==125,"invalid vocabulary object");}
    }j_expect(125);h_assert(count>256,"empty vocabulary");return 0;
}
fn qt_merges_read() {
    j_expect(91);j_ws();let rank=0;
    while load8(j_source+j_offset)!=93 {
        j_expect(91);j_ws();let a=j_parse_string();j_ws();j_expect(44);j_ws();let b=j_parse_string();j_ws();j_expect(93);
        let left=qt_lookup(a,0,0);let right=qt_lookup(b,0,0);let result=qt_lookup(h_cat(a,b),0,0);
        qt_pair(left,right,1,(result<<32)|(rank+1));rank=rank+1;j_ws();
        if load8(j_source+j_offset)==44 {j_offset=j_offset+1;j_ws();}else {h_assert(load8(j_source+j_offset)==93,"invalid merge list");}
    }j_expect(93);return 0;
}
fn qt_model_read() {
    j_expect(123);j_ws();while load8(j_source+j_offset)!=125 {
        let key=j_parse_string();j_ws();j_expect(58);j_ws();
        if h_equal(key,"vocab") {qt_vocab_read();}else if h_equal(key,"merges") {qt_merges_read();}
        else {let value=j_parse_value();if h_equal(key,"type") {h_assert(h_equal(j_value(value),"BPE"),"requires BPE tokenizer");}
            if h_equal(key,"dropout") {h_assert(j_kind(value)==0,"BPE dropout is unsupported");}
            if h_equal(key,"ignore_merges") || h_equal(key,"byte_fallback") {h_assert(!j_value(value),"unsupported BPE option");}}
        j_ws();if load8(j_source+j_offset)==44 {j_offset=j_offset+1;j_ws();}else {h_assert(load8(j_source+j_offset)==125,"invalid tokenizer model");}
    }j_expect(125);return 0;
}
fn qt_open(path) {
    qt_vocab=alloc(524288*16);qt_merges=alloc(524288*16);qt_tokens=alloc(200000*8);qt_bytes=alloc(256*8);
    j_source=h_read(path);j_offset=0;j_depth=0;j_ws();j_expect(123);j_ws();let pretokenizer=0;let normalizer=0;
    while load8(j_source+j_offset)!=125 {
        let key=j_parse_string();j_ws();j_expect(58);j_ws();
        if h_equal(key,"model") {qt_model_read();}else {let value=j_parse_value();if h_equal(key,"added_tokens") {qt_added=value;}if h_equal(key,"pre_tokenizer") {pretokenizer=value;}if h_equal(key,"normalizer") {normalizer=value;}}
        j_ws();if load8(j_source+j_offset)==44 {j_offset=j_offset+1;j_ws();}else {h_assert(load8(j_source+j_offset)==125,"invalid tokenizer JSON");}
    }j_expect(125);j_ws();h_assert(!load8(j_source+j_offset),"trailing tokenizer data");h_assert(qt_added && pretokenizer,"missing tokenizer metadata");
    let i=0;let extension=256;
    while i<256 {let code=i;if !(i>=33 && i<=126) && !(i>=161 && i<=172) && !(i>=174) {code=extension;extension=extension+1;}
        let b=h_buffer();j_utf8(b,code);store64(qt_bytes+i*8,qt_lookup(h_data(b),0,0));i=i+1;}
    i=0;while i<j_count(qt_added) {let item=j_at(qt_added,i);let id=j_n(item,"id");h_assert(id>=0 && id<200000,"invalid added token ID");store64(qt_tokens+id*8,j_s(item,"content"));i=i+1;}
    h_assert(normalizer && h_equal(j_s(normalizer,"type"),"NFC"),"requires NFC tokenizer normalization");
    let sequence=j_need(pretokenizer,"pretokenizers");h_assert(j_count(sequence)==2 && h_equal(j_s(j_at(sequence,0),"type"),"Split") && h_equal(j_s(j_at(sequence,1),"type"),"ByteLevel"),"unsupported pretokenizer sequence");
    h_assert(!j_n(j_at(sequence,1),"add_prefix_space") && !j_n(j_at(sequence,1),"use_regex"),"unsupported ByteLevel pretokenizer options");
    let pattern=j_s(j_need(j_at(sequence,0),"pattern"),"Regex");
    qt_glib=ffi_open("libglib-2.0.so.0");h_assert(qt_glib,"Unicode tokenizer requires libglib-2.0.so.0");let error=alloc(8);
    qt_regex=ffi_call(ffi_symbol(qt_glib,"g_regex_new"),pattern,0,0,error,0,0);h_assert(qt_regex && !load64(error),"cannot compile tokenizer pattern");
    qt_normalize=ffi_symbol(qt_glib,"g_utf8_normalize");qt_match=ffi_symbol(qt_glib,"g_regex_match");qt_pos=ffi_symbol(qt_glib,"g_match_info_fetch_pos");qt_next=ffi_symbol(qt_glib,"g_match_info_next");
    qt_free=ffi_symbol(qt_glib,"g_free");qt_match_free=ffi_symbol(qt_glib,"g_match_info_free");return 0;
}
fn qt_bpe(text,n,result) {
    h_assert(n>0 && n<=16384,"pretoken exceeds 16384 bytes");let ids=h_take(n*8);let count=n;let i=0;
    while i<n {store64(ids+i*8,load64(qt_bytes+load8(text+i)*8));i=i+1;}
    while count>1 {let best=-1;let best_rank=0x7fffffff;let best_value=0;i=0;
        while i<count-1 {let value=qt_pair(load64(ids+i*8),load64(ids+(i+1)*8),0,0);let rank=(value&4294967295)-1;
            if value && rank<best_rank {best=i;best_rank=rank;best_value=value;}i=i+1;}
        if best<0 {i=count;}else {store64(ids+best*8,best_value>>32);i=best+1;while i<count-1 {store64(ids+i*8,load64(ids+(i+1)*8));i=i+1;}count=count-1;}
        if best<0 {i=0;while i<count {qt_token_add(result,load64(ids+i*8));i=i+1;}return 0;}
    }qt_token_add(result,load64(ids));return 0;
}
fn qt_plain(text,n,result) {
    if !n {return 0;}let normalized=ffi_call(qt_normalize,text,n,1,0,0,0);h_assert(normalized,"prompt must be valid UTF-8");let info=alloc(8);let positions=alloc(8);let error=alloc(8);
    let matched=ffi_call_i32(qt_match,qt_regex,normalized,0,info,0,0);let end=0;
    while matched {h_assert(ffi_call_i32(qt_pos,load64(info),0,positions,positions+4,0,0),"tokenizer match failure");
        let begin=load64(positions)&4294967295;let finish=(load64(positions)>>32)&4294967295;h_assert(begin==end && finish>begin,"tokenizer split left unmatched bytes");
        qt_bpe(normalized+begin,finish-begin,result);end=finish;matched=ffi_call_i32(qt_next,load64(info),error,0,0,0,0);h_assert(!load64(error),"tokenizer regex failure");
    }
    h_assert(end==h_len(normalized),"tokenizer did not consume prompt");ffi_call(qt_match_free,load64(info),0,0,0,0,0);ffi_call(qt_free,normalized,0,0,0,0,0);return 0;
}
fn qt_encode_bounded(text) {
    qt_overflow=0;let result=h_vec_sized(qt_limit);let n=h_len(text);let start=0;let i=0;
    while i<n {let found=0;let j=0;
        if load8(text+i)==60 {while j<j_count(qt_added) && !found {let token=j_at(qt_added,j);let content=j_s(token,"content");let length=h_len(content);
            if length<=n-i && h_bytes(text+i,content,length) {qt_plain(text+start,i-start,result);qt_token_add(result,j_n(token,"id"));i=i+length;start=i;found=1;}j=j+1;}}
        if !found {i=i+1;}
    }qt_plain(text+start,n-start,result);return result;
}
fn qt_encode(text) {let result=qt_encode_bounded(text);h_assert(!qt_overflow,h_cat3("prompt exceeds ",h_int(qt_limit)," tokenizer tokens"));return result;}
fn qt_decode(id) {
    h_assert(id>=0 && id<200000 && load64(qt_tokens+id*8),"unknown output token");let s=load64(qt_tokens+id*8);let result=h_buffer();let i=0;
    while load8(s+i) {let c=load8(s+i);i=i+1;if c>=192 {c=((c&31)<<6)|(load8(s+i)&63);i=i+1;}
        if c>=256 {let ordinal=c-256;let b=0;let seen=0;let found=0;while b<256 && !found {
            if !(b>=33 && b<=126) && !(b>=161 && b<=172) && !(b>=174) {if seen==ordinal {c=b;found=1;}seen=seen+1;}b=b+1;}h_assert(found,"invalid ByteLevel codepoint");}
        let byte=h_take(1);store8(byte,c);h_append(result,byte,1);
    }return result;
}
