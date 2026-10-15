import "bytes.flex";
// BLE HCI/ACL host core. Caller storage=4096+2320*links, links1..4.
// Root: HCI output1536 + eight320-byte copied control events.
// Link: metadata256, L2CAP RX1032 and TX1032 (payload limit1024).
// No allocation, clocks, transport calls, GATT policy or key ownership.
global bh_work=0;
global bh_links=0;
global bh_active=0;
global bh_generation=0;
global bh_now=0;
global bh_error=0;
global bh_last_error=0;
global bh_fault_connection=0;
global bh_acl_mtu=27;
global bh_buffers=1;
global bh_free=1;
global bh_host_flow=0;
global bh_bad_packets=0;
global bh_rx_packets=0;
global bh_tx_packets=0;
global bh_unknown_acl=0;
global bh_unknown_completed=0;
global bh_unknown_cid=0;
global bh_event_head=0;
global bh_event_count=0;
global bh_event_dropped=0;
global bh_event_kind=0;
global bh_event_connection=0;
global bh_event_status=0;
global bh_event_detail=0;
global bh_event_data=0;
global bh_event_size=0;
global bh_packet=0;
global bh_packet_size=0;
global bh_packet_index= -1;
global bh_packet_connection=0;
global bh_packet_fragment=0;
global bh_tx_cursor=0;
global bh_last_packet_kind=0;
global bh_message_cid=0;
global bh_message_data=0;
global bh_message_size=0;
// Controller encryption at the first fragment, not pairing/MITM authentication.
global bh_message_encrypted=0;
fn bh_u16(p) {return load8(p)|(load8(p+1)<<8);}
fn bh_put16(p,n) {store8(p,n);store8(p+1,n>>8);return 2;}
fn bh_size(links) {if links<1 || links>4 {return -22;}return 4096+links*2320;}
fn bh_slot(index) {return bh_work+4096+index*2320;}
fn bh_rx(index) {return bh_slot(index)+256;}
fn bh_tx(index) {return bh_slot(index)+1288;}
fn bh_find(handle) {let i=0;while i<bh_links {if load64(bh_slot(i))==handle+1 {return i;}i=i+1;}return -1;}
fn bh_resolve(connection) {let i=0;while i<bh_links {let p=bh_slot(i);if load64(p) && load64(p+216)==connection {return i;}i=i+1;}return -1;}
fn bh_handle(connection) {let i=bh_resolve(connection);if i<0 {return -107;}return load64(bh_slot(i))-1;}
fn bh_params(interval,latency,timeout) {return interval>=6 && interval<=3200 && latency>=0 && latency<=499 && timeout>=10 && timeout<=3200 && timeout*8>(latency+1)*interval*2;}
fn bh_cid(cid) {return cid==4 || cid==5 || cid==6 || (cid>=64 && cid<=127);}
fn bh_init(work,capacity,links) {
    let size=bh_size(links);if size<0 || work<=0 || capacity<size {return -22;}nb_zero(work,size);bh_work=work;bh_links=links;bh_active=0;bh_generation=0;bh_now=0;bh_error=0;bh_last_error=0;bh_fault_connection=0;bh_acl_mtu=27;bh_buffers=1;bh_free=1;bh_host_flow=0;bh_bad_packets=0;bh_rx_packets=0;bh_tx_packets=0;bh_unknown_acl=0;bh_unknown_completed=0;bh_unknown_cid=0;bh_event_head=0;bh_event_count=0;bh_event_dropped=0;bh_event_data=0;bh_event_size=0;bh_packet=work;bh_packet_size=0;bh_packet_index= -1;bh_packet_connection=0;bh_packet_fragment=0;bh_tx_cursor=0;bh_last_packet_kind=0;bh_message_data=0;bh_message_size=0;bh_message_encrypted=0;return 0;
}
fn bh_set_buffers(mtu,count) {if !bh_work {return -19;}if bh_active || bh_packet_size {return -16;}if mtu<27 || mtu>65535 || count<1 || count>65535 {return -22;}bh_acl_mtu=mtu;if bh_acl_mtu>1024 {bh_acl_mtu=1024;}bh_buffers=count;bh_free=count;return 0;}
fn bh_set_host_flow(enabled) {if !bh_work {return -19;}if bh_active || bh_packet_size {return -16;}if enabled<0 || enabled>1 {return -22;}bh_host_flow=enabled;return 0;}
fn bh_emit(kind,connection,status,detail,packet,size) {
    if bh_event_count==8 {bh_event_dropped=bh_event_dropped+1;bh_error= -105;return -105;}let index=(bh_event_head+bh_event_count)%8;let p=bh_work+1536+index*320;store64(p,kind);store64(p+8,connection);store64(p+16,status);store64(p+24,detail);store64(p+32,size);store64(p+40,bh_now);if size {nb_copy(p+56,packet,size);}bh_event_count=bh_event_count+1;return 0;
}
fn bh_next_event() {if !bh_event_count {return 0;}let p=bh_work+1536+bh_event_head*320;bh_event_kind=load64(p);bh_event_connection=load64(p+8);bh_event_status=load64(p+16);bh_event_detail=load64(p+24);bh_event_size=load64(p+32);bh_event_data=p+56;return 1;}
fn bh_consume_event() {if !bh_event_count {return -11;}bh_event_head=(bh_event_head+1)%8;bh_event_count=bh_event_count-1;bh_event_data=0;bh_event_size=0;return 0;}
fn bh_bad(error,index) {bh_last_error=error;bh_bad_packets=bh_bad_packets+1;bh_fault_connection=0;if index<0 {bh_error=error;}else {let p=bh_slot(index);bh_fault_connection=load64(p+216);store64(p+136,1);if bh_packet_size && bh_packet_index==index {bh_packet_size=0;bh_packet_index= -1;}store64(p+200,error);if !load64(p+96) {store64(p+72,0);store64(p+80,0);store64(p+240,0);}let r=bh_emit(9,bh_fault_connection,error,0,0,0);if r {return r;}}return error;}
fn bh_message(connection) {let i=bh_resolve(connection);if i<0 {return -107;}let p=bh_slot(i);if !load64(p+96) {return 0;}bh_message_cid=load64(p+104);bh_message_data=bh_rx(i)+4;bh_message_size=load64(p+80)-4;bh_message_encrypted=load64(p+248);return 1;}
fn bh_consume(connection) {let i=bh_resolve(connection);if i<0 {return -107;}let p=bh_slot(i);if !load64(p+96) {return -11;}store64(p+72,0);store64(p+80,0);store64(p+88,0);store64(p+96,0);store64(p+104,0);store64(p+232,0);store64(p+240,0);store64(p+248,0);bh_message_data=0;bh_message_size=0;bh_message_encrypted=0;return 0;}
fn bh_send(connection,cid,payload,size) {if !bh_work {return -19;}if bh_error {return bh_error;}let i=bh_resolve(connection);if i<0 {return -107;}let p=bh_slot(i);if load64(p+136) {return -107;}if !bh_cid(cid) || size<0 || size>1024 || (size && payload<=0) {return -22;}if load64(p+112) {return -11;}let out=bh_tx(i);bh_put16(out,size);bh_put16(out+2,cid);nb_copy(out+4,payload,size);store64(p+112,size+4);store64(p+120,0);store64(p+128,cid);return 0;}
fn bh_outstanding(connection) {let i=bh_resolve(connection);if i<0 {return -107;}return load64(bh_slot(i)+64);}
fn bh_mark_closing(connection) {let i=bh_resolve(connection);if i<0 {return -107;}store64(bh_slot(i)+136,1);if bh_packet_size && bh_packet_index==i {bh_packet_size=0;bh_packet_index= -1;}return 0;}
fn bh_next_packet() {
    if bh_error {return bh_error;}if bh_packet_size {return bh_packet_size;}let data=0;if bh_free {let j=0;while j<bh_links {let p=bh_slot(j);if load64(p) && load64(p+112) && !load64(p+136) {data=1;}j=j+1;}}if bh_host_flow && (bh_last_packet_kind!=1 || !data) {let count=0;let i=0;while i<bh_links {let p=bh_slot(i);let n=load64(p+224);if load64(p) && n {if n>65535 {n=65535;}let at=5+count*4;bh_put16(bh_packet+at,load64(p)-1);bh_put16(bh_packet+at+2,n);count=count+1;}i=i+1;}
        if count {store8(bh_packet,1);bh_put16(bh_packet+1,0x0c35);store8(bh_packet+3,1+count*4);store8(bh_packet+4,count);bh_packet_size=5+count*4;bh_packet_index= -1;return bh_packet_size;}}
    if !bh_free {return 0;}let turns=0;while turns<bh_links {let i=(bh_tx_cursor+turns)%bh_links;let p=bh_slot(i);let total=load64(p+112);if load64(p) && total && !load64(p+136) {let at=load64(p+120);let n=total-at;if n>bh_acl_mtu {n=bh_acl_mtu;}let flags=load64(p)-1;if at {flags=flags|0x1000;}store8(bh_packet,2);bh_put16(bh_packet+1,flags);bh_put16(bh_packet+3,n);nb_copy(bh_packet+5,bh_tx(i)+at,n);bh_packet_size=n+5;bh_packet_index=i;bh_packet_connection=load64(p+216);bh_packet_fragment=n;return bh_packet_size;}turns=turns+1;}return 0;
}
fn bh_packet_sent() {
    if !bh_packet_size {return -16;}if load8(bh_packet)==1 {let i=0;while i<load8(bh_packet+4) {let at=5+i*4;let index=bh_find(bh_u16(bh_packet+at));let n=bh_u16(bh_packet+at+2);if index<0 || n>load64(bh_slot(index)+224) {return bh_bad(-71,-1);}i=i+1;}i=0;while i<load8(bh_packet+4) {let at=5+i*4;let p=bh_slot(bh_find(bh_u16(bh_packet+at)));store64(p+224,load64(p+224)-bh_u16(bh_packet+at+2));i=i+1;}}
    else {let i=bh_packet_index;if !bh_free || i<0 || i>=bh_links {return bh_bad(-71,-1);}let p=bh_slot(i);if !load64(p) || load64(p+216)!=bh_packet_connection {return bh_bad(-71,-1);}store64(p+64,load64(p+64)+1);bh_free=bh_free-1;let at=load64(p+120)+bh_packet_fragment;store64(p+120,at);if at==load64(p+112) {store64(p+112,0);store64(p+120,0);}bh_tx_packets=bh_tx_packets+1;bh_tx_cursor=(i+1)%bh_links;}
    bh_last_packet_kind=load8(bh_packet);bh_packet_size=0;bh_packet_index= -1;bh_packet_fragment=0;return 0;
}
fn bh_completed(packet,size) {
    let count=load8(packet+3);if size!=4+count*4 {return bh_bad(-74,-1);}let freed=0;let orphan=0;let i=0;
    while i<count {let at=4+i*4;let handle=bh_u16(packet+at);if handle>0x0eff {return bh_bad(-74,-1);}let j=0;while j<i {if bh_u16(packet+4+j*4)==handle {return bh_bad(-74,-1);}j=j+1;}let n=bh_u16(packet+at+2);let index=bh_find(handle);if index>=0 {if n>load64(bh_slot(index)+64) {return bh_bad(-71,-1);}freed=freed+n;}else {orphan=orphan+n;}i=i+1;}
    if freed+bh_free>bh_buffers {return bh_bad(-71,-1);}i=0;while i<count {let at=4+i*4;let index=bh_find(bh_u16(packet+at));if index>=0 {let p=bh_slot(index);store64(p+64,load64(p+64)-bh_u16(packet+at+2));}i=i+1;}bh_free=bh_free+freed;bh_unknown_completed=bh_unknown_completed+orphan;return 1;
}
fn bh_connected(packet,size,enhanced) {
    let expected=22;let interval_at=15;if enhanced {expected=34;interval_at=27;}if size!=expected {return bh_bad(-74,-1);}let status=load8(packet+4);if status {let r=bh_emit(1,0,status,0,packet,size);if r {return r;}return 1;}
    let handle=bh_u16(packet+5);let role=load8(packet+7);let atype=load8(packet+8);let limit=1;if enhanced {limit=3;}let interval=bh_u16(packet+interval_at);let latency=bh_u16(packet+interval_at+2);let timeout=bh_u16(packet+interval_at+4);
    if handle>0x0eff || role>1 || atype>limit || !bh_params(interval,latency,timeout) || (role && load8(packet+interval_at+6)>7) || bh_find(handle)>=0 {return bh_bad(-74,-1);}if bh_event_count==8 {bh_event_dropped=bh_event_dropped+1;return bh_bad(-105,-1);}let index=bh_find(-1);if index<0 {return bh_bad(-105,-1);}let p=bh_slot(index);nb_zero(p,2320);bh_generation=bh_generation+1;store64(p,handle+1);store64(p+8,role);store64(p+16,atype);nb_copy(p+24,packet+9,6);store64(p+32,interval);store64(p+40,latency);store64(p+48,timeout);store64(p+168,27);store64(p+184,27);store64(p+216,bh_generation);bh_active=bh_active+1;let r=bh_emit(1,bh_generation,0,handle,packet,size);if r {return r;}return 1;
}
fn bh_disconnected(packet,size) {
    if size!=7 {return bh_bad(-74,-1);}let status=load8(packet+3);let handle=bh_u16(packet+4);let index=bh_find(handle);let connection=0;if index>=0 {connection=load64(bh_slot(index)+216);}if !status && handle>0x0eff {return bh_bad(-74,-1);}if bh_event_count==8 {bh_event_dropped=bh_event_dropped+1;return bh_bad(-105,-1);}let r=bh_emit(2,connection,status,(handle<<8)|load8(packet+6),packet,size);if r {return r;}
    if index>=0 {let p=bh_slot(index);if status {store64(p+136,0);}else {let freed=load64(p+64);if bh_free+freed>bh_buffers {return bh_bad(-71,-1);}bh_free=bh_free+freed;if bh_packet_size && (bh_packet_index==index || load8(bh_packet)==1) {bh_packet_size=0;bh_packet_index= -1;}nb_zero(p,2320);bh_active=bh_active-1;}}return 1;
}
fn bh_acl_input(packet,size) {
    if size<5 || size>1029 || bh_u16(packet+3)!=size-5 {return bh_bad(-74,-1);}let flags=bh_u16(packet+1);let handle=flags&4095;let boundary=(flags>>12)&3;let index=bh_find(handle);if handle>0x0eff || flags&0xc000 || boundary==3 || boundary==0 {return bh_bad(-74,index);}if index<0 {bh_unknown_acl=bh_unknown_acl+1;return 0;}let p=bh_slot(index);let n=size-5;
    if load64(p+136) {if bh_host_flow {store64(p+224,load64(p+224)+1);}bh_rx_packets=bh_rx_packets+1;return 1;}if load64(p+96) {return -11;}let have=load64(p+72);let total=load64(p+80);let skip=load64(p+232);let started=load64(p+240);
    if (boundary==1 && !started) || (boundary!=1 && started) {return bh_bad(-74,index);}if !started {store64(p+248,load64(p+56));}let at=0;while at<n {if total && have>=total {return bh_bad(-74,index);}if have<4 || !skip {store8(bh_rx(index)+have,load8(packet+5+at));}have=have+1;at=at+1;if have==4 {total=bh_u16(bh_rx(index))+4;let cid=bh_u16(bh_rx(index)+2);skip=!bh_cid(cid);if !skip && total>1028 {return bh_bad(-90,index);}store64(p+104,cid);}}
    store64(p+72,have);store64(p+80,total);store64(p+232,skip);store64(p+240,1);if total && have==total {if skip {store64(p+72,0);store64(p+80,0);store64(p+104,0);store64(p+232,0);bh_unknown_cid=bh_unknown_cid+1;}else {store64(p+96,1);}store64(p+88,0);store64(p+240,0);}else if n || !started {store64(p+88,bh_now+10000);}if bh_host_flow {store64(p+224,load64(p+224)+1);}bh_rx_packets=bh_rx_packets+1;return 1;
}
fn bh_input(packet,size,now) {
    if !bh_work {return -19;}if packet<=0 || size<1 || now<0 || now<bh_now {return -22;}if bh_error {return bh_error;}bh_now=now;if load8(packet)==2 {return bh_acl_input(packet,size);}if load8(packet)!=4 || size<3 || size!=load8(packet+2)+3 {return bh_bad(-74,-1);}let event=load8(packet+1);
    if event==19 {if size<4 {return bh_bad(-74,-1);}return bh_completed(packet,size);}if event==5 {return bh_disconnected(packet,size);}
    if event==16 || event==26 {if size!=4 {return bh_bad(-74,-1);}let error= -5;if event==26 {error= -105;}let r=bh_emit(8,0,error,load8(packet+3),packet,size);bh_error=error;if r {return r;}return error;}
    if event==8 || event==48 {let expected=7;if event==48 {expected=6;}if size!=expected {return bh_bad(-74,-1);}let index=bh_find(bh_u16(packet+4));let connection=0;if index>=0 {let p=bh_slot(index);connection=load64(p+216);if !load8(packet+3) && event==8 {if load8(packet+6)>2 {return bh_bad(-74,index);}store64(p+56,load8(packet+6));}}let r=bh_emit(4,connection,load8(packet+3),event,packet,size);if r {return r;}return 1;}
    if event==62 {if size<4 {return bh_bad(-74,-1);}let sub=load8(packet+3);if sub==1 || sub==10 {return bh_connected(packet,size,sub==10);}if sub==3 || sub==4 {let expected=13;if sub==4 {expected=15;}if size!=expected {return bh_bad(-74,-1);}let index=bh_find(bh_u16(packet+5));let connection=0;let kind=3;if sub==4 {kind=5;}if index>=0 {let p=bh_slot(index);connection=load64(p+216);if !load8(packet+4) {if sub==3 {let interval=bh_u16(packet+7);let latency=bh_u16(packet+9);let timeout=bh_u16(packet+11);if !bh_params(interval,latency,timeout) {return bh_bad(-74,index);}store64(p+32,interval);store64(p+40,latency);store64(p+48,timeout);}else {nb_copy(p+160,packet+7,8);}}}let r=bh_emit(kind,connection,load8(packet+4),0,packet,size);if r {return r;}return 1;}
        if sub==7 {if size!=14 {return bh_bad(-74,-1);}let index=bh_find(bh_u16(packet+4));let connection=0;if index>=0 {let p=bh_slot(index);let tx=bh_u16(packet+6);let rx=bh_u16(packet+10);let tt=bh_u16(packet+8);let rt=bh_u16(packet+12);if tx<27 || tx>251 || rx<27 || rx>251 || tt<328 || tt>17040 || rt<328 || rt>17040 {return bh_bad(-74,index);}store64(p+168,tx);store64(p+176,tt);store64(p+184,rx);store64(p+192,rt);connection=load64(p+216);}let r=bh_emit(6,connection,0,0,packet,size);if r {return r;}return 1;}
        if (sub==5 && size!=16) || (sub==6 && size!=14) {return bh_bad(-74,-1);}let connection=0;if sub==5 || sub==6 {let index=bh_find(bh_u16(packet+4));if index>=0 {connection=load64(bh_slot(index)+216);}}let r=bh_emit(7,connection,0,(event<<8)|sub,packet,size);if r {return r;}return 1;
    }let r=bh_emit(7,0,0,event,packet,size);if r {return r;}return 1;
}
fn bh_tick(now) {if !bh_work {return -19;}if now<0 || now<bh_now {return -22;}bh_now=now;if bh_error {return bh_error;}let i=0;while i<bh_links {let p=bh_slot(i);if load64(p) && load64(p+240) && !load64(p+96) && load64(p+88) && now>=load64(p+88) {return bh_bad(-110,i);}i=i+1;}return 0;}

// Drop caller-owned storage and all exported views before the caller frees it.
fn bh_deinit() {bh_work=0;bh_links=0;bh_active=0;bh_now=0;bh_error=0;bh_last_error=0;bh_fault_connection=0;bh_acl_mtu=27;bh_buffers=1;bh_free=1;bh_host_flow=0;bh_bad_packets=0;bh_rx_packets=0;bh_tx_packets=0;bh_unknown_acl=0;bh_unknown_completed=0;bh_unknown_cid=0;bh_event_head=0;bh_event_count=0;bh_event_dropped=0;bh_event_kind=0;bh_event_connection=0;bh_event_status=0;bh_event_detail=0;bh_event_data=0;bh_event_size=0;bh_packet=0;bh_packet_size=0;bh_packet_index=-1;bh_packet_connection=0;bh_packet_fragment=0;bh_tx_cursor=0;bh_last_packet_kind=0;bh_message_cid=0;bh_message_data=0;bh_message_size=0;bh_message_encrypted=0;return 0;}
