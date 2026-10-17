// SC passkey extension;owned by smp-sc.flex,with its serialized API contract.
// Private slot words960:key,968:haveKey,976:round(0..19),984:UI action.
// 992/1000:local/peer keypress metadata.928..959:short-lived random staging.
// States12:user,13:waitCa(B),14:waitCb(A),15:waitNa(B),16:waitNb(A),
// 17:advance B after its acknowledged random. No keys enter public snapshots.
fn sc_pk_negotiated(p) {return (load8(p+275)&load8(p+283)&16)!=0;}
fn sc_pk_ui(p) {store64(p+984,load64(p+128));store64(p+512,12);return 0;}
fn sc_pk_prepare(p,round,now) {
 if round<0 || round>19 || !load64(p+968) {return -116;}let token=load64(p);let gen=load64(p+528);let lease=load64(p+520);let r=smp_sc_ready(sc_engine,sm_size(sc_links));if r {return r;}
 let bit=128|((load64(p+960)>>round)&1);sc_busy=1;r=smp_sc_random(p+928,16,p+1024,512);if !r {r=smp_f4(p+608,p+672,p+928,bit,p+896,p+1024,512);}sc_busy=0;let safe=sc_recheck(p,token,gen,lease);if safe {return safe;}
 if r {nb_zero(p+896,16);nb_zero(p+928,32);return r;}nb_copy(p+768,p+928,16);nb_zero(p+784,32);nb_zero(p+912,48);store64(p+976,round);return 0;
}
fn sc_pk_error(p,r,now) {if sc_transient(r) {return -11;}if load64(p+8)!=3 || !load64(p+512) {return r;}return sc_abort(p,8,r,1,now);}
fn sc_pk_start(p,now) {
 if load64(p+16) {store64(p+544,1);store64(p+984,0);store64(p+512,13);return 0;}let r=sc_pk_prepare(p,0,now);if r {return sc_pk_error(p,r,now);}store64(p+544,1);store64(p+984,0);return sc_queue(p,3,p+896,16,14,now);
}
// Generate a fresh display passkey. Ten20-bit candidates avoid modulo bias;
// an all-rejected draw returns -11 andpublishes no value. No fixed passkeys.
fn sc_passkey_generate(token,generation,lease,now) {
 let r=sc_bound(token,generation,lease,now,1);if r {return r;}let p=sm_find(token);if load64(p+88)!=1 || load64(p+128)!=2 {return -95;}if load64(p+168) {return -11;}if load64(p+512)!=12 || load64(p+984)!=2 || load64(p+968) {return -116;}
 r=smp_sc_ready(sc_engine,sm_size(sc_links));if r {return r;}sc_busy=1;r=smp_sc_random(p+928,32,p+1024,512);sc_busy=0;let safe=sc_recheck(p,token,generation,lease);if safe {return safe;}if r {nb_zero(p+928,32);return sc_pk_error(p,r,now);}
 let at=0;let value=-1;while at<30 && value<0 {let n=load8(p+928+at)|(load8(p+929+at)<<8)|((load8(p+930+at)&15)<<16);if n<1000000 {value=n;}at=at+3;}nb_zero(p+928,32);if value<0 {return -11;}store64(p+960,value);store64(p+968,1);return 0;
}
fn sc_passkey_prompt(token,generation,lease,out,capacity,now) {
 let r=sc_bound(token,generation,lease,now,1);if r {return r;}if capacity<40 || !sd_external(out,40) {return -22;}let p=sm_find(token);if load64(p+88)!=1 {return -95;}let action=load64(p+984);if !action {return 0;}if action==2 && !load64(p+968) {return -11;}
 store64(out,token);store64(out+8,generation);store64(out+16,lease);store64(out+24,action);let value=0;if action==2 {value=load64(p+960);}store64(out+32,value);return 1;
}
fn sc_passkey_enter(token,generation,lease,value,now) {
 if value<0 || value>999999 {return -22;}let r=sc_bound(token,generation,lease,now,1);if r {return r;}let p=sm_find(token);if load64(p+88)!=1 || load64(p+128)!=1 {return -95;}if load64(p+168) {return -11;}if load64(p+512)!=12 || load64(p+984)!=1 {return -116;}
 if sc_pk_negotiated(p) && !(load64(p+992)&2) {return -11;}if load64(p+968) && load64(p+960)!=value {return -116;}store64(p+960,value);store64(p+968,1);return sc_pk_start(p,now);
}
fn sc_passkey_start(token,generation,lease,now) {
 let r=sc_bound(token,generation,lease,now,1);if r {return r;}let p=sm_find(token);if load64(p+88)!=1 || load64(p+128)!=2 {return -95;}if load64(p+168) {return -11;}if load64(p+512)!=12 || load64(p+984)!=2 || !load64(p+968) {return -116;}return sc_pk_start(p,now);
}
fn sc_passkey_cancel(token,generation,lease,now) {
 let r=sc_bound(token,generation,lease,now,0);if r {return r;}let p=sm_find(token);if load64(p+88)!=1 {return -95;}r=sc_abort(p,1,-13,1,now);if r==-13 {return 0;}return r;
}
fn sc_pk_confirm(p,packet,now) {
 let state=load64(p+512);if state==12 {return -11;}if load64(p+16) && state==13 {let r=sc_pk_prepare(p,load64(p+976),now);if r {return sc_pk_error(p,r,now);}nb_copy(p+800,packet+1,16);r=sc_queue(p,3,p+896,16,15,now);if r {return r;}return 1;}
 if !load64(p+16) && state==14 {nb_copy(p+800,packet+1,16);let r=sc_queue(p,4,p+768,16,16,now);if r {return r;}return 1;}return sc_abort(p,8,0,1,now);
}
fn sc_pk_random(p,packet,now) {
 let role=load64(p+16);let state=load64(p+512);if (role && state!=15) || (!role && state!=16) {return sc_abort(p,8,0,1,now);}let token=load64(p);let gen=load64(p+528);let lease=load64(p+520);let r=smp_sc_ready(sc_engine,sm_size(sc_links));if r {return sc_pk_error(p,r,now);}
 nb_copy(p+784,packet+1,16);let bit=128|((load64(p+960)>>load64(p+976))&1);sc_busy=1;r=smp_f4(p+672,p+608,p+784,bit,p+912,p+1024,512);sc_busy=0;let safe=sc_recheck(p,token,gen,lease);if safe {return safe;}if r {nb_zero(p+784,16);nb_zero(p+912,16);return sc_pk_error(p,r,now);}if !smp_equal(p+912,p+800,16) {return sc_abort(p,4,0,1,now);}nb_zero(p+912,16);
 let round=load64(p+976);if round==19 {r=sc_derive(p);if r {return sc_pk_error(p,r,now);}if role {r=sc_queue(p,4,p+768,16,8,now);}else {r=sc_queue(p,13,p+848,16,9,now);}}
 else {if role {r=sc_queue(p,4,p+768,16,17,now);}else {r=sc_pk_prepare(p,round+1,now);if r {return sc_pk_error(p,r,now);}r=sc_queue(p,3,p+896,16,14,now);}}if r {return r;}return 1;
}
// Metadata:started bit0,complete bit1,digits bits8..15,last type bits16..23,
// monotonically increasing event serial bits24..62. Peer events are tolerant
// of missed start/digit messages andnever change authentication decisions.
fn sc_pk_press_word(word,kind,strict) {
 if kind<0 || kind>4 {return -22;}let count=(word>>8)&255;let serial=word>>24;if serial==549755813887 {return -75;}let flags=word&3;
 if !kind {flags=1;count=0;}else {if strict && (!(flags&1) || flags&2) {return -22;}if kind==1 {if count==6 {if strict {return -22;}}else {count=count+1;}}if kind==2 {if !count {if strict {return -22;}}else {count=count-1;}}if kind==3 {count=0;}if kind==4 {if strict && !count {return -22;}flags=flags|2;}}
 return ((serial+1)<<24)|(kind<<16)|(count<<8)|flags;
}
fn sc_keypress(token,generation,lease,kind,now) {
 if kind<0 || kind>4 {return -22;}let r=sc_bound(token,generation,lease,now,1);if r {return r;}let p=sm_find(token);if load64(p+88)!=1 || load64(p+128)!=1 || !sc_pk_negotiated(p) {return -95;}if load64(p+168) {return -11;}if load64(p+512)!=12 || load64(p+984)!=1 {return -116;}let word=sc_pk_press_word(load64(p+992),kind,1);if word<0 {return word;}
 store8(p+928,kind);r=sc_queue(p,14,p+928,1,12,now);nb_zero(p+928,1);if r {return r;}store64(p+992,word);return 0;
}
fn sc_pk_keypress(p,packet,now) {
 if !sc_pk_negotiated(p) {return 0;}let kind=load8(packet+1);if kind>4 {return sc_abort(p,10,0,1,now);}let state=load64(p+512);if state<12 || state>16 {return 0;}let word=sc_pk_press_word(load64(p+1000),kind,0);if word<0 {return sc_abort(p,8,word,1,now);}store64(p+1000,word);store64(p+152,now+30000);return 0;
}
fn sc_keypress_peer(token,generation,lease,out,capacity,now) {
 let r=sc_bound(token,generation,lease,now,1);if r {return r;}if capacity<24 || !sd_external(out,24) {return -22;}let p=sm_find(token);if load64(p+88)!=1 || !sc_pk_negotiated(p) {return -95;}let word=load64(p+1000);if !word {return 0;}store64(out,word>>24);store64(out+8,(word>>16)&255);store64(out+16,(word>>8)&255);return 1;
}
