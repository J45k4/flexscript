// Recoverable parser for files and remote responses; malformed input is a notice,
// never a process-wide assertion. Numeric metadata keeps its original spelling.
import "../../lib/state.flex";
global sj_source=0;global sj_at=0;global sj_depth=0;global sj_bad=0;
fn sj_space(){let c=load8(sj_source+sj_at);while c==32 || c==9 || c==10 || c==13{sj_at=sj_at+1;c=load8(sj_source+sj_at);}return 0;}
fn sj_expect(c){if load8(sj_source+sj_at)!=c{sj_bad=1;return 0;}sj_at=sj_at+1;return 1;}
fn sj_hex(){let n=0;let i=0;while i<4{let c=load8(sj_source+sj_at);let digit=-1;if c>=48 && c<=57{digit=c-48;}if c>=65 && c<=70{digit=c-55;}if c>=97 && c<=102{digit=c-87;}if digit<0{sj_bad=1;return 0;}n=(n<<4)|digit;sj_at=sj_at+1;i=i+1;}return n;}
fn sj_string(){if !sj_expect(34){return "";}let out=h_buffer();while !sj_bad && load8(sj_source+sj_at)!=34{let c=load8(sj_source+sj_at);if c<32{sj_bad=1;return "";}sj_at=sj_at+1;if c==92{c=load8(sj_source+sj_at);if !c{sj_bad=1;return "";}sj_at=sj_at+1;if c==117{let cp=sj_hex();if !cp{sj_bad=1;return "";}if cp>=55296 && cp<=56319{if !sj_expect(92) || !sj_expect(117){return "";}let low=sj_hex();if low<56320 || low>57343{sj_bad=1;return "";}cp=65536+((cp-55296)<<10)+low-56320;}else if cp>=56320 && cp<=57343{sj_bad=1;return "";}j_utf8(out,cp);c=-1;}else if c==110{c=10;}else if c==114{c=13;}else if c==116{c=9;}else if c==98{c=8;}else if c==102{c=12;}else if c!=34 && c!=92 && c!=47{sj_bad=1;return "";}}if c>=0{let p=h_take(1);store8(p,c);h_append(out,p,1);}}sj_expect(34);return h_data(out);}
fn sj_digit(c){return c>=48 && c<=57;}
fn sj_value(){sj_space();sj_depth=sj_depth+1;if sj_depth>64{sj_bad=1;return 0;}let c=load8(sj_source+sj_at);let out=0;
    if c==34{out=j_string(sj_string());}
    else if c==91 || c==123{sj_at=sj_at+1;let end=93;out=j_array();if c==123{out=j_object();end=125;}sj_space();if load8(sj_source+sj_at)!=end{let more=1;while more && !sj_bad{let key=0;if c==123{key=sj_string();sj_space();sj_expect(58);}let value=sj_value();if sj_bad{return 0;}if c==123{if j_count(out)>=4096 || j_get(out,key){sj_bad=1;return 0;}j_set(out,key,value);}else{if j_count(out)>=65536{sj_bad=1;return 0;}j_push(out,value);}sj_space();if load8(sj_source+sj_at)==44{sj_at=sj_at+1;sj_space();}else{more=0;}}}sj_expect(end);}
    else if h_starts(sj_source+sj_at,"true"){sj_at=sj_at+4;out=j_bool(1);}
    else if h_starts(sj_source+sj_at,"false"){sj_at=sj_at+5;out=j_bool(0);}
    else if h_starts(sj_source+sj_at,"null"){sj_at=sj_at+4;out=cj_null();}
    else{let start=sj_at;let negative=c==45;if negative{sj_at=sj_at+1;}let digits=sj_at;c=load8(sj_source+sj_at);if c==48{sj_at=sj_at+1;}else if c>=49 && c<=57{while sj_digit(load8(sj_source+sj_at)){sj_at=sj_at+1;}}else{sj_bad=1;return 0;}let count=sj_at-digits;let raw=count>18;if load8(sj_source+sj_at)==46{raw=1;sj_at=sj_at+1;if !sj_digit(load8(sj_source+sj_at)){sj_bad=1;return 0;}while sj_digit(load8(sj_source+sj_at)){sj_at=sj_at+1;}}c=load8(sj_source+sj_at);if c==69 || c==101{raw=1;sj_at=sj_at+1;c=load8(sj_source+sj_at);if c==43 || c==45{sj_at=sj_at+1;}if !sj_digit(load8(sj_source+sj_at)){sj_bad=1;return 0;}while sj_digit(load8(sj_source+sj_at)){sj_at=sj_at+1;}}if raw{out=j_node(6,h_slice(sj_source+start,sj_at-start));}else{let number=h_number(h_slice(sj_source+digits,count));if negative{number=-number;}out=j_int(number);}}
    sj_depth=sj_depth-1;return out;
}
fn sj_parse(text){sj_source=text;sj_at=0;sj_depth=0;sj_bad=0;let out=sj_value();sj_space();if sj_bad || load8(sj_source+sj_at){return 0;}return out;}
