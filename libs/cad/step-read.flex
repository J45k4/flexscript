// ISO 10303-21 exchange structure for faceted PCAD imports. A parsed file
// owns its indexed entities and preserves definition order for the catalog.
import "math.flex";
global sr_cursor=0;
global sr_tokens=0;

fn sr_digit(c) {return c>=48 && c<=57;}
fn sr_letter(c) {return (c>=65 && c<=90) || (c>=97 && c<=122);}
fn sr_space(c) {return c==32 || (c>=9 && c<=13);}
fn sr_peek() {
    while !cg_error {
        while sr_space(load8(sr_cursor)) {sr_cursor=sr_cursor+1;}
        if load8(sr_cursor)!=47 || load8(sr_cursor+1)!=42 {return load8(sr_cursor);}
        sr_cursor=sr_cursor+2;
        while load8(sr_cursor) && !(load8(sr_cursor)==42 && load8(sr_cursor+1)==47) {sr_cursor=sr_cursor+1;}
        if !load8(sr_cursor) {return cg_fail("Unterminated STEP comment");}sr_cursor=sr_cursor+2;
    }
    return 0;
}
fn sr_token() {
    sr_tokens=sr_tokens+1;if sr_tokens>600000 {return cg_fail("STEP token limit exceeded");}
    return cg_step();
}
fn sr_punct(c) {
    if sr_peek()!=c {return cg_fail("Unexpected punctuation in STEP exchange data");}
    sr_cursor=sr_cursor+1;return sr_token();
}
fn sr_word(hyphen) {
    let c=sr_peek();let start=sr_cursor;
    if !sr_letter(c) {cg_fail("Expected a STEP keyword");return "";}
    while sr_letter(c) || sr_digit(c) || c==95 || (hyphen && c==45) {sr_cursor=sr_cursor+1;c=load8(sr_cursor);}
    let word=m_slice(start,sr_cursor-start);let i=0;while load8(word+i) {
        c=load8(word+i);if c>=97 && c<=122 {store8(word+i,c-32);}i=i+1;
    }
    sr_token();return word;
}
fn sr_section(name) {
    if !m_eq(sr_word(1),name) {return cg_fail(m_cat("Expected STEP section ",name));}return sr_punct(59);
}
fn sr_reference() {
    sr_cursor=sr_cursor+1;let id=0;
    while sr_digit(load8(sr_cursor)) {
        id=id*10+load8(sr_cursor)-48;if id>999999999 {return cg_fail("STEP reference exceeds its bound");}sr_cursor=sr_cursor+1;
    }
    if !id {return cg_fail("Invalid STEP reference");}sr_token();return id;
}
fn sr_string() {
    sr_cursor=sr_cursor+1;let b=m_buffer();let start=sr_cursor;
    while load8(sr_cursor) {
        if load8(sr_cursor)==39 {
            m_append(b,start,sr_cursor-start);sr_cursor=sr_cursor+1;
            if load8(sr_cursor)!=39 {sr_token();return j_text(m_data(b));}
            start=sr_cursor;
        }
        sr_cursor=sr_cursor+1;
    }
    return cg_fail("Unterminated STEP string");
}
fn sr_numeric() {
    let start=sr_cursor;let c=load8(sr_cursor);if c==43 || c==45 {sr_cursor=sr_cursor+1;}
    let digits=0;while sr_digit(load8(sr_cursor)) {digits=digits+1;sr_cursor=sr_cursor+1;}
    if load8(sr_cursor)==46 {
        sr_cursor=sr_cursor+1;while sr_digit(load8(sr_cursor)) {digits=digits+1;sr_cursor=sr_cursor+1;}
    }
    if !digits {return cg_fail("Expected a STEP number");}
    c=load8(sr_cursor);if c==69 || c==101 {
        sr_cursor=sr_cursor+1;c=load8(sr_cursor);if c==43 || c==45 {sr_cursor=sr_cursor+1;}
        if !sr_digit(load8(sr_cursor)) {return cg_fail("Invalid STEP exponent");}
        while sr_digit(load8(sr_cursor)) {sr_cursor=sr_cursor+1;}
    }
    sr_token();return j_new(6,m_slice(start,sr_cursor-start));
}
// STEP-only node kinds 8, 9 and 10 hold references, typed instances and literals.
fn sr_value(depth) {
    let c=sr_peek();if c==40 {return sr_group(depth);}
    if sr_letter(c) {return sr_instance(sr_word(0),depth);}
    if c==39 {return sr_string();}if c==35 {return j_new(8,sr_reference());}
    if c==46 && sr_letter(load8(sr_cursor+1)) {
        sr_cursor=sr_cursor+1;let word=sr_word(0);if load8(sr_cursor)!=46 {return cg_fail("Invalid STEP enumeration");}
        sr_cursor=sr_cursor+1;return j_new(10,m_cat(".",m_cat(word,".")));
    }
    if c==36 || c==42 {let value=m_slice(sr_cursor,1);sr_punct(c);return j_new(10,value);}
    return sr_numeric();
}
fn sr_group(depth) {
    if depth>24 {return cg_fail("STEP nesting limit exceeded");}
    if !sr_punct(40) {return 0;}let group=j_array();let tail=group+16;
    if sr_peek()!=41 {
        let more=1;while more && !cg_error {
            let item=sr_value(depth+1);if !item {return 0;}store64(tail,item);tail=item+24;
            more=sr_peek()!=41;if more && !sr_punct(44) {return 0;}
        }
    }
    if !sr_punct(41) {return 0;}return group;
}
fn sr_instance(word,depth) {
    let args=sr_group(depth);if !args {return 0;}let row=j_new(9,word);store64(row+16,load64(args+16));return row;
}
fn sr_definition() {
    if sr_peek()!=40 {return sr_instance(sr_word(0),0);}
    sr_punct(40);let group=j_array();let tail=group+16;
    while sr_letter(sr_peek()) {
        let row=sr_instance(sr_word(0),0);if !row {return 0;}store64(tail,row);tail=row+24;
    }
    if !load64(group+16) {return cg_fail("Empty complex STEP entity");}
    if !sr_punct(41) {return 0;}return group;
}
fn sr_arg(row,index) {
    if !row {return 0;}let item=load64(row+16);while item && index>0 {item=load64(item+24);index=index-1;}return item;
}
fn sr_type(node,type) {return j_kind(node)==9 && m_eq(j_value(node),type);}
fn sr_component(node,type) {
    if sr_type(node,type) {return node;}if j_kind(node)!=3 {return 0;}
    let row=sr_arg(node,0);let match=0;while row {
        if sr_type(row,type) {if match {return 0;}match=row;}row=load64(row+24);
    }return match;
}
// A fixed bucket table supports sparse nine-digit IDs. Collisions and scans
// consume the shared CAD work budget. Each entry also links to its successor.
fn sr_find(file,id) {
    if !file || id<=0 {return 0;}let row=load64(load64(file)+(id%8191)*8);
    while row && load64(row)!=id {if !cg_step() {return 0;}row=load64(row+16);}return row;
}
fn sr_resolve(file,ref,type) {
    if j_kind(ref)!=8 {return cg_fail("Expected a STEP entity reference");}
    let entry=sr_find(file,j_value(ref));if !entry {return cg_fail("Missing referenced STEP entity");}
    let node=load64(entry+8);if type && !sr_type(node,type) {return cg_fail(m_cat("Expected STEP entity ",type));}return node;
}
fn cad_step_read(text) {
    cg_begin();if !text || m_len(text)>2097152 {return cg_fail("STEP input exceeds 2 MiB");}
    sr_cursor=text;sr_tokens=0;
    if !sr_section("ISO-10303-21") || !sr_section("HEADER") {return 0;}
    let word=sr_word(0);while !cg_error && !m_eq(word,"ENDSEC") {
        if !sr_instance(word,0) || !sr_punct(59) {return 0;}word=sr_word(0);
    }
    if !sr_punct(59) || !sr_section("DATA") {return 0;}
    let file=m_take(16);let buckets=m_take(8191*8);let i=0;
    while i<8191 {store64(buckets+i*8,0);i=i+1;}store64(file,buckets);store64(file+8,0);
    let tail=file+8;let count=0;
    while sr_peek()==35 && !cg_error {
        let id=sr_reference();if !id || !sr_punct(61) {return 0;}if sr_find(file,id) {return cg_fail("Duplicate STEP entity ID");}
        count=count+1;if count>50000 {return cg_fail("STEP entity limit exceeded");}
        let node=sr_definition();if !node || !sr_punct(59) {return 0;}
        let bucket=buckets+(id%8191)*8;let entry=m_take(32);store64(entry,id);store64(entry+8,node);
        store64(entry+16,load64(bucket));store64(entry+24,0);store64(bucket,entry);store64(tail,entry);tail=entry+24;
    }
    if !sr_section("ENDSEC") || !sr_section("END-ISO-10303-21") {return 0;}
    if sr_peek() {return cg_fail("Unexpected content after STEP exchange");}if cg_error {return 0;}return file;
}
fn sr_escape_width(p) {
    if load8(p)!=92 || (load8(p+1)!=88 && load8(p+1)!=120) {return 0;}
    let width=load8(p+2);if (width!=50 && width!=52) || load8(p+3)!=92 {return 0;}return (width-48)*2;
}
fn sr_name(raw,id) {
    let p="";if j_kind(raw)==2 {p=j_value(raw);}let b=m_buffer();
    while load8(p) {
        let c=load8(p);let width=sr_escape_width(p);
        if width {
            p=p+4;let high=0;let valid=1;let run=m_buffer();
            while load8(p) && load8(p)!=92 && valid {
                let code=0;let i=0;while i<width && j_hex(load8(p))>=0 {code=code*16+j_hex(load8(p));p=p+1;i=i+1;}
                if i!=width {valid=0;}
                else if width==4 && code>=55296 && code<=56319 && !high {high=code;}
                else {
                    if high && code>=56320 && code<=57343 {code=65536+(high-55296)*1024+code-56320;}
                    else if high || (code>=55296 && code<=57343) || code>1114111 {valid=0;}
                    high=0;if code<32 || code==127 {code=32;}if valid {j_utf8(run,code);}
                }
            }
            while load8(p) && load8(p)!=92 {p=p+1;}
            if load8(p)==92 && (load8(p+1)==88 || load8(p+1)==120) && load8(p+2)==48 && load8(p+3)==92 {p=p+4;}else {valid=0;}
            if valid && !high {m_text(b,m_data(run));}else {m_text(b,"?");}
        }else {
            if c==92 && load8(p+1)==92 {p=p+1;}if c<32 || c==127 {m_text(b," ");}else {m_append(b,p,1);}p=p+1;
        }
    }
    let s=m_data(b);while load8(s)==32 {s=s+1;}let n=m_len(s);while n && load8(s+n-1)==32 {n=n-1;}
    if n>96 {n=96;while n && (load8(s+n)&192)==128 {n=n-1;}}
    if !n {return m_cat("STEP solid #",m_int(id));}return m_slice(s,n);
}
fn cad_step_bodies(file) {
    cg_begin();if !file {return cg_fail("Missing STEP file");}
    let out=j_array();let row=load64(file+8);let count=0;while row {
        let node=load64(row+8);if sr_type(node,"FACETED_BREP") {
            count=count+1;if count>128 {return cg_fail("STEP exceeds 128 faceted solids");}
            let item=j_object();cg_j_int(item,"id",load64(row));cg_j_text(item,"name",sr_name(sr_arg(node,0),load64(row)));j_add(out,0,item);
        }row=load64(row+24);
    }
    if !count {return cg_fail("STEP file has no supported FACETED_BREP solids");}return out;
}
