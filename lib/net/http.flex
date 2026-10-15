import "bytes.flex";
// HTTP/1.1 client framing (RFC9112). One transaction; caller-owned6144 bytes.
// Response states: idle0, headers1, fixed2, EOF3, chunk-size4, chunk-data5,
// chunk-CRLF6, trailers7, complete8, failed9. No allocation/device calls.
global hp_work=0;
global hp_request=0;
global hp_request_size=0;
global hp_request_ready=0;
global hp_request_host=0;
global hp_request_length=0;
global hp_request_keep=0;
global hp_head=0;
global hp_headers=0;
global hp_header_used=0;
global hp_header_end=0;
global hp_trailer_start=0;
global hp_header_start=0;
global hp_fields=0;
global hp_line=0;
global hp_line_size=0;
global hp_cr=0;
global hp_chunk_cr=0;
global hp_body=0;
global hp_body_used=0;
global hp_received=0;
global hp_limit=16777216;
global hp_state=0;
global hp_error=0;
global hp_status=0;
global hp_minor=0;
global hp_final_headers=0;
global hp_reusable=0;
global hp_remaining=0;
global hp_length= -1;
global hp_transfer=0;
global hp_close=0;
global hp_keep=0;
global hp_interim=0;
global hp_meta=0;
global hp_field_size=0;
fn hp_fail(error) {hp_state=9;hp_error=error;hp_reusable=0;return error;}
fn hp_init(work,capacity) {if work<=0 || capacity<6144 {return -22;}hp_work=work;hp_request=work;hp_headers=work+2048;hp_body=work+4096;hp_line=work+5120;hp_state=0;hp_error=0;hp_body_used=0;hp_request_ready=0;hp_final_headers=0;hp_header_used=0;hp_received=0;hp_limit=16777216;return 0;}
fn hp_set_limit(size) {if size<0 || size>2147483647 {return -22;}if hp_state && hp_state!=8 && hp_state!=9 {return -16;}hp_limit=size;return 0;}
fn hp_reset_fields() {hp_status=0;hp_minor=0;hp_header_used=0;hp_header_start=0;hp_fields=0;hp_length= -1;hp_transfer=0;hp_close=0;hp_keep=0;hp_cr=0;return 0;}
fn hp_name_valid(p,n) {if !p || n<1 || n>128 {return 0;}let i=0;while i<n {if !nb_token(load8(p+i)) {return 0;}i=i+1;}return 1;}
fn hp_value_valid(p,n) {if n<0 || (n && !p) {return 0;}let i=0;while i<n {let c=load8(p+i);if (c<32 && c!=9) || c==127 {return 0;}i=i+1;}return 1;}
fn hp_target_valid(p,n) {if !p || n<1 || n>1536 || (load8(p)!=47 && !(n==1 && load8(p)==42)) {return 0;}let i=0;while i<n {let c=load8(p+i);if c<33 || c>126 || c==35 {return 0;}if c==37 {if i+2>=n || nb_hex(load8(p+i+1))<0 || nb_hex(load8(p+i+2))<0 {return 0;}i=i+2;}i=i+1;}return 1;}
fn hp_begin(method,method_size,target,target_size,body_length,keep_alive) {
    if !hp_work {return -19;}if hp_state && hp_state!=8 && hp_state!=9 {return -16;}if hp_body_used {return -16;}
    if !hp_name_valid(method,method_size) || !hp_target_valid(target,target_size) || body_length< -1 || body_length>2147483647 || keep_alive<0 || keep_alive>1 {return -22;}
    if nb_ci(method,method_size,"CONNECT",7) {return -95;}if target_size==1 && load8(target)==42 && !(method_size==7 && nb_equal(method,"OPTIONS",7)) {return -22;}if method_size+target_size+12>2048 {return -90;}
    hp_reset_fields();hp_head=method_size==4 && nb_equal(method,"HEAD",4);hp_request_length=body_length;hp_request_keep=keep_alive;hp_request_host=0;hp_request_ready=0;hp_request_size=0;hp_body_used=0;hp_received=0;hp_final_headers=0;hp_error=0;hp_interim=0;hp_meta=0;hp_reusable=0;hp_line_size=0;hp_chunk_cr=0;hp_state=1;
    nb_copy(hp_request,method,method_size);hp_request_size=method_size;store8(hp_request+hp_request_size,32);hp_request_size=hp_request_size+1;nb_copy(hp_request+hp_request_size,target,target_size);hp_request_size=hp_request_size+target_size;nb_copy(hp_request+hp_request_size," HTTP/1.1\r\n",11);hp_request_size=hp_request_size+11;return 0;
}
fn hp_append_header(name,ns,value,vs) {if hp_request_size+ns+vs+4>2048 {return -90;}let p=hp_request+hp_request_size;nb_copy(p,name,ns);nb_copy(p+ns,": ",2);nb_copy(p+ns+2,value,vs);nb_copy(p+ns+2+vs,"\r\n",2);hp_request_size=hp_request_size+ns+vs+4;return 0;}
fn hp_host(host,size,port) {
    if hp_request_ready || hp_state!=1 || hp_request_host {return -16;}if !host || size<1 || size>253 || port<1 || port>65535 {return -22;}
    let i=0;while i<size {let c=load8(host+i);if !((c>=65 && c<=90) || (c>=97 && c<=122) || (c>=48 && c<=57) || c==45 || c==46) {return -22;}i=i+1;}
    nb_copy(hp_line,host,size);store8(hp_line+size,58);let n=nb_number(hp_line+size+1,port,10);let r=hp_append_header("Host",4,hp_line,size+1+n);if !r {hp_request_host=1;}return r;
}
fn hp_add_header(name,ns,value,vs) {
    if hp_request_ready || hp_state!=1 {return -16;}if vs>2048 {return -90;}if !hp_name_valid(name,ns) || !hp_value_valid(value,vs) {return -22;}
    if nb_ci(name,ns,"host",4) || nb_ci(name,ns,"content-length",14) || nb_ci(name,ns,"transfer-encoding",17) || nb_ci(name,ns,"connection",10) || nb_ci(name,ns,"upgrade",7) || nb_ci(name,ns,"expect",6) {return -95;}return hp_append_header(name,ns,value,vs);
}
fn hp_finish_request() {
    if hp_request_ready || hp_state!=1 {return -16;}if !hp_request_host {return -22;}let framing=28;if hp_request_length>=0 {framing=18+nb_digits(hp_request_length,10);}let connection=19;if hp_request_keep {connection=24;}let needed=framing+connection+2;if hp_request_size+needed>2048 {return -90;}
    if hp_request_length<0 {hp_append_header("Transfer-Encoding",17,"chunked",7);}else {let n=nb_number(hp_line,hp_request_length,10);hp_append_header("Content-Length",14,hp_line,n);}
    if hp_request_keep {hp_append_header("Connection",10,"keep-alive",10);}else {hp_append_header("Connection",10,"close",5);}nb_copy(hp_request+hp_request_size,"\r\n",2);hp_request_size=hp_request_size+2;hp_request_ready=1;return 0;
}
fn hp_parse_length(p,n) {
    let i=0;let found=0;let length= -1;
    while i<n {while i<n && (load8(p+i)==32 || load8(p+i)==9) {i=i+1;}let start=i;let value=0;
        while i<n && load8(p+i)>=48 && load8(p+i)<=57 {let digit=load8(p+i)-48;if value>(2147483647-digit)/10 {return -90;}value=value*10+digit;i=i+1;}
        if i==start {return -74;}while i<n && (load8(p+i)==32 || load8(p+i)==9) {i=i+1;}if found && value!=length {return -74;}length=value;found=1;
        if i<n {if load8(p+i)!=44 {return -74;}i=i+1;if i==n {return -74;}}
    }if !found || (hp_length>=0 && hp_length!=length) {return -74;}hp_length=length;return 0;
}
fn hp_connection(p,n) {
    let i=0;while i<n {while i<n && (load8(p+i)==32 || load8(p+i)==9) {i=i+1;}let start=i;while i<n && nb_token(load8(p+i)) {i=i+1;}let size=i-start;if !size {return -74;}
        if nb_ci(p+start,size,"close",5) {hp_close=1;}if nb_ci(p+start,size,"keep-alive",10) {hp_keep=1;}while i<n && (load8(p+i)==32 || load8(p+i)==9) {i=i+1;}if i<n {if load8(p+i)!=44 {return -74;}i=i+1;if i==n {return -74;}}
    }if !n {return -74;}return 0;
}
fn hp_forbidden_trailer(name,n) {return nb_ci(name,n,"content-length",14) || nb_ci(name,n,"transfer-encoding",17) || nb_ci(name,n,"connection",10) || nb_ci(name,n,"host",4) || nb_ci(name,n,"trailer",7) || nb_ci(name,n,"te",2) || nb_ci(name,n,"upgrade",7) || nb_ci(name,n,"authorization",13) || nb_ci(name,n,"proxy-authorization",19) || nb_ci(name,n,"content-encoding",16) || nb_ci(name,n,"content-type",12) || nb_ci(name,n,"content-range",13);}
fn hp_parse_field(p,n,trailer) {
    let colon=0;while colon<n && load8(p+colon)!=58 {if !nb_token(load8(p+colon)) {return -74;}colon=colon+1;}if !colon || colon==n || !hp_value_valid(p+colon+1,n-colon-1) {return -74;}
    hp_fields=hp_fields+1;if hp_fields>64 {return -90;}let start=colon+1;let end=n;while start<end && (load8(p+start)==32 || load8(p+start)==9) {start=start+1;}while end>start && (load8(p+end-1)==32 || load8(p+end-1)==9) {end=end-1;}
    if trailer {if hp_forbidden_trailer(p,colon) {return -74;}return 0;}
    if nb_ci(p,colon,"content-length",14) {return hp_parse_length(p+start,end-start);}
    if nb_ci(p,colon,"transfer-encoding",17) {if hp_transfer {return -74;}if !nb_ci(p+start,end-start,"chunked",7) {return -95;}hp_transfer=1;}
    if nb_ci(p,colon,"connection",10) {return hp_connection(p+start,end-start);}return 0;
}
fn hp_finish_headers() {
    if (hp_transfer && hp_length>=0) || (hp_minor==0 && hp_transfer) {return -74;}if hp_status<200 {if hp_status==101 {return -95;}if hp_transfer || hp_length>=0 {return -74;}hp_interim=hp_interim+1;if hp_interim>8 {return -90;}hp_reset_fields();return 0;}
    hp_header_end=hp_header_used;hp_trailer_start=hp_header_used;hp_final_headers=1;hp_reusable=hp_request_keep && !hp_close && (hp_minor==1 || hp_keep);
    if hp_head || hp_status==204 || hp_status==304 {if hp_status==204 && (hp_transfer || hp_length>=0) {return -74;}hp_remaining=0;hp_state=8;return 0;}
    if hp_transfer {hp_state=4;hp_line_size=0;hp_cr=0;return 0;}
    if hp_length>=0 {if hp_length>hp_limit {return -90;}hp_remaining=hp_length;hp_state=2;if !hp_remaining {hp_state=8;}return 0;}
    hp_state=3;hp_reusable=0;return 0;
}
fn hp_header_line(p,n) {
    if !hp_status {
        if n<13 || !nb_equal(p,"HTTP/1.",7) || (load8(p+7)!=48 && load8(p+7)!=49) || load8(p+8)!=32 || load8(p+12)!=32 {return -74;}
        let status=0;let i=9;while i<12 {let c=load8(p+i);if c<48 || c>57 {return -74;}status=status*10+c-48;i=i+1;}if status<100 || status>599 || !hp_value_valid(p+13,n-13) {return -74;}hp_status=status;hp_minor=load8(p+7)-48;return 0;
    }if !n {return hp_finish_headers();}return hp_parse_field(p,n,0);
}
fn hp_chunk_line(p,n) {
    let i=0;let length=0;while i<n && nb_hex(load8(p+i))>=0 {let digit=nb_hex(load8(p+i));if length>(2147483647-digit)/16 {return -90;}length=length*16+digit;i=i+1;}if !i {return -74;}
    while i<n {while i<n && (load8(p+i)==32 || load8(p+i)==9) {i=i+1;}if i==n || load8(p+i)!=59 {return -74;}i=i+1;while i<n && (load8(p+i)==32 || load8(p+i)==9) {i=i+1;}let start=i;while i<n && nb_token(load8(p+i)) {i=i+1;}if i==start {return -74;}
        while i<n && (load8(p+i)==32 || load8(p+i)==9) {i=i+1;}if i<n && load8(p+i)==61 {i=i+1;while i<n && (load8(p+i)==32 || load8(p+i)==9) {i=i+1;}if i<n && load8(p+i)==34 {i=i+1;let closed=0;while i<n && !closed {let c=load8(p+i);i=i+1;if c==34 {closed=1;}else {if c==92 {if i>=n {return -74;}c=load8(p+i);i=i+1;}if (c<32 && c!=9) || c==127 {return -74;}}}if !closed {return -74;}}
            else {start=i;while i<n && nb_token(load8(p+i)) {i=i+1;}if i==start {return -74;}}
        }
    }
    if length>hp_limit-hp_received {return -90;}hp_remaining=length;if length {hp_state=5;}else {hp_state=7;hp_cr=0;}return 0;
}
fn hp_feed(input,size) {
    if size<0 || (size && !input) {return -22;}if hp_state==9 {return hp_error;}if !hp_state {return -16;}let i=0;
    while i<size {
        if hp_state==8 {return hp_fail(-74);}let c=load8(input+i);
        if hp_state==2 || hp_state==3 || hp_state==5 {
            if hp_body_used==1024 {return i;}if hp_received>=hp_limit {return hp_fail(-90);}let n=size-i;if n>1024-hp_body_used {n=1024-hp_body_used;}if hp_state!=3 && n>hp_remaining {n=hp_remaining;}if n>hp_limit-hp_received {n=hp_limit-hp_received;}
            nb_copy(hp_body+hp_body_used,input+i,n);hp_body_used=hp_body_used+n;hp_received=hp_received+n;i=i+n;if hp_state!=3 {hp_remaining=hp_remaining-n;if !hp_remaining {if hp_state==2 {hp_state=8;}else {hp_state=6;hp_chunk_cr=0;}}}
        }else if hp_state==6 {
            if (!hp_chunk_cr && c!=13) || (hp_chunk_cr && c!=10) {return hp_fail(-74);}i=i+1;hp_chunk_cr=hp_chunk_cr+1;if hp_chunk_cr==2 {hp_state=4;hp_line_size=0;hp_cr=0;}
        }else if hp_state==1 {
            if hp_header_used>=2048 || hp_meta>=16384 {return hp_fail(-90);}if (hp_cr && c!=10) || (!hp_cr && c==10) {return hp_fail(-74);}store8(hp_headers+hp_header_used,c);hp_header_used=hp_header_used+1;hp_meta=hp_meta+1;i=i+1;
            if hp_cr {hp_cr=0;let n=hp_header_used-hp_header_start-2;let r=hp_header_line(hp_headers+hp_header_start,n);if r {return hp_fail(r);}hp_header_start=hp_header_used;}
            else if c==13 {hp_cr=1;}
        }else if hp_state==4 || hp_state==7 {
            if hp_line_size>=1024 {return hp_fail(-90);}if (hp_cr && c!=10) || (!hp_cr && c==10) {return hp_fail(-74);}store8(hp_line+hp_line_size,c);hp_line_size=hp_line_size+1;i=i+1;
            if hp_cr {hp_cr=0;let n=hp_line_size-2;let r=0;if hp_state==4 {r=hp_chunk_line(hp_line,n);}else {if hp_header_used+hp_line_size>2048 || hp_meta+hp_line_size>16384 {return hp_fail(-90);}r=hp_parse_field(hp_line,n,1);if !n {r=0;hp_state=8;}if !r {nb_copy(hp_headers+hp_header_used,hp_line,hp_line_size);hp_header_used=hp_header_used+hp_line_size;hp_meta=hp_meta+hp_line_size;}}hp_line_size=0;if r {return hp_fail(r);}}
            else if c==13 {hp_cr=1;}
        }else {return hp_fail(-74);}
    }return i;
}
fn hp_eof() {if hp_state==9 {return hp_error;}if hp_state==3 {hp_state=8;hp_reusable=0;return 0;}if hp_state==8 {hp_reusable=0;return 0;}return hp_fail(-74);}
fn hp_read(out,capacity) {if capacity<0 || (capacity && !out) {return -22;}if !capacity {return 0;}if hp_body_used {let n=hp_body_used;if n>capacity {n=capacity;}nb_copy(out,hp_body,n);nb_copy(hp_body,hp_body+n,hp_body_used-n);hp_body_used=hp_body_used-n;return n;}if hp_state==9 {return hp_error;}if hp_state==8 {return 0;}return -11;}
fn hp_field(name,size,occurrence,trailer) {
    hp_field_size=0;if !hp_name_valid(name,size) || occurrence<0 || occurrence>63 || trailer<0 || trailer>1 {return -22;}if !hp_final_headers {return -11;}
    let at=0;let end=hp_header_end;if trailer {at=hp_trailer_start;end=hp_header_used;}else {while at+1<end && !(load8(hp_headers+at)==13 && load8(hp_headers+at+1)==10) {at=at+1;}at=at+2;}
    while at+1<end {let start=at;while at+1<end && !(load8(hp_headers+at)==13 && load8(hp_headers+at+1)==10) {at=at+1;}let finish=at;at=at+2;if finish==start {return 0;}let colon=start;while colon<finish && load8(hp_headers+colon)!=58 {colon=colon+1;}
        if nb_ci(hp_headers+start,colon-start,name,size) {if !occurrence {start=colon+1;while start<finish && (load8(hp_headers+start)==32 || load8(hp_headers+start)==9) {start=start+1;}while finish>start && (load8(hp_headers+finish-1)==32 || load8(hp_headers+finish-1)==9) {finish=finish-1;}hp_field_size=finish-start;return hp_headers+start;}occurrence=occurrence-1;}
    }return 0;
}
