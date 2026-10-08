// Bounded JSON reader/writer used by test fixtures and build reports.
import "host.flex";
global j_source=0;
global j_offset=0;
global j_depth=0;
// Node: type (0 null,1 integer,2 string,3 array,4 object,5 boolean), value.
fn j_node(kind,value) {
    let p=h_take(16);
    store64(p,kind);
    store64(p+8,value);
    return p;
}
fn j_kind(p) {
    return load64(p);
}
fn j_value(p) {
    return load64(p+8);
}
fn j_int(n) {
    return j_node(1,n);
}
fn j_string(s) {
    return j_node(2,s);
}
fn j_array() {
    return j_node(3,h_vec());
}
fn j_object() {
    return j_node(4,h_vec());
}
fn j_bool(n) {
    return j_node(5,n!=0);
}
fn j_push(a,value) {
    h_assert(j_kind(a)==3,"JSON array expected");
    h_add(j_value(a),value);
    return a;
}
fn j_set(o,key,value) {
    h_assert(j_kind(o)==4,"JSON object expected");
    let fields=j_value(o);
    let i=0;
    while i<h_count(fields) {
        let pair=h_at(fields,i);
        if h_equal(load64(pair),key) {
            store64(pair+8,value);
            return o;
        }
        i=i+1;
    }
    let pair=h_take(16);
    store64(pair,key);
    store64(pair+8,value);
    h_add(fields,pair);
    return o;
}
fn j_get(o,key) {
    h_assert(j_kind(o)==4,"JSON object expected");
    let fields=j_value(o);
    let i=0;
    while i<h_count(fields) {
        let pair=h_at(fields,i);
        if h_equal(load64(pair),key) {
            return load64(pair+8);
        }
        i=i+1;
    }
    return 0;
}
fn j_need(o,key) {
    let p=j_get(o,key);
    h_assert(p,h_cat("missing JSON field: ",key));
    return p;
}
fn j_s(o,key) {
    let p=j_need(o,key);
    h_assert(j_kind(p)==2,"JSON string expected");
    return j_value(p);
}
fn j_n(o,key) {
    let p=j_need(o,key);
    h_assert(j_kind(p)==1 || j_kind(p)==5,"JSON number expected");
    return j_value(p);
}
fn j_count(a) {
    h_assert(j_kind(a)==3 || j_kind(a)==4,"JSON collection expected");
    return h_count(j_value(a));
}
fn j_at(a,i) {
    h_assert(j_kind(a)==3,"JSON array expected");
    return h_at(j_value(a),i);
}
fn j_ws() {
    while load8(j_source+j_offset)==32 || load8(j_source+j_offset)==9 || load8(j_source+j_offset)==10 || load8(j_source+j_offset)==13 {
        j_offset=j_offset+1;
    }
    return 0;
}
fn j_expect(c) {
    h_assert(load8(j_source+j_offset)==c,"invalid JSON delimiter");
    j_offset=j_offset+1;
    return 0;
}
fn j_hex4() {
    let n=0;
    let i=0;
    while i<4 {
        let c=load8(j_source+j_offset);
        j_offset=j_offset+1;
        let v=-1;
        if c>=48 && c<=57 {
            v=c-48;
        }else if c>=97 && c<=102 {
            v=c-87;
        }else if c>=65 && c<=70 {
            v=c-55;
        }
        h_assert(v>=0,"invalid JSON unicode escape");
        n=(n<<4)|v;
        i=i+1;
    }
    return n;
}
fn j_utf8(b,n) {
    let p=h_take(4);
    let size=1;
    if n<128 {
        store8(p,n);
    }else if n<2048 {
        size=2;
        store8(p,192|(n>>6));
        store8(p+1,128|(n&63));
    }else if n<65536 {
        size=3;
        store8(p,224|(n>>12));
        store8(p+1,128|((n>>6)&63));
        store8(p+2,128|(n&63));
    }else {
        size=4;
        store8(p,240|(n>>18));
        store8(p+1,128|((n>>12)&63));
        store8(p+2,128|((n>>6)&63));
        store8(p+3,128|(n&63));
    }
    h_append(b,p,size);
    return 0;
}
fn j_parse_string() {
    j_expect(34);
    let b=h_buffer();
    while load8(j_source+j_offset)!=34 {
        let c=load8(j_source+j_offset);
        h_assert(c>=32,"invalid JSON string");
        j_offset=j_offset+1;
        if c==92 {
            c=load8(j_source+j_offset);
            j_offset=j_offset+1;
            if c==117 {
                let n=j_hex4();
                h_assert(n!=0,"JSON text cannot contain zero bytes");
                if n>=55296 && n<=56319 {
                    j_expect(92);
                    j_expect(117);
                    let low=j_hex4();
                    h_assert(low>=56320 && low<=57343,"invalid JSON surrogate");
                    n=65536+((n-55296)<<10)+(low-56320);
                }else {
                    h_assert(n<56320 || n>57343,"invalid JSON surrogate");
                }
                j_utf8(b,n);
                c=-1;
            }else if c==110 {
                c=10;
            }else if c==114 {
                c=13;
            }else if c==116 {
                c=9;
            }else if c==98 {
                c=8;
            }else if c==102 {
                c=12;
            }else {
                h_assert(c==34 || c==92 || c==47,"invalid JSON escape");
            }
        }
        if c>=0 {
            let p=h_take(1);
            store8(p,c);
            h_append(b,p,1);
        }
    }
    j_expect(34);
    return h_data(b);
}
fn j_parse_value() {
    j_ws();
    j_depth=j_depth+1;
    h_assert(j_depth<=64,"JSON nesting limit");
    let c=load8(j_source+j_offset);
    let result=0;
    if c==34 {
        result=j_string(j_parse_string());
    } else if c==91 || c==123 {
        j_offset=j_offset+1;
        let end=93;
        result=j_array();
        if c==123 {
            end=125;
            result=j_object();
        }
        j_ws();
        if load8(j_source+j_offset)!=end {
            let more=1;
            while more {
                let key=0;
                if c==123 {
                    key=j_parse_string();
                    j_ws();
                    j_expect(58);
                }
                let value=j_parse_value();
                if c==123 {
                    h_assert(!j_get(result,key),"duplicate JSON object key");
                    j_set(result,key,value);
                }else {
                    j_push(result,value);
                }
                j_ws();
                if load8(j_source+j_offset)==44 {
                    j_offset=j_offset+1;
                    j_ws();
                }else {
                    more=0;
                }
            }
        }
        j_expect(end);
    } else if h_starts(j_source+j_offset,"true") {
        j_offset=j_offset+4;
        result=j_bool(1);
    } else if h_starts(j_source+j_offset,"false") {
        j_offset=j_offset+5;
        result=j_bool(0);
    } else if h_starts(j_source+j_offset,"null") {
        j_offset=j_offset+4;
        result=j_node(0,0);
    } else {
        let negative=0;
        if c==45 {
            negative=1;
            j_offset=j_offset+1;
        }
        let n=0;
        let digits=0;
        let first=load8(j_source+j_offset);
        let limit=-9223372036854775807;
        if negative {
            limit=limit-1;
        }
        while load8(j_source+j_offset)>=48 && load8(j_source+j_offset)<=57 {
            let digit=load8(j_source+j_offset)-48;
            h_assert(n>=limit/10 && (n!=limit/10 || digit<=-(limit%10)),"JSON integer overflow");
            n=n*10-digit;
            digits=digits+1;
            j_offset=j_offset+1;
        }
        h_assert(digits>0 && !(digits>1 && first==48),"invalid JSON integer");
        if !negative {
            n=-n;
        }
        result=j_int(n);
    }
    j_depth=j_depth-1;
    return result;
}
fn j_parse(s) {
    j_source=s;
    j_offset=0;
    j_depth=0;
    let result=j_parse_value();
    j_ws();
    h_assert(!load8(j_source+j_offset),"trailing JSON data");
    return result;
}
fn j_quote(b,s) {
    h_text(b,"\"");
    let i=0;
    while load8(s+i) {
        let c=load8(s+i);
        if c==34 || c==92 {
            h_text(b,"\\");
            h_append(b,s+i,1);
        }else if c<32 {
            let p=h_take(1);
            store8(p,c);
            h_text(b,"\\u00");
            h_text(b,h_hex(p,1));
        }else {
            h_append(b,s+i,1);
        }
        i=i+1;
    }
    h_text(b,"\"");
    return 0;
}
fn j_emit(b,p) {
    let kind=j_kind(p);
    let value=j_value(p);
    if kind==0 {
        h_text(b,"null");
    }else if kind==1 {
        h_text(b,h_int(value));
    }else if kind==2 {
        j_quote(b,value);
    }else if kind==5 {
        if value {
            h_text(b,"true");
        }else {
            h_text(b,"false");
        }
    }else {
        let end="]";
        h_text(b,"[");
        if kind==4 {
            h_text(b,"");
            store8(h_data(b)+h_size(b)-1,123);
            end="}";
        }
        let i=0;
        while i<h_count(value) {
            if i {
                h_text(b,",");
            }
            let item=h_at(value,i);
            if kind==4 {
                j_quote(b,load64(item));
                h_text(b,":");
                item=load64(item+8);
            }
            j_emit(b,item);
            i=i+1;
        }
        h_text(b,end);
    }
    return 0;
}
fn j_dump(p) {
    let b=h_buffer();
    j_emit(b,p);
    return h_data(b);
}
fn j_save(path,p) {
    return h_save(path,h_cat(j_dump(p),"\n"));
}
