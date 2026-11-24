// Bounded, nonfatal JSON parser. Nodes: kind,value,first child,next sibling,key.
import "ui/support.flex";
global j_source=0;
global j_pos=0;
global j_size=0;
global j_error=0;

fn j_new(kind,value) {let p=m_take(40);store64(p,kind);store64(p+8,value);store64(p+16,0);store64(p+24,0);store64(p+32,0);return p;}
fn j_kind(p) {if !p {return -1;}return load64(p);}
fn j_value(p) {if !p {return 0;}return load64(p+8);}
fn j_text(text) {return j_new(2,text);}
fn j_number(number) {return j_new(1,number);}
fn j_object() {return j_new(4,0);}
fn j_array() {return j_new(3,0);}
fn j_add(parent,key,value) {
    if !parent || !value {return 0;}store64(value+32,key);let child=load64(parent+16);
    if !child {store64(parent+16,value);}else {while load64(child+24) {child=load64(child+24);}store64(child+24,value);}return value;
}
fn j_get(parent,key) {if j_kind(parent)!=4 {return 0;}let p=load64(parent+16);while p {if m_eq(load64(p+32),key) {return p;}p=load64(p+24);}return 0;}
fn j_string(parent,key) {let p=j_get(parent,key);if j_kind(p)!=2 {return "";}return j_value(p);}
fn j_integer(parent,key) {let p=j_get(parent,key);if j_kind(p)!=1 {return 0;}return j_value(p);}
fn j_ws() {while j_pos<j_size && (load8(j_source+j_pos)==32 || load8(j_source+j_pos)==9 || load8(j_source+j_pos)==10 || load8(j_source+j_pos)==13) {j_pos=j_pos+1;}return 0;}
fn j_hex(c) {if c>=48 && c<=57 {return c-48;}if c>=65 && c<=70 {return c-55;}if c>=97 && c<=102 {return c-87;}return -1;}
fn j_code() {
    if j_pos+4>j_size {j_error=1;return 0;}let n=0;let i=0;while i<4 {let c=j_hex(load8(j_source+j_pos));if c<0 {j_error=1;return 0;}n=n*16+c;j_pos=j_pos+1;i=i+1;}return n;
}
fn j_utf8(b,c) {
    let p=m_take(4);let n=1;
    if c<128 {store8(p,c);}else if c<2048 {n=2;store8(p,192|(c>>6));store8(p+1,128|(c&63));}
    else if c<65536 {n=3;store8(p,224|(c>>12));store8(p+1,128|((c>>6)&63));store8(p+2,128|(c&63));}
    else {n=4;store8(p,240|(c>>18));store8(p+1,128|((c>>12)&63));store8(p+2,128|((c>>6)&63));store8(p+3,128|(c&63));}m_append(b,p,n);return 0;
}
fn j_parse_string() {
    if j_pos>=j_size || load8(j_source+j_pos)!=34 {j_error=1;return "";}j_pos=j_pos+1;let b=m_buffer();
    while j_pos<j_size && !j_error {
        let c=load8(j_source+j_pos);j_pos=j_pos+1;
        if c==34 {return m_data(b);}if c<32 {j_error=1;return "";}
        if c==92 {
            if j_pos>=j_size {j_error=1;return "";}c=load8(j_source+j_pos);j_pos=j_pos+1;
            if c==117 {
                c=j_code();if c>=55296 && c<=56319 {
                    if j_pos+2>j_size || load8(j_source+j_pos)!=92 || load8(j_source+j_pos+1)!=117 {j_error=1;return "";}
                    j_pos=j_pos+2;let low=j_code();if low<56320 || low>57343 {j_error=1;return "";}c=65536+(c-55296)*1024+low-56320;
                }else if c>=56320 && c<=57343 {j_error=1;return "";}
                // Text APIs are zero terminated; reject embedded NUL rather than truncate.
                if !c {j_error=1;return "";}j_utf8(b,c);c=-1;
            }else if c==110 {c=10;}else if c==114 {c=13;}else if c==116 {c=9;}else if c==98 {c=8;}else if c==102 {c=12;}
            else if c!=34 && c!=92 && c!=47 {j_error=1;return "";}
        }
        if c>=0 {let p=m_take(1);store8(p,c);m_append(b,p,1);}
    }j_error=1;return "";
}
fn j_parse_value(depth) {
    j_ws();if depth>32 || j_pos>=j_size {j_error=1;return 0;}let c=load8(j_source+j_pos);
    if c==34 {return j_text(j_parse_string());}
    if c==123 || c==91 {
        let object=c==123;let end=93;let result=j_array();if object {end=125;result=j_object();}j_pos=j_pos+1;j_ws();
        if j_pos<j_size && load8(j_source+j_pos)==end {j_pos=j_pos+1;return result;}
        while !j_error && j_pos<j_size {
            let key=0;if object {key=j_parse_string();if j_get(result,key) {j_error=1;return 0;}j_ws();if j_pos>=j_size || load8(j_source+j_pos)!=58 {j_error=1;return 0;}j_pos=j_pos+1;}
            j_add(result,key,j_parse_value(depth+1));j_ws();if j_pos>=j_size {j_error=1;return 0;}c=load8(j_source+j_pos);j_pos=j_pos+1;
            if c==end {return result;}if c!=44 {j_error=1;return 0;}j_ws();
        }j_error=1;return 0;
    }
    if j_pos+4<=j_size && m_eq(m_slice(j_source+j_pos,4),"true") {j_pos=j_pos+4;return j_new(5,1);}
    if j_pos+5<=j_size && m_eq(m_slice(j_source+j_pos,5),"false") {j_pos=j_pos+5;return j_new(5,0);}
    if j_pos+4<=j_size && m_eq(m_slice(j_source+j_pos,4),"null") {j_pos=j_pos+4;return j_new(0,0);}
    let start=j_pos;let negative=c==45;if negative {j_pos=j_pos+1;}let digits=j_pos;
    if j_pos<j_size && load8(j_source+j_pos)==48 {j_pos=j_pos+1;}
    else {while j_pos<j_size && load8(j_source+j_pos)>=48 && load8(j_source+j_pos)<=57 {j_pos=j_pos+1;}}
    if digits==j_pos {j_error=1;return 0;}
    let raw=0;
    if j_pos<j_size && load8(j_source+j_pos)==46 {raw=1;j_pos=j_pos+1;let fraction=j_pos;while j_pos<j_size && load8(j_source+j_pos)>=48 && load8(j_source+j_pos)<=57 {j_pos=j_pos+1;}if fraction==j_pos {j_error=1;return 0;}}
    if j_pos<j_size && (load8(j_source+j_pos)==101 || load8(j_source+j_pos)==69) {raw=1;j_pos=j_pos+1;if j_pos<j_size && (load8(j_source+j_pos)==43 || load8(j_source+j_pos)==45) {j_pos=j_pos+1;}let exponent=j_pos;while j_pos<j_size && load8(j_source+j_pos)>=48 && load8(j_source+j_pos)<=57 {j_pos=j_pos+1;}if exponent==j_pos {j_error=1;return 0;}}
    let text=m_slice(j_source+start,j_pos-start);if raw {return j_new(6,text);}let n=m_number(text+negative);if n<0 {return j_new(6,text);}if negative {n=-n;}return j_number(n);
}
fn j_parse(text) {j_source=text;j_pos=0;j_size=m_len(text);j_error=0;let value=j_parse_value(0);j_ws();if j_error || j_pos!=j_size {return 0;}return value;}
fn j_signed(n) {if n<0 {if n==0x8000000000000000 {return "-9223372036854775808";}return m_cat("-",m_int(-n));}return m_int(n);}
fn j_write(b,p) {
    let kind=j_kind(p);m_assert(kind!=7,"Raw bytes require explicit transport encoding");if kind<=0 {m_text(b,"null");}else if kind==1 {m_text(b,j_signed(j_value(p)));}else if kind==2 {m_escape(b,j_value(p),1);}
    else if kind==5 {let v="false";if j_value(p) {v="true";}m_text(b,v);}else if kind==6 {m_text(b,j_value(p));}
    else {let open="[";let close="]";if kind==4 {open="{";close="}";}m_text(b,open);let child=load64(p+16);let count=0;while child {if count {m_text(b,",");}if kind==4 {m_escape(b,load64(child+32),1);m_text(b,":");}j_write(b,child);child=load64(child+24);count=count+1;}m_text(b,close);}return 0;
}
fn j_encode(p) {let b=m_buffer();j_write(b,p);return m_data(b);}
