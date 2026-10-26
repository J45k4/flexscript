// SDK JSON nodes/writer, with full JSON number syntax for API metadata.
import "../../../scripts/lib/json.flex";

fn c_json_digit(c) {return c>=48 && c<=57;}
fn c_json_value() {
    j_ws();j_depth=j_depth+1;
    h_assert(j_depth<=64,"JSON nesting limit");
    let c=load8(j_source+j_offset);let result=0;
    if c==34 {result=j_string(j_parse_string());}
    else if c==123 || c==91 {
        j_offset=j_offset+1;let end=93;result=j_array();
        if c==123 {end=125;result=j_object();}
        j_ws();let more=load8(j_source+j_offset)!=end;
        while more {
            let key=0;
            if c==123 {key=j_parse_string();j_ws();j_expect(58);}
            let value=c_json_value();
            if c==123 {
                h_assert(!j_get(result,key),"duplicate JSON object key");j_set(result,key,value);
            }else {j_push(result,value);}
            j_ws();
            if load8(j_source+j_offset)==44 {j_offset=j_offset+1;j_ws();}
            else {more=0;}
        }
        j_expect(end);
    }else if h_starts(j_source+j_offset,"true") {j_offset=j_offset+4;result=j_bool(1);}
    else if h_starts(j_source+j_offset,"false") {j_offset=j_offset+5;result=j_bool(0);}
    else if h_starts(j_source+j_offset,"null") {j_offset=j_offset+4;result=j_node(0,0);}
    else {
        let start=j_offset;let negative=load8(j_source+j_offset)==45;
        if negative {j_offset=j_offset+1;}
        let digits=j_offset;
        if load8(j_source+j_offset)==48 {j_offset=j_offset+1;}
        else {
            h_assert(load8(j_source+j_offset)>=49 && load8(j_source+j_offset)<=57,"invalid JSON number");
            while c_json_digit(load8(j_source+j_offset)) {j_offset=j_offset+1;}
        }
        let count=j_offset-digits;let raw=count>18;
        if load8(j_source+j_offset)==46 {
            raw=1;j_offset=j_offset+1;
            h_assert(c_json_digit(load8(j_source+j_offset)),"invalid JSON fraction");
            while c_json_digit(load8(j_source+j_offset)) {j_offset=j_offset+1;}
        }
        c=load8(j_source+j_offset);
        if c==101 || c==69 {
            raw=1;j_offset=j_offset+1;c=load8(j_source+j_offset);
            if c==43 || c==45 {j_offset=j_offset+1;}
            h_assert(c_json_digit(load8(j_source+j_offset)),"invalid JSON exponent");
            while c_json_digit(load8(j_source+j_offset)) {j_offset=j_offset+1;}
        }
        if raw {
            // Kind 6 retains exact numeric text without floating conversion;
            // the shared writer validates the token before emitting it.
            result=j_node(6,h_slice(j_source+start,j_offset-start));
        }else {
            let number=h_number(h_slice(j_source+digits,count));
            if negative {number=-number;}result=j_int(number);
        }
    }
    j_depth=j_depth-1;return result;
}
fn c_json(text) {
    j_source=text;j_offset=0;j_depth=0;let result=c_json_value();j_ws();
    h_assert(!load8(j_source+j_offset),"trailing JSON data");return result;
}
fn c_string(object,key) {
    if !object || j_kind(object)!=4 {return 0;}
    let value=j_get(object,key);
    if !value || j_kind(value)!=2 {return 0;}
    return j_value(value);
}
fn c_flag(object,key) {
    if !object || j_kind(object)!=4 {return 0;}
    let value=j_get(object,key);
    return value && (j_kind(value)==5 || j_kind(value)==1) && j_value(value)!=0;
}
fn c_error(message) {
    let result=j_object();j_set(result,"error",j_string(message));return result;
}
// A bounded file reader for credentials, replay files and worker requests.
fn c_read(path,limit) {
    let fd=syscall(2,path,0x80000,0,0,0,0);if fd<0 {return 0;}
    let output=h_buffer();let scratch=h_take(4096);let more=1;let ok=1;
    while more {
        let n=syscall(0,fd,scratch,4096,0,0,0);
        if n>0 {
            if h_size(output)+n>limit {ok=0;more=0;}
            else {h_append(output,scratch,n);}
        }else if n!=-4 {more=0;if n<0 {ok=0;}}
    }
    h_close(fd);
    if !ok || h_len(h_data(output))!=h_size(output) {return 0;}
    return h_data(output);
}
