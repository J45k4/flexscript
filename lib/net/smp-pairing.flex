import "bytes.flex";
// SMP phase1/session core, LE only. No allocation, entropy, HCI or encryption.
// Caller storage256+1536*links (1..4); serialize calls in the owning host task.
// Config8 octets: IO,OOB,AuthReq,maxKey,initDist,respDist,minKey,policy.
// Policy:1 requireMITM,2 requireSC,4 requireBond,8 secureOOB,16 requireConsent.
// Addresses: type0/1 then6 wire-order octets. Tokens are positive monotonically
// increasing connection generations, retained as a floor across deinit/reinit.
// States:1 idle,2 waitResponse,3 featuresReady,4 failed,5 timeoutLocked,
// 6 waitConsent,7 waitPairRequest,8 waitSecurityDecision. None means authenticated.
// Slot:0 token,8 state,16 role,24 policy,32 minKey;80 SC,88 method(JW0,
// passkey1,numeric2,OOB3),96 keySize,104 bond,112/120 keyDist,128 local action
// (none0,input1,display2,numeric3,OOB4),136 plannedAuth,144 failure,152 deadline,
// 160 peerSecurityRequest,168 txSize,176 txCode,184 events,192 epoch,200 txTag,
// 208 peerFailure,216 CT2,224 verifiedSecurity(always0 in phase1),232 localReq;
// 240/248 addresses,256 config8,264 peerPDU7,272 preq7,280 pres7,320 TX65.
// 512..1535 is reserved sensitive material for the subsequent crypto phase.
global sm_work=0;
global sm_links=0;
global sm_active=0;
global sm_token_floor=0;
global sm_now=0;
global sm_packet=0;
global sm_packet_size=0;
global sm_packet_connection=0;
global sm_packet_generation=0;
global sm_event_kind=0;
global sm_event_connection=0;
global sm_event_generation=0;
global sm_event_status=0;
fn sm_size(links) {if links<1 || links>4 {return -22;}return 256+links*1536;}
fn sm_range(p,n) {return p>0 && n>=0 && p<=9223372036854775807-n;}
fn sm_input_range(p,n) {return sm_range(p,n) && !(p<sm_work+sm_size(sm_links) && sm_work<p+n);}
fn sm_slot(index) {return sm_work+256+index*1536;}
fn sm_find(token) {if !sm_work || token<=0 {return 0;}let i=0;while i<sm_links {let p=sm_slot(i);if load64(p)==token {return p;}i=i+1;}return 0;}
fn sm_time(now) {if now<sm_now || now<0 || now>9223372036854745807 {return -22;}sm_now=now;return 0;}
fn sm_epoch(p) {let n=load64(p+192);if n==9223372036854775807 {return -75;}store64(p+192,n+1);return 0;}
fn sm_views(token) {if sm_packet_connection==token {sm_packet=0;sm_packet_size=0;sm_packet_connection=0;sm_packet_generation=0;}if sm_event_connection==token {sm_event_kind=0;sm_event_connection=0;sm_event_generation=0;sm_event_status=0;}return 0;}
fn sm_clear_attempt(p) {nb_zero(p+80,112);nb_zero(p+200,40);nb_zero(p+264,56);nb_zero(p+320,1216);sm_views(load64(p));return 0;}
fn sm_expire(p) {if load64(p+152) && sm_now>=load64(p+152) {sm_clear_attempt(p);store64(p+8,5);store64(p+144,-110);store64(p+184,8);sm_epoch(p);return 1;}return 0;}
fn sm_tick(now) {if !sm_work {return -19;}let r=sm_time(now);if r {return r;}let i=0;while i<sm_links {let p=sm_slot(i);if load64(p) {sm_expire(p);}i=i+1;}return 0;}
fn sm_live_time(p,now) {let r=sm_time(now);if r {return r;}sm_expire(p);if load64(p+8)==5 {return -110;}return 0;}
fn sm_init(work,capacity,links) {
    if sm_work {return -16;}let size=sm_size(links);if size<0 || capacity<size || !sm_range(work,capacity) || work&7 {return -22;}
    nb_zero(work,size);sm_work=work;sm_links=links;sm_active=0;sm_now=0;sm_views(sm_packet_connection);sm_views(sm_event_connection);return 0;
}
fn sm_features(pdu) {if load8(pdu+1)>4 || load8(pdu+2)>1 || (load8(pdu+3)&3)>1 {return 10;}if load8(pdu+4)<7 || load8(pdu+4)>16 {return 6;}return 0;}
fn sm_config(config) {
    if !sm_input_range(config,8) {return 0;}let io=load8(config);let auth=load8(config+2);let min=load8(config+6);let policy=load8(config+7);
    return io<=4 && load8(config+1)<=1 && auth<=63 && (auth&3)<=1 && load8(config+3)>=7 && load8(config+3)<=16 && load8(config+4)<=15 && load8(config+5)<=15 && (auth&8 || !((load8(config+4)|load8(config+5))&8)) && min>=7 && min<=load8(config+3) && policy<=31 && (!(policy&1) || auth&4) && (!(policy&2) || auth&8) && (!(policy&4) || (auth&3)==1);
}
fn sm_open(token,role,local,peer,config,now) {
    if !sm_work {return -19;}if token<=sm_token_floor || role<0 || role>1 || !sm_input_range(local,7) || !sm_input_range(peer,7) || load8(local)>1 || load8(peer)>1 || !sm_config(config) || now<sm_now || now<0 || now>9223372036854745807 {return -22;}
    let i=0;while i<sm_links && load64(sm_slot(i)) {i=i+1;}if i==sm_links {return -105;}sm_time(now);let p=sm_slot(i);nb_zero(p,1536);store64(p,token);store64(p+8,1);store64(p+16,role);store64(p+24,load8(config+7));store64(p+32,load8(config+6));store64(p+192,1);nb_copy(p+240,local,7);nb_copy(p+248,peer,7);nb_copy(p+256,config,8);sm_token_floor=token;sm_active=sm_active+1;return 0;
}
fn sm_close(token) {if !sm_work {return -19;}let p=sm_find(token);if !p {return -107;}sm_views(token);nb_zero(p,1536);sm_active=sm_active-1;return 0;}
fn sm_deinit() {if !sm_work {return 0;}if sm_active {return -16;}nb_zero(sm_work,sm_size(sm_links));sm_work=0;sm_links=0;sm_now=0;sm_views(sm_packet_connection);sm_views(sm_event_connection);return 0;}
// Method/action packed as method|(localAction<<4)|(SC<<8). Selection follows
// both legacy and SC association tables; this describes a plan, not link trust.
fn sm_method(io,remote,oob,remote_oob,auth,remote_auth,role) {
    if io<0 || io>4 || remote<0 || remote>4 || oob<0 || oob>1 || remote_oob<0 || remote_oob>1 || auth<0 || auth>255 || remote_auth<0 || remote_auth>255 || role<0 || role>1 {return -22;}
    let sc=((auth&remote_auth)&8)!=0;let tag=sc<<8;
    if (sc && (oob || remote_oob)) || (!sc && oob && remote_oob) {return tag|67;}
    if !((auth|remote_auth)&4) || io==3 || remote==3 {return tag;}
    if sc && (io==1 || io==4) && (remote==1 || remote==4) {return tag|50;}
    if !sc && io==4 && remote==4 {let action=2;if role {action=1;}return tag|1|(action<<4);}
    if io==2 || (io==4 && (remote==0 || remote==1)) {return tag|17;}
    if remote==2 || remote==4 {return tag|33;}return tag;
}
fn sm_negotiate(p) {
    let preq=p+272;let pres=p+280;let size=load8(preq+4);if load8(pres+4)<size {size=load8(pres+4);}if size<load64(p+32) {return 6;}
    let policy=load64(p+24);let selected=sm_method(load8(p+256),load8(p+265),load8(p+257),load8(p+266),load8(p+258),load8(p+267),load64(p+16));let sc=selected>>8;let method=selected&15;let action=(selected>>4)&15;
    let authenticated=method==1 || method==2 || (method==3 && policy&8);let bond=(load8(preq+3)&3)==1 && (load8(pres+3)&3)==1;let requested=load64(p+232)|load64(p+160);
    if ((policy&2 || requested&8) && !sc) || ((policy&1 || requested&4) && !authenticated) || (policy&4 && !bond) {return 3;}
    let init=load8(preq+5)&load8(pres+5)&15;let resp=load8(preq+6)&load8(pres+6)&15;if !bond {init=0;resp=0;}else if sc {init=init&14;resp=resp&14;if !((init&resp)&8) {init=init&7;resp=resp&7;}}else {init=init&7;resp=resp&7;}
    store64(p+80,sc);store64(p+88,method);store64(p+96,size);store64(p+104,bond);store64(p+112,init);store64(p+120,resp);store64(p+128,action);store64(p+136,authenticated);store64(p+216,sc && ((load8(preq+3)&load8(pres+3))&32)!=0);return 0;
}
fn sm_queue(p,bytes,size,timed) {nb_zero(p+320,72);nb_copy(p+320,bytes,size);store64(p+168,size);store64(p+176,load8(bytes));store64(p+200,load64(p+192));if timed {store64(p+152,sm_now+30000);}return 0;}
fn sm_fail(p,reason,reply) {
    if reply && load64(p+168) {return -11;}if load64(p+192)==9223372036854775807 {return -75;}sm_clear_attempt(p);sm_epoch(p);store64(p+8,4);store64(p+144,reason);store64(p+184,4);
    if reply {store8(p+392,5);store8(p+393,reason);sm_queue(p,p+392,2,0);nb_zero(p+392,2);}return 1;
}
fn sm_features_ready(p) {
    if load64(p+24)&16 {store64(p+8,6);store64(p+184,2);return 0;}
    store64(p+8,3);store64(p+184,1);if load64(p+16)==1 {sm_queue(p,p+280,7,1);}return 0;
}
fn sm_pair(token,now) {
    if !sm_work {return -19;}let p=sm_find(token);if !p {return -107;}if load64(p+16) {return -22;}let state=load64(p+8);if state==5 {return -110;}if state!=1 && state!=4 && state!=8 {return -16;}if load64(p+168) {return -11;}if load64(p+192)==9223372036854775807 {return -75;}
    let r=sm_live_time(p,now);if r {return r;}let requested=load64(p+160);sm_clear_attempt(p);sm_epoch(p);store64(p+160,requested);store8(p+272,1);nb_copy(p+273,p+256,6);store64(p+8,2);sm_queue(p,p+272,7,1);return 0;
}
fn sm_request_security(token,now) {
    if !sm_work {return -19;}let p=sm_find(token);if !p {return -107;}if load64(p+16)!=1 {return -22;}let state=load64(p+8);if state==5 {return -110;}if state!=1 && state!=4 {return -16;}if load64(p+168) {return -11;}if load64(p+192)==9223372036854775807 {return -75;}
    let auth=load8(p+258);if auth&4 && load8(p+256)==3 && !load8(p+257) && !(load64(p+24)&8) {return -22;}let r=sm_live_time(p,now);if r {return r;}sm_clear_attempt(p);sm_epoch(p);store64(p+232,auth);store64(p+8,7);store8(p+392,11);store8(p+393,auth);sm_queue(p,p+392,2,1);nb_zero(p+392,2);return 0;
}
fn sm_consent(token,generation,accepted,now) {
    if !sm_work {return -19;}let p=sm_find(token);if !p {return -107;}if accepted!=0 && accepted!=1 {return -22;}let r=sm_live_time(p,now);if r {return r;}if load64(p+8)!=6 || load64(p+192)!=generation {return -116;}if load64(p+168) {return -11;}
    if !accepted {let code=sm_fail(p,8,1);if code<0 {return code;}return 0;}if load64(p+192)==9223372036854775807 {return -75;}sm_views(token);sm_epoch(p);store64(p+8,3);store64(p+184,1);if load64(p+16)==1 {sm_queue(p,p+280,7,1);}return 0;
}
// Result:1 consumed,0 ignored RFU,2 valid crypto/key PDU for phase2 handoff;
// -11 retains input under TX backpressure;errors never masquerade as success.
fn sm_input(token,packet,size,now) {
    if !sm_work {return -19;}let p=sm_find(token);if !p {return -107;}if size<0 || size>65535 || (size && !sm_input_range(packet,size)) {return -22;}
    let r=sm_live_time(p,now);if r {return r;}let state=load64(p+8);if !size {return sm_fail(p,10,1);}let code=load8(packet);if code==0 || code>14 {return 0;}
    if code==5 {if size!=2 {return sm_fail(p,10,1);}let reason=load8(packet+1);let raw=reason;if reason<1 || reason>15 {reason=8;}r=sm_fail(p,reason,0);if r>0 {store64(p+208,raw);}return r;}
    if code==11 {
        if size!=2 || (load8(packet+1)&3)>1 {return sm_fail(p,10,1);}if load64(p+16)!=0 {return sm_fail(p,8,1);}if state==2 || state==3 || state==6 {return 0;}if load64(p+168) {return -11;}if load64(p+192)==9223372036854775807 {return -75;}
        let auth=load64(p+160)| (load8(packet+1)&63);sm_clear_attempt(p);sm_epoch(p);store64(p+160,auth);store64(p+8,8);store64(p+184,16);store64(p+152,sm_now+30000);return 1;
    }
    if code==1 || code==2 {
        if load64(p+168) {return -11;}if size!=7 {return sm_fail(p,10,1);}let error=sm_features(packet);if error {return sm_fail(p,error,1);}
        if code==1 {if load64(p+16)!=1 || (state!=1 && state!=4 && state!=7) {return sm_fail(p,8,1);}}
        else if load64(p+16)!=0 || state!=2 {return sm_fail(p,8,1);}
        if load64(p+192)>=9223372036854775806 {return -75;}
        if code==1 {let requested=load64(p+232);sm_clear_attempt(p);store64(p+232,requested);sm_epoch(p);nb_copy(p+272,packet,7);store8(p+280,2);nb_copy(p+281,p+256,6);store8(p+285,load8(p+285)&load8(packet+5)&15);store8(p+286,load8(p+286)&load8(packet+6)&15);store64(p+152,sm_now+30000);}
        else {let mask=7;if (load8(p+275)&load8(packet+3))&8 {mask=15;}if (load8(packet+5)&mask)&~load8(p+277) || (load8(packet+6)&mask)&~load8(p+278) {return sm_fail(p,10,1);}sm_epoch(p);nb_copy(p+280,packet,7);}
        nb_copy(p+264,packet,7);error=sm_negotiate(p);if error {return sm_fail(p,error,1);}sm_features_ready(p);return 1;
    }
    let expected=17;if code==7 {expected=11;}else if code==9 {expected=8;}else if code==12 {expected=65;}else if code==14 {expected=2;}
    if size!=expected {return sm_fail(p,10,1);}if state==3 {if load64(p+168) {return -11;}return 2;}return sm_fail(p,8,1);
}
fn sm_next_packet(token) {if !sm_work {return -19;}let p=sm_find(token);if !p {return -107;}if load64(p+8)==5 {return -110;}let size=load64(p+168);if !size {return 0;}sm_packet=p+320;sm_packet_size=size;sm_packet_connection=token;sm_packet_generation=load64(p+200);return size;}
fn sm_packet_sent(token,generation,now) {
    if !sm_work {return -19;}let p=sm_find(token);if !p {return -107;}let r=sm_live_time(p,now);if r {return r;}if !load64(p+168) || load64(p+200)!=generation {return -116;}nb_zero(p+320,72);store64(p+168,0);store64(p+176,0);store64(p+200,0);if sm_packet_connection==token && sm_packet_generation==generation {sm_packet=0;sm_packet_size=0;sm_packet_connection=0;sm_packet_generation=0;}return 0;
}
fn sm_next_event(token) {
    if !sm_work {return -19;}let p=sm_find(token);if !p {return -107;}let flags=load64(p+184);if !flags {return 0;}let kind=1;while !(flags&(1<<(kind-1))) {kind=kind+1;}
    sm_event_kind=kind;sm_event_connection=token;sm_event_generation=load64(p+192);sm_event_status=load64(p+144);if kind==5 {sm_event_status=load64(p+160);}return 1;
}
fn sm_event_consumed(token,generation,kind) {
    if !sm_work {return -19;}let p=sm_find(token);if !p {return -107;}if kind<1 || kind>5 {return -22;}let bit=1<<(kind-1);if load64(p+192)!=generation || !(load64(p+184)&bit) {return -116;}store64(p+184,load64(p+184)&~bit);if sm_event_connection==token && sm_event_generation==generation && sm_event_kind==kind {sm_event_kind=0;sm_event_connection=0;sm_event_generation=0;sm_event_status=0;}return 0;
}

// Public224-byte phase1 snapshot; fixed words followed by copied addresses/PDUs.
// It contains no keys and does not expose the sensitive region reserved above.
fn sm_snapshot(token,out,capacity) {
    if !sm_work {return -19;}let p=sm_find(token);if !p {return -107;}if capacity<224 || !sm_input_range(out,224) {return -22;}nb_zero(out,224);
    store64(out,load64(p+8));store64(out+8,load64(p+16));let i=0;while i<8 {store64(out+16+i*8,load64(p+80+i*8));i=i+1;}
    store64(out+80,load64(p+224));store64(out+88,load64(p+144));store64(out+96,load64(p+152));store64(out+104,load64(p+192));store64(out+112,load64(p+168));store64(out+120,load64(p+184));store64(out+128,load64(p+160));store64(out+136,load64(p+232));store64(out+144,load64(p+216));store64(out+152,load64(p+208));nb_copy(out+160,p+240,7);nb_copy(out+168,p+248,7);nb_copy(out+176,p+272,7);nb_copy(out+184,p+280,7);nb_copy(out+192,p+256,8);nb_copy(out+200,p+264,7);store64(out+208,token);return 0;
}
