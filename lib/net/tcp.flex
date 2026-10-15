import "ethernet-ipv4.flex";
// Bounded cooperative TCP: one connection, one outstanding segment, 2048-byte
// receive window. Caller owns 4096 bytes; no allocation, OS or device calls.
// States: closed/listen/syn-sent/syn-received/established/fin-wait-1/fin-wait-2/
// close-wait/last-ack/closing/time-wait/error (0..11).
global tc_workspace=0;
global tc_state=0;
global tc_error=0;
global tc_local_ip=0;
global tc_remote_ip=0;
global tc_local_port=0;
global tc_remote_port=0;
global tc_iss=0;
global tc_snd_una=0;
global tc_snd_next=0;
global tc_rcv_next=0;
global tc_peer_window=0;
global tc_window_seq=0;
global tc_window_ack=0;
global tc_mss=536;
global tc_rx_size=0;
global tc_eof=0;
global tc_close_wanted=0;
global tc_ack_pending=0;
global tc_syn_repeat=0;
global tc_tx_pending=0;
global tc_tx_flags=0;
global tc_tx_seq=0;
global tc_tx_end=0;
global tc_challenge_at=0;
global tc_tx_size=0;
global tc_tx_sent=0;
global tc_tx_first=0;
global tc_tx_retries=0;
global tc_tx_due=0;
global tc_rto=1000;
global tc_srtt=0;
global tc_rttvar=0;
global tc_rtt_seen=0;
global tc_sample_taken=0;
global tc_state_due=0;
global tc_probe_due=0;
global tc_probe_delay=1000;
global tc_last_now=0;
global tc_retransmits=0;
global tc_bad_packets=0;
fn tc_add(a,b) {return (a+b)&4294967295;}
fn tc_diff(a,b) {let d=(a-b)&4294967295;if d>=2147483648 {d=d-4294967296;}return d;}
fn tc_fail(error) {tc_state=11;tc_error=error;tc_tx_pending=0;tc_ack_pending=0;tc_syn_repeat=0;tc_rx_size=0;tc_eof=0;return error;}
fn tc_init(workspace,capacity) {if !workspace || capacity<4096 {return -22;}tc_workspace=workspace;tc_prepare(0,0);tc_remote_ip=0;tc_remote_port=0;tc_local_port=0;tc_bad_packets=0;tc_state=0;en_zero(workspace,4096);return 0;}
fn tc_prepare(isn,now) {
    tc_error=0;tc_local_ip=en_ip;tc_iss=isn&4294967295;tc_snd_una=tc_iss;tc_snd_next=tc_iss;tc_rcv_next=0;tc_peer_window=0;tc_window_seq=0;tc_window_ack=0;tc_mss=536;tc_rx_size=0;tc_eof=0;tc_close_wanted=0;tc_ack_pending=0;tc_syn_repeat=0;tc_tx_pending=0;tc_tx_sent=0;tc_rto=1000;tc_srtt=0;tc_rttvar=0;tc_rtt_seen=0;tc_state_due=0;tc_probe_due=0;tc_probe_delay=1000;tc_last_now=now;tc_retransmits=0;tc_challenge_at=0;return 0;
}
fn tc_queue(flags,payload,size) {
    if tc_tx_pending {return -11;}if size {en_copy(tc_workspace,payload,size);}tc_tx_seq=tc_snd_next;tc_tx_size=size;tc_tx_flags=flags;tc_tx_pending=1;tc_tx_sent=0;tc_tx_retries=0;tc_sample_taken=0;
    let sequence_size=size;if flags&2 {sequence_size=sequence_size+1;}if flags&1 {sequence_size=sequence_size+1;}tc_tx_end=tc_add(tc_snd_next,sequence_size);return 0;
}
fn tc_connect(ip,port,local_port,isn,now) {
    if !tc_workspace || !en_ip {return -107;}if tc_state && tc_state!=11 {return -16;}
    if !en_valid_ip(ip) || (en_mask<4294967294 && ip==(en_ip|((~en_mask)&4294967295))) || port<1 || port>65535 || local_port<1 || local_port>65535 || now<0 {return -22;}
    tc_prepare(isn,now);tc_remote_ip=ip;tc_remote_port=port;tc_local_port=local_port;tc_state=2;return tc_queue(2,0,0);
}
fn tc_listen(port,isn,now) {
    if !tc_workspace || !en_ip {return -107;}if tc_state && tc_state!=11 {return -16;}if port<1 || port>65535 || now<0 {return -22;}
    tc_prepare(isn,now);tc_local_port=port;tc_remote_ip=0;tc_remote_port=0;tc_state=1;return 0;
}
fn tc_wire(ip,ports,sequence,ack,flags,window,payload,size) {
    if en_tx_size {return -11;}let mac=en_route(ip);if mac<0 {return mac;}let header=20;if flags&2 {header=24;}let length=header+size;let r=en_ip_header(ip,6,length,mac);if r {return r;}
    let p=en_tx+34;en_zero(p,header);en_put16(p,ports>>16);en_put16(p+2,ports&65535);en_put32(p+4,sequence);en_put32(p+8,ack);store8(p+12,(header/4)<<4);store8(p+13,flags);en_put16(p+14,window);
    if flags&2 {store8(p+20,2);store8(p+21,4);en_put16(p+22,1460);}if size {en_copy(p+header,payload,size);}
    let seed=(en_ip>>16)+(en_ip&65535)+(ip>>16)+(ip&65535)+6+length;en_put16(p+16,en_checksum(p,length,seed));en_tx_size=34+length;return 0;
}
fn tc_emit(sequence,flags,payload,size) {let ack=0;if flags&16 {ack=tc_rcv_next;}let r=tc_wire(tc_remote_ip,(tc_local_port<<16)|tc_remote_port,sequence,ack,flags,2048-tc_rx_size,payload,size);if !r {if flags&16 {tc_ack_pending=0;}let length=size;if flags&2 {length=length+1;}if flags&1 {length=length+1;}if length && tc_diff(tc_add(sequence,length),tc_snd_next)>0 {tc_snd_next=tc_add(sequence,length);}}return r;}
fn tc_rtt(sample) {
    if sample<1 {sample=1;}if !tc_rtt_seen {tc_srtt=sample;tc_rttvar=sample/2;tc_rtt_seen=1;}else {let delta=tc_srtt-sample;if delta<0 {delta= -delta;}tc_rttvar=(3*tc_rttvar+delta)/4;tc_srtt=(7*tc_srtt+sample)/8;}
    let variance=4*tc_rttvar;if variance<1 {variance=1;}tc_rto=tc_srtt+variance;if tc_rto<1000 {tc_rto=1000;}if tc_rto>60000 {tc_rto=60000;}return 0;
}
fn tc_send(payload,size,now) {
    if tc_state!=4 && tc_state!=7 {return -107;}if tc_close_wanted {return -32;}if size<0 || (size && !payload) || now<0 {return -22;}if !size {return 0;}if tc_tx_pending || !tc_peer_window {return -11;}
    let n=size;if n>tc_mss {n=tc_mss;}if n>tc_peer_window {n=tc_peer_window;}let r=tc_queue(24,payload,n);if r {return r;}return n;
}
fn tc_receive(out,capacity) {
    if !tc_workspace || !out || capacity<0 {return -22;}if !capacity {return 0;}
    if tc_rx_size {let n=tc_rx_size;if n>capacity {n=capacity;}en_copy(out,tc_workspace+2048,n);en_copy(tc_workspace+2048,tc_workspace+2048+n,tc_rx_size-n);tc_rx_size=tc_rx_size-n;if tc_state>=3 && tc_state<=10 {tc_ack_pending=1;}return n;}
    if tc_error {return tc_error;}if tc_eof {return 0;}return -11;
}
fn tc_close() {if tc_state==1 {tc_state=0;return 0;}if tc_state!=4 && tc_state!=7 {return -107;}tc_close_wanted=1;return 0;}
fn tc_timewait(now) {tc_state=10;tc_state_due=now+240000;tc_tx_pending=0;return 0;}
fn tc_acknowledge(ack,now) {
    let advance=tc_diff(ack,tc_snd_una);if advance<=0 {return 0;}if tc_diff(ack,tc_snd_next)>0 || !tc_tx_pending || !tc_tx_sent {return -74;}
    if !tc_tx_retries && !tc_sample_taken {tc_rtt(now-tc_tx_first);tc_sample_taken=1;}tc_snd_una=ack;
    let n=tc_diff(ack,tc_tx_seq);if n<0 {return -74;}
    if ack==tc_tx_end {
        let flags=tc_tx_flags;tc_tx_pending=0;
        if flags&1 {if tc_state==5 {tc_state=6;tc_state_due=now+60000;}else if tc_state==8 {tc_state=0;}else if tc_state==9 {tc_timewait(now);}}
    }else {if n>tc_tx_size || (tc_tx_flags&3) {return -74;}en_copy(tc_workspace,tc_workspace+n,tc_tx_size-n);tc_tx_size=tc_tx_size-n;tc_tx_seq=ack;tc_tx_due=now+tc_rto;if ack==tc_snd_next {tc_tx_sent=0;tc_tx_retries=0;tc_sample_taken=0;}}return 0;
}
fn tc_challenge(now) {if now>=tc_challenge_at {tc_ack_pending=1;tc_challenge_at=now+100;}return 0;}
fn tc_options(p,header) {
    let mss=536;let i=20;while i<header {let kind=load8(p+i);if !kind {return mss;}if kind==1 {i=i+1;}else {if i+2>header {return -74;}let n=load8(p+i+1);if n<2 || i+n>header {return -74;}if kind==2 {if n!=4 {return -74;}mss=en_u16(p+i+2);if !mss {return -74;}if mss>1460 {mss=1460;}}i=i+n;}}return mss;
}
fn tc_reset_reply(source,ports,sequence,ack,flags,length) {
    if flags&4 {return 0;}if flags&16 {return tc_wire(source,ports,ack,0,4,0,0,0);}let count=length;if flags&2 {count=count+1;}if flags&1 {count=count+1;}return tc_wire(source,ports,0,tc_add(sequence,count),20,0,0,0);
}
fn tc_input(now) {
    if !tc_workspace || !en_tcp_data || en_tcp_target!=en_ip || !en_valid_ip(en_tcp_source) {return 0;}let p=en_tcp_data;let size=en_tcp_size;if size<20 {tc_bad_packets=tc_bad_packets+1;return -74;}
    let header=(load8(p+12)>>4)*4;let seed=(en_tcp_source>>16)+(en_tcp_source&65535)+(en_tcp_target>>16)+(en_tcp_target&65535)+6+size;
    if header<20 || header>size || en_checksum(p,size,seed) {tc_bad_packets=tc_bad_packets+1;return -74;}let options=tc_options(p,header);if options<0 {return options;}
    let source_port=en_u16(p);let target_port=en_u16(p+2);if !source_port || !target_port {return -74;}let sequence=en_u32(p+4);let ack=en_u32(p+8);let flags=load8(p+13);let length=size-header;let window=en_u16(p+14);let ports=(target_port<<16)|source_port;
    if !tc_state || tc_state==11 || target_port!=tc_local_port || (tc_state!=1 && (en_tcp_source!=tc_remote_ip || source_port!=tc_remote_port)) {return tc_reset_reply(en_tcp_source,ports,sequence,ack,flags,length);}
    if tc_state==1 {
        if flags&4 {return 0;}if flags&16 {return tc_reset_reply(en_tcp_source,ports,sequence,ack,flags,length);}if !(flags&2) {return 0;}
        tc_remote_ip=en_tcp_source;tc_remote_port=source_port;tc_rcv_next=tc_add(sequence,1);tc_window_seq=sequence;tc_window_ack=0;tc_peer_window=window;tc_mss=options;tc_state=3;return tc_queue(18,0,0);
    }
    if tc_state==2 {
        let valid_ack=(flags&16) && ack==tc_snd_next && tc_tx_sent;
        if (flags&16) && !valid_ack {return tc_reset_reply(en_tcp_source,ports,sequence,ack,flags,length);}if flags&4 {if valid_ack {return tc_fail(-111);}return 0;}if !(flags&2) {return 0;}
        tc_rcv_next=tc_add(sequence,1);tc_window_seq=sequence;tc_window_ack=ack;tc_peer_window=window;tc_mss=options;
        if valid_ack {tc_acknowledge(ack,now);if tc_tx_retries && tc_rto<3000 {tc_rto=3000;}tc_state=4;tc_ack_pending=1;}else {tc_state=3;tc_tx_flags=18;tc_syn_repeat=1;}return 0;
    }
    // A duplicate SYN retransmits SYN-ACK without corrupting the sequence space.
    if tc_state==3 && (flags&2) && tc_add(sequence,1)==tc_rcv_next && !(flags&4) {tc_syn_repeat=1;return 0;}
    let delta=tc_diff(sequence,tc_rcv_next);let segment_length=length;if flags&1 {segment_length=segment_length+1;}let available=2048-tc_rx_size;let acceptable=0;
    if !segment_length {acceptable=(!available && !delta) || (available && delta>=0 && delta<available);}else if available {acceptable=(delta>=0 && delta<available) || (delta<0 && delta+segment_length>0);}
    if !acceptable {
        if !(flags&4) {tc_ack_pending=1;if tc_state==10 && (flags&1) && tc_add(sequence,segment_length)==tc_rcv_next {tc_state_due=now+240000;}}return 0;
    }
    if flags&4 {if tc_state==10 {return 0;}if !delta {return tc_fail(-104);}tc_challenge(now);return 0;}
    if flags&2 {tc_challenge(now);return 0;}if !(flags&16) {return 0;}
    if tc_diff(ack,tc_snd_next)>0 || tc_diff(ack,tc_snd_una)< -65535 {tc_challenge(now);return 0;}
    if tc_state==3 {if ack!=tc_snd_next || !tc_tx_sent {return tc_reset_reply(en_tcp_source,ports,sequence,ack,flags,length);}tc_acknowledge(ack,now);tc_state=4;}
    else {let r=tc_acknowledge(ack,now);if r {tc_ack_pending=1;return 0;}}
    if tc_diff(ack,tc_snd_una)>=0 && (tc_diff(sequence,tc_window_seq)>0 || (sequence==tc_window_seq && tc_diff(ack,tc_window_ack)>=0)) {tc_peer_window=window;tc_window_seq=sequence;tc_window_ack=ack;if window {tc_probe_due=0;tc_probe_delay=1000;}}
    if tc_state==0 || tc_state==10 {if flags&1 {tc_ack_pending=1;}return 0;}
    if delta>0 {if segment_length {tc_ack_pending=1;}return 0;}let skip= -delta;if skip>length {skip=length;}let n=length-skip;let accepted=n;if accepted>available {accepted=available;}
    if accepted && !tc_eof {en_copy(tc_workspace+2048+tc_rx_size,p+header+skip,accepted);tc_rx_size=tc_rx_size+accepted;tc_rcv_next=tc_add(tc_rcv_next,accepted);tc_ack_pending=1;}
    if (flags&1) && accepted==n && tc_add(sequence,length)==tc_rcv_next && !tc_eof {
        tc_eof=1;tc_rcv_next=tc_add(tc_rcv_next,1);tc_ack_pending=1;if tc_state==4 {tc_state=7;}else if tc_state==5 {tc_state=9;}else if tc_state==6 {tc_timewait(now);}
    }if length {tc_ack_pending=1;}return 0;
}
fn tc_poll(now) {
    tc_last_now=now;if !tc_state || tc_state==11 {return 0;}if en_ip!=tc_local_ip {return tc_fail(-107);}en_now=now;
    if tc_state==10 && now>=tc_state_due {tc_state=0;tc_ack_pending=0;return 0;}if tc_state==6 && now>=tc_state_due {return tc_fail(-110);}
    if tc_syn_repeat {let r=tc_emit(tc_tx_seq,tc_tx_flags,tc_workspace,tc_tx_size);if !r {tc_syn_repeat=0;}return r;}
    // Fresh output carries the current ACK/window itself. Sending a pure ACK
    // first on every read can indefinitely postpone a queued application write.
    let fresh_data=tc_tx_pending && !tc_tx_sent && tc_tx_size && tc_peer_window && (tc_tx_flags&16);
    if tc_ack_pending && tc_state!=2 && tc_state!=3 && !fresh_data {return tc_emit(tc_snd_next,16,0,0);}
    if tc_close_wanted && !tc_tx_pending && (tc_state==4 || tc_state==7) {let state=5;if tc_state==7 {state=8;}tc_queue(17,0,0);tc_state=state;}
    if tc_tx_pending {
        if !tc_peer_window && !(tc_tx_flags&2) {
            if !tc_probe_due {tc_probe_due=now+tc_probe_delay;}
            if now>=tc_probe_due {let size=0;let sequence=tc_add(tc_snd_next,-1);if tc_tx_size {size=1;sequence=tc_tx_seq;}let r=tc_emit(sequence,16,tc_workspace,size);if r {return r;}if size {tc_tx_sent=1;tc_tx_due=now+tc_rto;tc_sample_taken=1;}tc_probe_delay=tc_probe_delay*2;if tc_probe_delay>60000 {tc_probe_delay=60000;}tc_probe_due=now+tc_probe_delay;}return 0;
        }
        if !tc_tx_sent || now>=tc_tx_due {
            if tc_tx_sent && tc_tx_retries>=8 {return tc_fail(-110);}let size=tc_tx_size;if !(tc_tx_flags&3) && size>tc_peer_window {size=tc_peer_window;}let r=tc_emit(tc_tx_seq,tc_tx_flags,tc_workspace,size);if r {return r;}
            if tc_tx_sent {tc_tx_retries=tc_tx_retries+1;tc_retransmits=tc_retransmits+1;tc_rto=tc_rto*2;if tc_rto>60000 {tc_rto=60000;}}else {tc_tx_first=now;tc_tx_sent=1;}tc_tx_due=now+tc_rto;
        }return 0;
    }
    if !tc_peer_window && (tc_state==4 || tc_state==7) {
        if !tc_probe_due {tc_probe_due=now+tc_probe_delay;}if now>=tc_probe_due {let r=tc_emit(tc_add(tc_snd_next,-1),16,0,0);if r {return r;}tc_probe_delay=tc_probe_delay*2;if tc_probe_delay>60000 {tc_probe_delay=60000;}tc_probe_due=now+tc_probe_delay;}
    }return 0;
}

// Opaque 512-byte snapshots allow an independent protocol-owned connection.
// Buffers remain caller-owned and must outlive every snapshot referencing them.
fn tc_context_save(context,capacity) {
    if !context || capacity<512 {return -22;}store64(context,0x4654435043545831);store64(context+8,41);
    store64(context+16,tc_workspace);
    store64(context+24,tc_state);
    store64(context+32,tc_error);
    store64(context+40,tc_local_ip);
    store64(context+48,tc_remote_ip);
    store64(context+56,tc_local_port);
    store64(context+64,tc_remote_port);
    store64(context+72,tc_iss);
    store64(context+80,tc_snd_una);
    store64(context+88,tc_snd_next);
    store64(context+96,tc_rcv_next);
    store64(context+104,tc_peer_window);
    store64(context+112,tc_window_seq);
    store64(context+120,tc_window_ack);
    store64(context+128,tc_mss);
    store64(context+136,tc_rx_size);
    store64(context+144,tc_eof);
    store64(context+152,tc_close_wanted);
    store64(context+160,tc_ack_pending);
    store64(context+168,tc_syn_repeat);
    store64(context+176,tc_tx_pending);
    store64(context+184,tc_tx_flags);
    store64(context+192,tc_tx_seq);
    store64(context+200,tc_tx_end);
    store64(context+208,tc_challenge_at);
    store64(context+216,tc_tx_size);
    store64(context+224,tc_tx_sent);
    store64(context+232,tc_tx_first);
    store64(context+240,tc_tx_retries);
    store64(context+248,tc_tx_due);
    store64(context+256,tc_rto);
    store64(context+264,tc_srtt);
    store64(context+272,tc_rttvar);
    store64(context+280,tc_rtt_seen);
    store64(context+288,tc_sample_taken);
    store64(context+296,tc_state_due);
    store64(context+304,tc_probe_due);
    store64(context+312,tc_probe_delay);
    store64(context+320,tc_last_now);
    store64(context+328,tc_retransmits);
    store64(context+336,tc_bad_packets);
    return 0;
}
fn tc_context_load(context,capacity) {
    if !context || capacity<512 || load64(context)!=0x4654435043545831 || load64(context+8)!=41 {return -22;}
    tc_workspace=load64(context+16);
    tc_state=load64(context+24);
    tc_error=load64(context+32);
    tc_local_ip=load64(context+40);
    tc_remote_ip=load64(context+48);
    tc_local_port=load64(context+56);
    tc_remote_port=load64(context+64);
    tc_iss=load64(context+72);
    tc_snd_una=load64(context+80);
    tc_snd_next=load64(context+88);
    tc_rcv_next=load64(context+96);
    tc_peer_window=load64(context+104);
    tc_window_seq=load64(context+112);
    tc_window_ack=load64(context+120);
    tc_mss=load64(context+128);
    tc_rx_size=load64(context+136);
    tc_eof=load64(context+144);
    tc_close_wanted=load64(context+152);
    tc_ack_pending=load64(context+160);
    tc_syn_repeat=load64(context+168);
    tc_tx_pending=load64(context+176);
    tc_tx_flags=load64(context+184);
    tc_tx_seq=load64(context+192);
    tc_tx_end=load64(context+200);
    tc_challenge_at=load64(context+208);
    tc_tx_size=load64(context+216);
    tc_tx_sent=load64(context+224);
    tc_tx_first=load64(context+232);
    tc_tx_retries=load64(context+240);
    tc_tx_due=load64(context+248);
    tc_rto=load64(context+256);
    tc_srtt=load64(context+264);
    tc_rttvar=load64(context+272);
    tc_rtt_seen=load64(context+280);
    tc_sample_taken=load64(context+288);
    tc_state_due=load64(context+296);
    tc_probe_due=load64(context+304);
    tc_probe_delay=load64(context+312);
    tc_last_now=load64(context+320);
    tc_retransmits=load64(context+328);
    tc_bad_packets=load64(context+336);
    return 0;
}
fn tc_context_matches(context,ip,source_port,target_port) {
    if !context || load64(context)!=0x4654435043545831 {return 0;}return load64(context+48)==ip && load64(context+64)==source_port && load64(context+56)==target_port;
}
