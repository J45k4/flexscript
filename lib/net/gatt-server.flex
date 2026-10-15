import "bytes.flex";
// Caller-owned ATT/GATT server, one unenhanced bearer per connection.
// Workspace: scratch512 + attributes*128 + aligned value pool + links*4096.
// Each link: metadata256, response520, notification520, prepare records512,
// prepare bytes1024, copied direct-write event512, staging512 and CCCDs128.
// Prepare queue32 records/1024 bytes; attribute values at most512 bytes.
global ga_work=0;
global ga_attrs=0;
global ga_attr_capacity=0;
global ga_count=0;
global ga_pool=0;
global ga_pool_capacity=0;
global ga_pool_used=0;
global ga_connections=0;
global ga_links=0;
global ga_last_token=0;
global ga_service_handle=0;
global ga_last_value=0;
global ga_sealed=0;
global ga_mtu=23;
global ga_now=0;
global ga_generation=0;
global ga_packet=0;
global ga_packet_size=0;
global ga_packet_kind=0;
global ga_packet_connection=0;
global ga_packet_generation=0;
global ga_value_data=0;
global ga_value_size=0;
global ga_event_kind=0;
global ga_event_handle=0;
global ga_event_offset=0;
global ga_event_data=0;
global ga_event_size=0;
global ga_event_status=0;
global ga_request_handle=0;
global ga_request_security=0;
global ga_cancelled_notifications=0;
global ga_name_handle=0;
global ga_appearance_handle=0;
global ga_service_changed_handle=0;
fn ga_u16(p) {return load8(p)|(load8(p+1)<<8);}
fn ga_put16(p,n) {store8(p,n);store8(p+1,n>>8);return 2;}
fn ga_size(attributes,links,values) {if attributes<1 || attributes>64 || links<1 || links>4 || values<0 || values>65536 {return -22;}return 512+attributes*128+((values+7)&~7)+links*4096;}
fn ga_init(work,capacity,attributes,links,values,mtu) {
    let size=ga_size(attributes,links,values);if size<0 || work<=0 || work&7 || capacity<size || mtu<23 || mtu>517 {return -22;}nb_zero(work,size);ga_work=work;ga_attrs=work+512;ga_attr_capacity=attributes;ga_count=0;ga_pool=ga_attrs+attributes*128;ga_pool_capacity=(values+7)&~7;ga_pool_used=0;ga_connections=ga_pool+ga_pool_capacity;ga_links=links;ga_last_token=0;ga_service_handle=0;ga_last_value=0;ga_sealed=0;ga_mtu=mtu;ga_now=0;ga_generation=0;ga_packet=0;ga_packet_size=0;ga_packet_kind=0;ga_packet_connection=0;ga_packet_generation=0;ga_value_data=0;ga_value_size=0;ga_event_data=0;ga_event_size=0;ga_request_handle=0;ga_request_security=0;ga_cancelled_notifications=0;ga_name_handle=0;ga_appearance_handle=0;ga_service_changed_handle=0;return 0;
}
fn ga_at(handle) {if !ga_work || handle<1 || handle>ga_count {return 0;}return ga_attrs+(handle-1)*128;}
fn ga_slot(index) {return ga_connections+index*4096;}
fn ga_find(token) {let i=0;while i<ga_links {if load64(ga_slot(i))==token && token>0 {return i;}i=i+1;}return -1;}
fn ga_conn(token) {let i=ga_find(token);if i<0 {return 0;}return ga_slot(i);}
fn ga_uuid16(uuid) {if !ga_work || uuid<0 || uuid>65535 {return 0;}ga_put16(ga_work,uuid);return ga_work;}
fn ga_base_uuid(uuid) {let base=ga_work+16;store8(base,0xfb);store8(base+1,0x34);store8(base+2,0x9b);store8(base+3,0x5f);store8(base+4,0x80);store8(base+5,0);store8(base+6,0);store8(base+7,0x80);store8(base+8,0);store8(base+9,0x10);store8(base+10,0);store8(base+11,0);return nb_equal(uuid,base,12) && !load8(uuid+14) && !load8(uuid+15);}
fn ga_uuid_equal(a,an,b,bn) {if an==bn {return nb_equal(a,b,an);}if an==2 && bn==16 {return ga_base_uuid(b) && ga_u16(a)==ga_u16(b+12);}if an==16 && bn==2 {return ga_base_uuid(a) && ga_u16(a+12)==ga_u16(b);}return 0;}
fn ga_uuid_is(uuid,size,value) {if size==2 {return ga_u16(uuid)==value;}return size==16 && ga_base_uuid(uuid) && ga_u16(uuid+12)==value;}
fn ga_room(count,bytes) {return ga_work && !ga_sealed && ga_count+count<=ga_attr_capacity && ga_pool_used+bytes<=ga_pool_capacity;}
fn ga_add(uuid,usize,value,size,capacity,permissions,kind) {
    let p=ga_attrs+ga_count*128;let data=ga_pool+ga_pool_used;ga_count=ga_count+1;store64(p,ga_count);store64(p+8,usize);nb_copy(p+16,uuid,usize);store64(p+32,data);store64(p+40,size);store64(p+48,capacity);store64(p+56,permissions);store64(p+64,kind);if permissions&60 {store64(p+96,7);}nb_copy(data,value,size);ga_pool_used=ga_pool_used+((capacity+7)&~7);return ga_count;
}
fn ga_service(uuid,size,primary) {
    if uuid<=0 || (size!=2 && size!=16) || primary<0 || primary>1 || !ga_room(1,(size+7)&~7) {return -22;}nb_copy(ga_work+64,uuid,size);ga_put16(ga_work+32,0x2801-primary);let previous=ga_service_handle;let handle=ga_add(ga_work+32,2,ga_work+64,size,size,1,1);store64(ga_at(handle)+120,1);if previous {store64(ga_at(previous)+72,handle-1);}ga_service_handle=handle;ga_last_value=0;return handle;
}
fn ga_characteristic(uuid,usize,properties,permissions,value,size,capacity) {
    if uuid<=0 || (usize!=2 && usize!=16) || !ga_service_handle || properties<0 || properties>255 || properties&65 || permissions<0 || permissions>255 || size<0 || capacity<size || capacity>512 || (size && value<=0) || ga_uuid_is(uuid,usize,0x2800) || ga_uuid_is(uuid,usize,0x2801) || ga_uuid_is(uuid,usize,0x2802) || ga_uuid_is(uuid,usize,0x2803) || ((properties&2)!=0)!=((permissions&1)!=0) || ((properties&12)!=0)!=((permissions&2)!=0) {return -22;}
    let cccd=(properties&48)!=0;let extended=(properties&128)!=0;let bytes=((usize+10)&~7)+((capacity+7)&~7)+extended*8;if !ga_room(2+cccd+extended,bytes) {return -12;}
    let decl=ga_work+64;store8(decl,properties);ga_put16(decl+1,ga_count+2);nb_copy(decl+3,uuid,usize);ga_put16(ga_work+32,0x2803);let d=ga_add(ga_work+32,2,decl,usize+3,usize+3,1,2);store64(ga_at(d)+120,1);
    let handle=ga_add(uuid,usize,value,size,capacity,permissions,3);store64(ga_at(handle)+88,properties);ga_last_value=handle;
    if cccd {ga_put16(ga_work+32,0x2902);let h=ga_add(ga_work+32,2,0,0,0,3,4);let p=ga_at(h);store64(p+40,2);store64(p+48,2);store64(p+80,handle);store64(p+120,1);}
    if extended {ga_put16(ga_work+32,0x2900);ga_put16(ga_work+64,1);let h=ga_add(ga_work+32,2,ga_work+64,2,2,1,5);store64(ga_at(h)+120,1);store64(ga_at(h)+80,handle);}return handle;
}
fn ga_descriptor(uuid,usize,permissions,value,size,capacity) {
    if uuid<=0 || (usize!=2 && usize!=16) || !ga_last_value || permissions<0 || permissions>255 || size<0 || capacity<size || capacity>512 || (size && value<=0) || ga_uuid_is(uuid,usize,0x2902) || ga_uuid_is(uuid,usize,0x2900) || ga_uuid_is(uuid,usize,0x2800) || ga_uuid_is(uuid,usize,0x2801) || ga_uuid_is(uuid,usize,0x2802) || ga_uuid_is(uuid,usize,0x2803) {return -22;}
    if ga_uuid_is(uuid,usize,0x2901) && permissions&2 {let i=ga_last_value+1;let found=0;while i<=ga_count {let p=ga_at(i);if ga_uuid_is(p+16,load64(p+8),0x2900) && load64(p+80)==ga_last_value {found=load64(p+32);}i=i+1;}if !found {return -22;}if !ga_room(1,(capacity+7)&~7) {return -12;}ga_put16(found,ga_u16(found)|2);}
    if !ga_room(1,(capacity+7)&~7) {return -12;}let handle=ga_add(uuid,usize,value,size,capacity,permissions,5);store64(ga_at(handle)+80,ga_last_value);return handle;
}
fn ga_permissions(handle,permissions,min_key_size) {let p=ga_at(handle);if !p || ga_sealed || permissions<0 || permissions>255 || min_key_size<0 || min_key_size>16 || (min_key_size && min_key_size<7) || load64(p+64)==1 || load64(p+64)==2 || load64(p+64)==6 || (permissions&2 && ga_uuid_is(p+16,load64(p+8),0x2900)) {return -22;}store64(p+56,permissions);store64(p+96,min_key_size);return 0;}
fn ga_fixed(handle,enabled) {let p=ga_at(handle);if !p || ga_sealed || enabled<0 || enabled>1 || load64(p+64)!=3 && load64(p+64)!=5 {return -22;}if enabled && load64(p+40)!=load64(p+48) {return -22;}store64(p+120,enabled);return 0;}
fn ga_include(service) {let p=ga_at(service);if !p || load64(p+64)!=1 || !load64(p+72) || !ga_service_handle || service==ga_service_handle {return -22;}let n=4;if load64(p+40)==2 {n=6;}if !ga_room(1,8) {return -12;}ga_put16(ga_work+32,0x2802);ga_put16(ga_work+64,service);ga_put16(ga_work+66,load64(p+72));if n==6 {nb_copy(ga_work+68,load64(p+32),2);}let handle=ga_add(ga_work+32,2,ga_work+64,n,n,1,6);store64(ga_at(handle)+120,1);return handle;}
fn ga_utf8(text,size) {
    let i=0;while i<size {let c=load8(text+i);let n=1;if c>=128 {if c>=0xc2 && c<=0xdf {n=2;}else if c>=0xe0 && c<=0xef {n=3;}else if c>=0xf0 && c<=0xf4 {n=4;}else {return 0;}if i+n>size {return 0;}let second=load8(text+i+1);if (c==0xe0 && second<0xa0) || (c==0xed && second>=0xa0) || (c==0xf0 && second<0x90) || (c==0xf4 && second>=0x90) {return 0;}let j=1;while j<n {let b=load8(text+i+j);if b<128 || b>191 {return 0;}j=j+1;}}i=i+n;}return 1;
}
fn ga_standard_services(name,size,appearance) {
    if ga_count || name<=0 || size<1 || size>248 || appearance<0 || appearance>65535 || !ga_room(9,56+((size+7)&~7)) || !ga_utf8(name,size) {return -22;}
    ga_service(ga_uuid16(0x1800),2,1);ga_name_handle=ga_characteristic(ga_uuid16(0x2a00),2,2,1,name,size,size);ga_put16(ga_work+96,appearance);ga_appearance_handle=ga_characteristic(ga_uuid16(0x2a01),2,2,1,ga_work+96,2,2);ga_fixed(ga_appearance_handle,1);
    ga_service(ga_uuid16(0x1801),2,1);ga_put16(ga_work+96,1);ga_put16(ga_work+98,65535);ga_service_changed_handle=ga_characteristic(ga_uuid16(0x2a05),2,32,0,ga_work+96,4,4);ga_fixed(ga_service_changed_handle,1);return 0;
}
fn ga_seal() {if !ga_work || ga_sealed || !ga_service_handle {return -22;}store64(ga_at(ga_service_handle)+72,ga_count);ga_sealed=1;return 0;}
fn ga_open(token) {if !ga_sealed {return -19;}if token<=ga_last_token || token<=0 || ga_find(token)>=0 {return -22;}let i=0;while i<ga_links {let p=ga_slot(i);if !load64(p) {nb_zero(p,4096);store64(p,token);store64(p+8,23);ga_last_token=token;return 0;}i=i+1;}return -105;}
fn ga_close(token) {let p=ga_conn(token);if !p {return -107;}nb_zero(p,4096);if ga_packet_connection==token {ga_packet=0;ga_packet_size=0;ga_packet_kind=0;}return 0;}
fn ga_security_valid(security) {let flags=security&255;let key=(security>>8)&255;return security>=0 && security<=65535 && flags<=7 && key<=16 && (!key || key>=7) && (!(flags&2) || flags&1) && (!key || flags&1);}
fn ga_security(token,security) {let p=ga_conn(token);if !p {return -107;}if !ga_security_valid(security) {return -22;}store64(p+16,security);ga_recheck_notification(p);return 0;}
fn ga_data(p,c) {if load64(p+64)==4 {return c+3920+(load64(p)-1)*2;}return load64(p+32);}
fn ga_check_permission(p,security,write) {
    let bits=load64(p+56);let allowed=1;let enc=4;let auth=16;let authorized=64;if write {allowed=2;enc=8;auth=32;authorized=128;}if !(bits&allowed) {return 2+write;}if bits&auth && !(security&2) {return 5;}if bits&authorized && !(security&4) {return 8;}if bits&enc && !(security&1) {return 15;}if bits&(enc|auth) && (security>>8)<load64(p+96) {return 12;}return 0;
}
fn ga_value(handle) {let p=ga_at(handle);if !p || load64(p+64)==4 {return -22;}ga_value_data=load64(p+32);ga_value_size=load64(p+40);return 1;}
fn ga_set(handle,value,size) {let p=ga_at(handle);if !p || (load64(p+64)!=3 && load64(p+64)!=5) || size<0 || size>load64(p+48) || (size && value<=0) {return -22;}nb_copy(load64(p+32),value,size);if !load64(p+120) {store64(p+40,size);}return 0;}
fn ga_response(c,size) {ga_generation=ga_generation+1;store64(c+24,size);store64(c+168,ga_generation);store64(c+192,ga_now+30000);store64(c+200,ga_request_handle);return 1;}
fn ga_error_response(c,op,handle,error) {let out=c+256;store8(out,1);store8(out+1,op);ga_put16(out+2,handle);store8(out+4,error);ga_request_handle=handle;return ga_response(c,5);}
fn ga_direct_event(c,handle,offset,data,size,kind) {nb_copy(c+2832,data,size);store64(c+80,kind);store64(c+88,handle);store64(c+96,size);store64(c+104,offset);return 0;}
fn ga_cccd_valid(p,value) {let v=ga_at(load64(p+80));let properties=load64(v+88);let allowed=0;if properties&16 {allowed=allowed|1;}if properties&32 {allowed=allowed|2;}return !(value&~allowed);}
fn ga_write(c,p,offset,data,size) {nb_copy(ga_data(p,c)+offset,data,size);if !load64(p+120) {let length=offset+size;if offset && length<load64(p+40) {length=load64(p+40);}store64(p+40,length);}return 0;}
fn ga_range(start,end) {return start>=1 && start<=end && end<=65535;}
fn ga_discover(c,in,size,op) {
    if size<5 {return ga_error_response(c,op,0,4);}let start=ga_u16(in+1);let end=ga_u16(in+3);if !ga_range(start,end) {return ga_error_response(c,op,start,1);}let out=c+256;let mtu=load64(c+8);let at=2;let entry=0;let original= -1;let uuid=in+5;let usize=size-5;let i=start;
    if op==4 {if size!=5 {return ga_error_response(c,op,0,4);}store8(out,5);}
    else if op==6 {if size<7 {return ga_error_response(c,op,0,4);}store8(out,7);at=1;}
    else {if usize!=2 && usize!=16 {return ga_error_response(c,op,0,4);}if op==16 && !ga_uuid_is(uuid,usize,0x2800) && !ga_uuid_is(uuid,usize,0x2801) {return ga_error_response(c,op,start,16);}store8(out,op+1);}
    let stop=0;while i<=end && i<=ga_count && !stop {let p=ga_at(i);let match=1;if op==6 {match=ga_uuid_equal(p+16,load64(p+8),in+5,2);if match {let n=load64(p+40);if load64(p+64)==1 {match=ga_uuid_equal(ga_data(p,c),n,in+7,size-7);}else {match=n==size-7 && nb_equal(ga_data(p,c),in+7,n);}}}
        else if op!=4 {match=ga_uuid_equal(p+16,load64(p+8),uuid,usize);}if match {
            if op==4 {let n=load64(p+8);let length=n+2;if entry && entry!=length {stop=1;}else if at+length>mtu {stop=1;}else {if !entry {entry=length;store8(out+1,1+(n==16));}ga_put16(out+at,i);nb_copy(out+at+2,p+16,n);at=at+length;}}
            else if op==6 {if at+4>mtu {stop=1;}else {ga_put16(out+at,i);let last=i;if load64(p+64)==1 {last=load64(p+72);}ga_put16(out+at+2,last);at=at+4;}}
            else {let error=ga_check_permission(p,ga_request_security,0);if error {if at==2 {return ga_error_response(c,op,i,error);}stop=1;}else {let n=load64(p+40);let whole=n;let header=2;if op==16 {header=4;}let cap=mtu-2-header;if cap>255-header {cap=255-header;}if n>cap {n=cap;}let length=n+header;if entry && (entry!=length || original!=whole) {stop=1;}else if at+length>mtu {stop=1;}else {if !entry {entry=length;original=whole;store8(out+1,length);}ga_put16(out+at,i);if op==16 {ga_put16(out+at+2,load64(p+72));}nb_copy(out+at+header,ga_data(p,c),n);at=at+length;}}}
        }i=i+1;
    }let empty=2;if op==6 {empty=1;}if at==empty {return ga_error_response(c,op,start,10);}return ga_response(c,at);
}
fn ga_read(c,in,size,op) {
    let expected=3;if op==12 {expected=5;}if size!=expected {return ga_error_response(c,op,0,4);}let handle=ga_u16(in+1);let p=ga_at(handle);if !p {return ga_error_response(c,op,handle,1);}let error=ga_check_permission(p,ga_request_security,0);if error {return ga_error_response(c,op,handle,error);}let offset=0;if op==12 {offset=ga_u16(in+3);}let length=load64(p+40);if offset>length {return ga_error_response(c,op,handle,7);}let n=length-offset;if n>load64(c+8)-1 {n=load64(c+8)-1;}store8(c+256,op+1);nb_copy(c+257,ga_data(p,c)+offset,n);return ga_response(c,n+1);
}
fn ga_read_multiple(c,in,size,op) {
    if size<5 || !(size&1) {return ga_error_response(c,op,0,4);}let at=1;while at<size {let handle=ga_u16(in+at);let p=ga_at(handle);if !p {return ga_error_response(c,op,handle,1);}let error=ga_check_permission(p,ga_request_security,0);if error {return ga_error_response(c,op,handle,error);}at=at+2;}
    let out=c+256;store8(out,op+1);let n=1;at=1;let mtu=load64(c+8);while at<size && n<mtu {let p=ga_at(ga_u16(in+at));let length=load64(p+40);if op==32 {if n+2>mtu {return ga_response(c,n);}let room=mtu-n-2;ga_put16(out+n,length);if length>room {length=room;}n=n+2;}else if length>mtu-n {length=mtu-n;}nb_copy(out+n,ga_data(p,c),length);n=n+length;at=at+2;}return ga_response(c,n);
}
fn ga_write_request(c,in,size,op) {
    if size<3 {if op==0x52 {return 1;}return ga_error_response(c,op,0,4);}let handle=ga_u16(in+1);let p=ga_at(handle);let error=1;if p {error=ga_check_permission(p,ga_request_security,1);if !error && load64(p+64)==3 {let required=8;if op==0x52 {required=4;}if !(load64(p+88)&required) {error=3;}}if !error && size-3>load64(p+48) {error=13;}if !error && load64(p+64)==4 {if size!=5 {error=13;}else if !ga_cccd_valid(p,ga_u16(in+3)) {error=19;}}}
    if error {if op==0x52 {return 1;}return ga_error_response(c,op,handle,error);}if load64(c+80) || load64(c+128) {return -11;}ga_write(c,p,0,in+3,size-3);ga_recheck_notification(c);let kind=1;if load64(p+64)==4 {kind=2;}ga_direct_event(c,handle,0,in+3,size-3,kind);if op==0x52 {return 1;}store8(c+256,0x13);return ga_response(c,1);
}
fn ga_prepare(c,in,size) {
    if size<5 {return ga_error_response(c,22,0,4);}let handle=ga_u16(in+1);let p=ga_at(handle);if !p {return ga_error_response(c,22,handle,1);}let error=ga_check_permission(p,ga_request_security,1);if !error && load64(p+64)==3 && !(load64(p+88)&8) {error=3;}if error {return ga_error_response(c,22,handle,error);}if load64(c+80) || load64(c+128) {return -11;}let count=load64(c+112);let used=load64(c+120);let n=size-5;if count>=32 || used+n>1024 {return ga_error_response(c,22,handle,9);}let record=c+1296+count*16;ga_put16(record,handle);ga_put16(record+2,ga_u16(in+3));ga_put16(record+4,n);ga_put16(record+6,used);store64(record+8,ga_request_security);nb_copy(c+1808+used,in+5,n);store64(c+112,count+1);store64(c+120,used+n);nb_copy(c+256,in,size);store8(c+256,23);return ga_response(c,size);
}
fn ga_clear_prepare(c) {store64(c+112,0);store64(c+120,0);store64(c+128,0);store64(c+136,0);return 0;}
fn ga_execute(c,in,size) {
    if size!=2 || load8(in+1)>1 {return ga_error_response(c,24,0,4);}if load64(c+80) || load64(c+128) {return -11;}let count=load64(c+112);if !load8(in+1) || !count {ga_clear_prepare(c);store8(c+256,25);return ga_response(c,1);}
    let i=1;while i<=ga_count {let p=ga_at(i);ga_put16(ga_work+128+(i-1)*2,load64(p+40));if load64(p+64)==4 {ga_put16(ga_work+256+(i-1)*2,ga_u16(ga_data(p,c)));}i=i+1;}
    i=0;while i<count {let rec=c+1296+i*16;let handle=ga_u16(rec);let p=ga_at(handle);let offset=ga_u16(rec+2);let n=ga_u16(rec+4);let current=ga_u16(ga_work+128+(handle-1)*2);let error=ga_check_permission(p,ga_request_security,1);if !error {error=ga_check_permission(p,load64(rec+8),1);}if !error && offset>current {error=7;}if !error && offset+n>load64(p+48) {error=13;}if error {ga_clear_prepare(c);return ga_error_response(c,24,handle,error);}if load64(p+64)==4 {nb_copy(ga_work+256+(handle-1)*2+offset,c+1808+ga_u16(rec+6),n);}else if !load64(p+120) {let next=offset+n;if offset && next<current {next=current;}ga_put16(ga_work+128+(handle-1)*2,next);}i=i+1;}
    i=0;while i<count {let rec=c+1296+i*16;let handle=ga_u16(rec);let p=ga_at(handle);if load64(p+64)==4 && !ga_cccd_valid(p,ga_u16(ga_work+256+(handle-1)*2)) {ga_clear_prepare(c);return ga_error_response(c,24,handle,19);}i=i+1;}
    i=0;while i<count {let rec=c+1296+i*16;let p=ga_at(ga_u16(rec));ga_write(c,p,ga_u16(rec+2),c+1808+ga_u16(rec+6),ga_u16(rec+4));i=i+1;}ga_recheck_notification(c);store64(c+128,1);store64(c+136,0);store8(c+256,25);return ga_response(c,1);
}
fn ga_input(token,in,size,security,now) {
    let c=ga_conn(token);if !c {return -107;}if in<=0 || size<1 || size>517 || now<ga_now || !ga_security_valid(security) {return -22;}if load64(c+72) {return load64(c+72);}ga_now=now;ga_request_security=security;let op=load8(in);
    if op==30 {if size!=1 {return ga_fail(c,-74,0);}if load64(c+56) {store64(c+144,load64(c+56));store64(c+56,0);store64(c+64,0);}return 1;}
    if op==0xd2 || op&0x40 && op!=0x52 || op&1 {return 1;}if load64(c+24) {return -11;}ga_request_handle=0;if size>=3 && op!=2 {ga_request_handle=ga_u16(in+1);}if size>load64(c+8) {if op==0x52 {return 1;}return ga_error_response(c,op,0,4);}
    if op==2 {if size!=3 || ga_u16(in+1)<23 {return ga_error_response(c,op,0,4);}let mtu=ga_u16(in+1);if mtu>ga_mtu {mtu=ga_mtu;}store64(c+8,mtu);ga_recheck_notification(c);store8(c+256,3);ga_put16(c+257,ga_mtu);return ga_response(c,3);}
    if op==4 || op==6 || op==8 || op==16 {return ga_discover(c,in,size,op);}if op==10 || op==12 {return ga_read(c,in,size,op);}if op==14 || op==32 {return ga_read_multiple(c,in,size,op);}if op==18 || op==0x52 {return ga_write_request(c,in,size,op);}if op==22 {return ga_prepare(c,in,size);}if op==24 {return ga_execute(c,in,size);}return ga_error_response(c,op,0,6);
}
fn ga_service_changed(token,start,end,now) {if !ga_service_changed_handle || !ga_range(start,end) {return -22;}ga_put16(ga_work+96,start);ga_put16(ga_work+98,end);return ga_notify(token,ga_service_changed_handle,ga_work+96,4,1,now);}
fn ga_subscription(c,handle) {let i=handle+1;while i<=ga_count {let p=ga_at(i);if load64(p+64)==4 && load64(p+80)==handle {return ga_u16(ga_data(p,c));}i=i+1;}return 0;}
fn ga_subscriptions(token,handle) {let c=ga_conn(token);let p=ga_at(handle);if !c {return -107;}if !p || load64(p+64)!=3 {return -22;}return ga_subscription(c,handle);}
fn ga_notification_authorized(c,p) {let bits=load64(p+56);let security=load64(c+16);return !(bits&16 && !(security&2) || bits&64 && !(security&4) || bits&4 && !(security&1) || bits&20 && (security>>8)<load64(p+96));}
fn ga_recheck_notification(c) {if load64(c+32) {let handle=load64(c+48);let p=ga_at(handle);let enabled=1;if load64(c+40)==2 {enabled=2;}if load64(c+32)>load64(c+8) || !(ga_subscription(c,handle)&enabled) || !ga_notification_authorized(c,p) {store64(c+32,0);ga_cancelled_notifications=ga_cancelled_notifications+1;}}return 0;}
fn ga_next_packet(token) {
    let c=ga_conn(token);if !c {return -107;}if load64(c+72) {return load64(c+72);}ga_recheck_notification(c);ga_packet=0;ga_packet_size=0;ga_packet_kind=0;ga_packet_connection=token;ga_packet_generation=0;
    if load64(c+24) {ga_packet=c+256;ga_packet_size=load64(c+24);ga_packet_kind=1;ga_packet_generation=load64(c+168);}else if load64(c+32) {ga_packet=c+776;ga_packet_size=load64(c+32);ga_packet_kind=2;ga_packet_generation=load64(c+176);}return ga_packet_size;
}
fn ga_packet_sent(token,now) {
    let c=ga_conn(token);if !c {return -107;}if now<ga_now {return -22;}if ga_packet_connection!=token || !ga_packet_size {return -16;}if ga_packet_kind==1 {if ga_packet!=c+256 || ga_packet_generation!=load64(c+168) || ga_packet_size!=load64(c+24) {return -16;}store64(c+24,0);store64(c+192,0);}
    else if ga_packet_kind==2 {if ga_packet!=c+776 || ga_packet_generation!=load64(c+176) || ga_packet_size!=load64(c+32) {return -16;}if load64(c+40)==2 {store64(c+56,load64(c+48));store64(c+64,now+30000);}store64(c+32,0);}else {return -16;}ga_now=now;ga_packet=0;ga_packet_size=0;ga_packet_kind=0;return 0;
}
fn ga_notify(token,handle,value,size,indicate,now) {
    let c=ga_conn(token);let p=ga_at(handle);if !c {return -107;}if !p || load64(p+64)!=3 || size<0 || size>512 || size>load64(p+48) || size>load64(c+8)-3 || (size && value<=0) || indicate<0 || indicate>1 || now<ga_now {return -22;}if load64(c+72) {return load64(c+72);}if load64(c+32) || indicate && (load64(c+56) || load64(c+144)) {return -11;}let property=16;let enabled=1;if indicate {property=32;enabled=2;}if !(load64(p+88)&property) {return -22;}if !(ga_subscription(c,handle)&enabled) {return -13;}
    if !ga_notification_authorized(c,p) {return -13;}let out=c+776;store8(out,0x1b+indicate*2);ga_put16(out+1,handle);nb_copy(out+3,value,size);store64(c+32,size+3);store64(c+40,1+indicate);store64(c+48,handle);ga_generation=ga_generation+1;store64(c+176,ga_generation);ga_now=now;return 0;
}
fn ga_fail(c,error,handle) {store64(c+152,handle);store64(c+208,1);store64(c+56,0);store64(c+64,0);store64(c+72,error);return error;}
fn ga_timeout(c,handle) {return ga_fail(c,-110,handle);}
fn ga_tick(now) {
    if !ga_work {return -19;}if now<ga_now {return -22;}ga_now=now;let i=0;let failed=0;
    while i<ga_links {let c=ga_slot(i);if load64(c) && !load64(c+72) {if load64(c+56) && now>=load64(c+64) {ga_timeout(c,load64(c+56));failed=1;}else if load64(c+24) && load64(c+192) && now>=load64(c+192) {ga_timeout(c,load64(c+200));failed=1;}else if load64(c+216) && now>=load64(c+216) {ga_timeout(c,0);failed=1;}}i=i+1;}if failed {return -110;}return 0;
}
fn ga_next_event(token) {
    let c=ga_conn(token);if !c {return -107;}ga_event_kind=0;ga_event_data=0;ga_event_size=0;ga_event_offset=0;ga_event_status=0;
    if load64(c+80) {ga_event_kind=load64(c+80);ga_event_handle=load64(c+88);ga_event_offset=load64(c+104);ga_event_size=load64(c+96);ga_event_data=c+2832;return 1;}
    if load64(c+128) {let rec=c+1296+load64(c+136)*16;ga_event_handle=ga_u16(rec);ga_event_kind=1;if load64(ga_at(ga_event_handle)+64)==4 {ga_event_kind=2;}ga_event_offset=ga_u16(rec+2);ga_event_size=ga_u16(rec+4);ga_event_data=c+1808+ga_u16(rec+6);return 1;}
    if load64(c+144) {ga_event_kind=3;ga_event_handle=load64(c+144);return 1;}if load64(c+208) {ga_event_kind=4;ga_event_handle=load64(c+152);ga_event_status=load64(c+72);return 1;}return 0;
}
fn ga_consume_event(token) {let c=ga_conn(token);if !c {return -107;}if load64(c+80) {store64(c+80,0);}else if load64(c+128) {let cursor=load64(c+136)+1;if cursor==load64(c+112) {ga_clear_prepare(c);}else {store64(c+136,cursor);}}else if load64(c+144) {store64(c+144,0);}else if load64(c+208) {store64(c+152,0);store64(c+208,0);}else {return -11;}ga_event_data=0;ga_event_size=0;return 0;}

// Drop caller-owned storage and all exported views before the caller frees it.
fn ga_deinit() {ga_work=0;ga_attrs=0;ga_attr_capacity=0;ga_count=0;ga_pool=0;ga_pool_capacity=0;ga_pool_used=0;ga_connections=0;ga_links=0;ga_last_token=0;ga_service_handle=0;ga_last_value=0;ga_sealed=0;ga_mtu=23;ga_now=0;ga_generation=0;ga_packet=0;ga_packet_size=0;ga_packet_kind=0;ga_packet_connection=0;ga_packet_generation=0;ga_value_data=0;ga_value_size=0;ga_event_kind=0;ga_event_handle=0;ga_event_offset=0;ga_event_data=0;ga_event_size=0;ga_event_status=0;ga_request_handle=0;ga_request_security=0;ga_cancelled_notifications=0;ga_name_handle=0;ga_appearance_handle=0;ga_service_changed_handle=0;return 0;}
