// RFC 5227 address conflict detection. No allocation; one candidate.
// Three randomized probes, two announcements and ongoing ARP monitoring.
// On a conflict always relinquish; optional address defense is not attempted.
global ac_state=0;
global ac_address=0;
global ac_ready=0;
global ac_due=0;
global ac_sent=0;
global ac_seed=1;
global ac_conflicts=0;
global ac_last_start= -60000;
fn ac_random() {ac_seed=(ac_seed*1664525+1013904223)&4294967295;return ac_seed;}
fn ac_reset() {ac_state=0;ac_address=0;ac_ready=0;ac_sent=0;return 0;}
fn ac_start(address,now,seed) {
    if !en_valid_ip(address) || now<0 {return -22;}if ac_state && ac_state!=4 {return -16;}
    ac_state=1;ac_address=address;ac_ready=0;ac_sent=0;ac_seed=seed&4294967295;ac_due=now+ac_random()%1001;
    if ac_conflicts>=10 && ac_due<ac_last_start+60000 {ac_due=ac_last_start+60000;}ac_last_start=ac_due;return 0;
}
fn ac_input(mac,source,target,operation) {
    if !ac_state || ac_state==4 || mac==en_mac {return 0;}
    if source==ac_address || (ac_state==1 && operation==1 && !source && target==ac_address) {ac_state=4;ac_ready=0;ac_conflicts=ac_conflicts+1;if en_ip==ac_address {en_ip=0;en_mask=0;en_gateway=0;en_dns=0;en_tx_size=0;en_fragment_reset();}return -98;}return 0;
}
fn ac_emit(source) {let r=en_arp_request(ac_address);if r {return r;}en_put32(en_tx+28,source);return 0;}
fn ac_poll(now) {
    if !ac_state {return 0;}if ac_state==4 {return -98;}if ac_state==3 || now<ac_due {return 0;}
    if ac_state==1 && ac_sent<3 {let r=ac_emit(0);if r {return r;}ac_sent=ac_sent+1;ac_due=now+1000+ac_random()%1001;if ac_sent==3 {ac_due=now+2000;}return 0;}
    let r=ac_emit(ac_address);if r {return r;}if ac_state==1 {ac_state=2;ac_ready=1;ac_sent=1;ac_due=now+2000;}else {ac_sent=2;ac_state=3;}return 0;
}
