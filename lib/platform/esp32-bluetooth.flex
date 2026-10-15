import "esp32-radio-os.flex";
// Original ESP32 ROM controller ABI v0x10005; requires esp32-btdm-elf.
// BLE VHCI transport; controller sleep and simultaneous Wi-Fi coexistence disabled.
global esp_bt_osi=0;
global esp_bt_initialized=0;
global esp_bt_vendor_initialized=0;
global esp_bt_phy_owned=0;
global esp_bt_callbacks=0;
global esp_bt_lifecycle_busy=0;
global esp_bt_cleanup_error=0;
global esp_bt_host_active=0;
global esp_bt_control_task=0;
global esp_bt_max_connections=1;
global esp_bt_count5=0;
global esp_bt_count7=0;
global esp_bt_count8=0;
global esp_bt_irq5=0;
global esp_bt_arg5=0;
global esp_bt_irq7=0;
global esp_bt_arg7=0;
global esp_bt_irq8=0;
global esp_bt_arg8=0;
global esp_bt_critical_depth=0;
global esp_bt_critical_ps=0;
global esp_bt_rx=0;
global esp_bt_rx_size=0;
global esp_bt_tx_ready=0;
global esp_bt_tx_inflight=0;
global esp_bt_tx=0;
global esp_bt_cmd=0;
global esp_bt_cmd_size=0;
global esp_bt_cmd_opcode=0;
global esp_bt_cmd_busy=0;
global esp_bt_cmd_credits=1;
global esp_bt_event_ring=0;
global esp_bt_event_head=0;
global esp_bt_event_count=0;
global esp_bt_event_dropped=0;
global esp_bt_acl_ring=0;
global esp_bt_acl_head=0;
global esp_bt_acl_count=0;
global esp_bt_acl_dropped=0;
global esp_bt_acl_packet=0;
global esp_bt_acl_size=0;
global esp_bt_receive_sequence=0;
global esp_bt_cmd_sequence=0;
global esp_bt_event_sequence=0;
global esp_bt_acl_sequence=0;
global esp_bt_packet=0;
global esp_bt_packet_size=0;
global esp_bt_packet_sequence=0;
global esp_bt_packet_kind=0;
fn esp_bt_irq(source) {
    if source==-1 {esp_bt_count7=esp_bt_count7+1;if esp_bt_irq7 {esp32_call32(esp_bt_irq7,esp_bt_arg7,0,0,0,0,0,0,0);}return 0;}
    if !(esp32_load32(0x3ff000ec)&(1<<source)) {return 0;}
    esp_bt_count5=esp_bt_count5+1;let f=esp_bt_irq5;let arg=esp_bt_arg5;if source==4 {esp_bt_count8=esp_bt_count8+1;f=esp_bt_irq8;arg=esp_bt_arg8;}if f {esp32_call32(f,arg,0,0,0,0,0,0,0);}return 0;
}
fn esp_bt_set_isr(a,b,c,d,e,f,g,h) {
    if a==5 {let r=esp_radio_irq_claim(6);if r {return r;}r=esp_radio_irq_claim(7);if r {return r;}esp_bt_irq5=b;esp_bt_arg5=c;esp_irq_attach(6,esp32_iram_callback(esp_bt_irq));esp_irq_attach(7,esp32_iram_callback(esp_bt_irq));}
    else if a==7 {if esp_irq_soft_handler && esp_irq_soft_handler!=esp32_iram_callback(esp_bt_irq) {return -16;}esp_radio_soft_owned=1;esp_bt_irq7=b;esp_bt_arg7=c;esp_irq_software(esp32_iram_callback(esp_bt_irq));}
    else if a==8 {let r=esp_radio_irq_claim(4);if r {return r;}esp_bt_irq8=b;esp_bt_arg8=c;esp_irq_attach(4,esp32_iram_callback(esp_bt_irq));}
    else {return esp_radio_fail(0x3000+a);}return 0;
}
fn esp_bt_ints_on(a,b,c,d,e,f,g,h) {esp32_irq_mask(esp32_irq_enabled()|2|128);return 0;}
fn esp_bt_disable(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();if !esp_bt_critical_depth {esp_bt_critical_ps=ps;}esp_bt_critical_depth=esp_bt_critical_depth+1;return 0;}
fn esp_bt_restore(a,b,c,d,e,f,g,h) {if !esp_bt_critical_depth {return esp_radio_fail(0x3100);}esp_bt_critical_depth=esp_bt_critical_depth-1;if !esp_bt_critical_depth {esp32_irq_restore(esp_bt_critical_ps);}return 0;}
fn esp_bt_yield(a,b,c,d,e,f,g,h) {return esp_sdk_yield();}
fn esp_bt_sw_intr(a,b,c,d,e,f,g,h) {if a!=0 {return -1;}esp32_irq_raise(128);return 0;}
fn esp_bt_sem_take_isr(a,b,c,d,e,f,g,h) {if b {store8(b,0);}return esp_sdk_sem_take(a,0);}
fn esp_bt_sem_give_isr(a,b,c,d,e,f,g,h) {if b {store8(b,0);}return esp_sdk_sem_give(a);}
fn esp_bt_recv_isr(a,b,c,d,e,f,g,h) {if c {store8(c,0);}return esp_sdk_queue_op(a,b,0,0);}
fn esp_bt_mac(a,b,c,d,e,f,g,h) {return esp_radio_cb_read_mac(a,2,0,0,0,0,0,0);}
fn esp_bt_srand(a,b,c,d,e,f,g,h) {return 0; // Hardware RNG does not have a software seed.
}
fn esp_bt_cycles_hus(a,b,c,d,e,f,g,h) {return a*2; // 500 kHz controller clock: 2 us per LP cycle.
}
fn esp_bt_hus_cycles(a,b,c,d,e,f,g,h) {return a/2;}
fn esp_bt_awake(a,b,c,d,e,f,g,h) {return 0; // Controller modem sleep explicitly disabled.
}
fn esp_bt_no_coex(a,b,c,d,e,f,g,h) {return 0; // Standalone controller, Wi-Fi is not active.
}
fn esp_bt_no_channel(a,b,c,d,e,f,g,h) {return -1;}
fn esp_bt_sleep_phase(a,b,c,d,e,f,g,h) {return esp_radio_fail(0x3200);}
fn esp_bt_patch(a,b,c,d,e,f,g,h) {esp32_call32(esp32_external("config_btdm_funcs_reset"),0,0,0,0,0,0,0,0);esp32_call32(esp32_external("config_ble_funcs_reset"),0,0,0,0,0,0,0,0);return 0;}
fn esp_bt_send_ready(a,b,c,d,e,f,g,h) {esp_bt_tx_ready=1;esp_bt_tx_inflight=0;return 0;}
fn esp_bt_transport_init() {
    if esp_bt_rx {return -16;}
    let rx=esp_sdk_calloc(1,1032);let cmd=esp_sdk_calloc(1,512);let tx=esp_sdk_calloc(1,1032);let events=esp_sdk_calloc(8,528);let acl=esp_sdk_calloc(4,1048);
    if !rx || !cmd || !tx || !events || !acl {esp_sdk_free(rx);esp_sdk_free(cmd);esp_sdk_free(tx);esp_sdk_free(events);esp_sdk_free(acl);return -12;}
    esp_bt_rx=rx;esp_bt_cmd=cmd;esp_bt_tx=tx;esp_bt_event_ring=events;esp_bt_acl_ring=acl;return 0;
}
// VHCI has handed us the packet: consume it even when the bounded application
// queue is full. Rejecting it keeps the controller's delivery path congested.
fn esp_bt_recv(a,b,c,d,e,f,g,h) {
    if !a || !esp_bt_cmd || !esp_bt_event_ring || !esp_bt_acl_ring || b<1 || b>1032 {esp_bt_event_dropped=esp_bt_event_dropped+1;return 0;}
    let type=load8(a);if type==2 {if b<5 || b>1029 || (load8(a+3)|(load8(a+4)<<8))!=b-5 {esp_bt_acl_dropped=esp_bt_acl_dropped+1;return 0;}}
    else if type!=4 || b<3 || b>258 || load8(a+2)+3!=b {esp_bt_event_dropped=esp_bt_event_dropped+1;return 0;}
    let ps=esp32_irq_save();esp_bt_receive_sequence=esp_bt_receive_sequence+1;let sequence=esp_bt_receive_sequence;let opcode= -1;
    if type==4 {if load8(a+1)==14 && b>=6 {opcode=load8(a+4)|(load8(a+5)<<8);if opcode!=0x0c35 {esp_bt_cmd_credits=load8(a+3);}}else if load8(a+1)==15 && b==7 {opcode=load8(a+5)|(load8(a+6)<<8);esp_bt_cmd_credits=load8(a+4);}}
    let out=0;
    if type==2 {if esp_bt_acl_count<4 {let slot=(esp_bt_acl_head+esp_bt_acl_count)%4;out=esp_bt_acl_ring+slot*1048+16;}}
    else if esp_bt_cmd_busy && opcode==esp_bt_cmd_opcode && !esp_bt_cmd_size {out=esp_bt_cmd;}
    else if esp_bt_event_count<8 {let slot=esp_bt_event_head+esp_bt_event_count;if slot>=8 {slot=slot-8;}out=esp_bt_event_ring+slot*528+16;}
    if out {let i=0;while i<b {store8(out+i,load8(a+i));i=i+1;}
        if type==2 {store64(out-16,b);store64(out-8,sequence);esp_bt_acl_count=esp_bt_acl_count+1;}else if out==esp_bt_cmd {esp_bt_cmd_sequence=sequence;esp_bt_cmd_size=b;}else {store64(out-16,b);store64(out-8,sequence);esp_bt_event_count=esp_bt_event_count+1;}
    }else if type==2 {esp_bt_acl_dropped=esp_bt_acl_dropped+1;}else {esp_bt_event_dropped=esp_bt_event_dropped+1;}
    esp32_irq_restore(ps);
    // The scheduler is cooperative. Give the application a chance to drain
    // reports when this callback runs in a task with interrupts unmasked.
    if !esp_bt_critical_depth && !(ps&15) && !esp32_load32(esp32_state()+16) {esp_sdk_yield();}return 0;
}
fn esp_bt_hci_next_event() {
    if !esp_bt_rx || esp_bt_cmd_busy {return 0;}let ps=esp32_irq_save();if !esp_bt_event_count {esp32_irq_restore(ps);return 0;}
    let packet=esp_bt_event_ring+esp_bt_event_head*528;let size=load64(packet);esp_bt_event_sequence=load64(packet+8);let i=0;while i<size {store8(esp_bt_rx+i,load8(packet+16+i));i=i+1;}
    esp_bt_rx_size=size;esp_bt_event_head=esp_bt_event_head+1;if esp_bt_event_head==8 {esp_bt_event_head=0;}esp_bt_event_count=esp_bt_event_count-1;esp32_irq_restore(ps);return size;
}
// A peeked ACL slot stays owned by the consumer until explicit consumption.
fn esp_bt_hci_peek_acl() {if !esp_bt_acl_ring {return 0;}let ps=esp32_irq_save();if !esp_bt_acl_count {esp32_irq_restore(ps);return 0;}let p=esp_bt_acl_ring+esp_bt_acl_head*1048;esp_bt_acl_size=load64(p);esp_bt_acl_sequence=load64(p+8);esp_bt_acl_packet=p+16;esp32_irq_restore(ps);return esp_bt_acl_size;}
fn esp_bt_hci_consume_acl() {let ps=esp32_irq_save();if !esp_bt_acl_count {esp32_irq_restore(ps);return -11;}esp_bt_acl_head=(esp_bt_acl_head+1)%4;esp_bt_acl_count=esp_bt_acl_count-1;esp_bt_acl_packet=0;esp_bt_acl_size=0;esp32_irq_restore(ps);return 0;}
// The host consumes these merged views in receipt order. Independent bounded
// queues protect control capacity without advancing lifecycle/security events
// past earlier data. One consumer owns the view until explicit consumption;
// do not mix this API with the legacy per-queue consumers.
fn esp_bt_hci_peek_packet() {
    let ps=esp32_irq_save();let p=0;let kind=0;
    if esp_bt_event_count {p=esp_bt_event_ring+esp_bt_event_head*528;kind=4;}
    if esp_bt_acl_count {let a=esp_bt_acl_ring+esp_bt_acl_head*1048;if !p || load64(a+8)<load64(p+8) {p=a;kind=2;}}
    esp_bt_packet=0;esp_bt_packet_size=0;esp_bt_packet_sequence=0;esp_bt_packet_kind=kind;
    if p {esp_bt_packet=p+16;esp_bt_packet_size=load64(p);esp_bt_packet_sequence=load64(p+8);}
    esp32_irq_restore(ps);return esp_bt_packet_size;
}
fn esp_bt_hci_consume_packet() {
    let ps=esp32_irq_save();let p=0;
    if esp_bt_packet_kind==4 && esp_bt_event_count {p=esp_bt_event_ring+esp_bt_event_head*528;}
    else if esp_bt_packet_kind==2 && esp_bt_acl_count {p=esp_bt_acl_ring+esp_bt_acl_head*1048;}
    if !p || esp_bt_packet!=p+16 || esp_bt_packet_sequence!=load64(p+8) {esp32_irq_restore(ps);return -16;}
    if esp_bt_packet_kind==4 {esp_bt_event_head=(esp_bt_event_head+1)%8;esp_bt_event_count=esp_bt_event_count-1;}
    else {esp_bt_acl_head=(esp_bt_acl_head+1)%4;esp_bt_acl_count=esp_bt_acl_count-1;}
    esp_bt_packet=0;esp_bt_packet_size=0;esp_bt_packet_sequence=0;esp_bt_packet_kind=0;esp32_irq_restore(ps);return 0;
}
// Raw ACL and Host Number Of Completed Packets only. The latter has no
// Command Complete event and consumes no ordinary HCI command credit.
fn esp_bt_hci_send_packet(packet,size) {
    if !esp_bt_tx {return -19;}if packet<=0 || size<1 || size>1032 {return -22;}let type=load8(packet);
    if type==2 {if size<5 || size>1029 || (load8(packet+3)|(load8(packet+4)<<8))!=size-5 {return -22;}let flags=load8(packet+1)|(load8(packet+2)<<8);if (flags&4095)>0x0eff || flags&0xc000 || ((flags>>12)&3)>1 {return -22;}}
    else if type==1 {if size<9 || load8(packet+1)!=0x35 || load8(packet+2)!=0x0c || size!=load8(packet+3)+4 || !load8(packet+4) || size!=5+load8(packet+4)*4 {return -22;}let i=0;while i<load8(packet+4) {let at=5+i*4;let handle=load8(packet+at)|(load8(packet+at+1)<<8);if handle>0x0eff {return -22;}i=i+1;}}
    else {return -22;}if (esp_bt_cmd_busy && type!=1) || esp_bt_tx_inflight || !esp32_call32(esp32_external("API_vhci_host_check_send_available"),0,0,0,0,0,0,0,0) {return -11;}
    let i=0;while i<size {store8(esp_bt_tx+i,load8(packet+i));i=i+1;}esp_bt_tx_inflight=1;esp_bt_tx_ready=0;esp32_call32(esp32_external("API_vhci_host_send_packet"),esp_bt_tx,size,0,0,0,0,0,0);return 0;
}
fn esp_bt_rom_memory() {
    if esp32_state()!=0x3ffc0000 {return -22;}
    let src=esp32_load32(0x4000d4f4);let i=0;while i<0x1830 {esp32_store32(0x3ffae6e0+i,esp32_load32(src+i));i=i+4;}
    i=0;while i<0x6388 {store8(0x3ffb0000+i,0);i=i+1;}
    i=0;while i<0x7f70 {store8(0x3ffb8000+i,0);i=i+1;}return 0;
}
fn esp_bt_os_init() {
    if esp_bt_osi || esp32_state()!=0x3ffc0000 {return -22;}esp_bt_osi=esp_sdk_calloc(1,252);if !esp_bt_osi {return -12;}
    esp32_store32(esp_bt_osi+0,65541); // version
    esp32_store32(esp_bt_osi+4,esp32_callback32(esp_bt_set_isr)); // set_isr
    esp32_store32(esp_bt_osi+8,esp32_callback32(esp_bt_ints_on)); // ints_on
    esp32_store32(esp_bt_osi+12,esp32_iram_callback32(esp_bt_disable)); // interrupt_disable
    esp32_store32(esp_bt_osi+16,esp32_iram_callback32(esp_bt_restore)); // interrupt_restore
    esp32_store32(esp_bt_osi+20,esp32_callback32(esp_bt_yield)); // task_yield
    esp32_store32(esp_bt_osi+24,esp32_iram_callback32(esp_radio_cb_yield_isr)); // task_yield_from_isr
    esp32_store32(esp_bt_osi+28,esp32_callback32(esp_radio_cb_sem_create)); // semphr_create
    esp32_store32(esp_bt_osi+32,esp32_callback32(esp_radio_cb_free)); // semphr_delete
    esp32_store32(esp_bt_osi+36,esp32_iram_callback32(esp_bt_sem_take_isr)); // semphr_take_from_isr
    esp32_store32(esp_bt_osi+40,esp32_iram_callback32(esp_bt_sem_give_isr)); // semphr_give_from_isr
    esp32_store32(esp_bt_osi+44,esp32_callback32(esp_radio_cb_sem_take)); // semphr_take
    esp32_store32(esp_bt_osi+48,esp32_callback32(esp_radio_cb_sem_give)); // semphr_give
    esp32_store32(esp_bt_osi+52,esp32_callback32(esp_radio_cb_recursive)); // mutex_create
    esp32_store32(esp_bt_osi+56,esp32_callback32(esp_radio_cb_free)); // mutex_delete
    esp32_store32(esp_bt_osi+60,esp32_callback32(esp_radio_cb_lock)); // mutex_lock
    esp32_store32(esp_bt_osi+64,esp32_callback32(esp_radio_cb_unlock)); // mutex_unlock
    esp32_store32(esp_bt_osi+68,esp32_callback32(esp_radio_cb_queue)); // queue_create
    esp32_store32(esp_bt_osi+72,esp32_callback32(esp_radio_cb_free)); // queue_delete
    esp32_store32(esp_bt_osi+76,esp32_callback32(esp_radio_cb_send)); // queue_send
    esp32_store32(esp_bt_osi+80,esp32_iram_callback32(esp_radio_cb_send_isr)); // queue_send_from_isr
    esp32_store32(esp_bt_osi+84,esp32_callback32(esp_radio_cb_recv)); // queue_recv
    esp32_store32(esp_bt_osi+88,esp32_iram_callback32(esp_bt_recv_isr)); // queue_recv_from_isr
    esp32_store32(esp_bt_osi+92,esp32_callback32(esp_radio_cb_task_create)); // task_create
    esp32_store32(esp_bt_osi+96,esp32_callback32(esp_radio_cb_task_delete)); // task_delete
    esp32_store32(esp_bt_osi+100,esp32_iram_callback32(esp_radio_cb_isr)); // is_in_isr
    esp32_store32(esp_bt_osi+104,esp32_iram_callback32(esp_bt_sw_intr)); // cause_sw_intr_to_core
    esp32_store32(esp_bt_osi+108,esp32_callback32(esp_radio_cb_malloc)); // malloc
    esp32_store32(esp_bt_osi+112,esp32_callback32(esp_radio_cb_malloc)); // malloc_internal
    esp32_store32(esp_bt_osi+116,esp32_callback32(esp_radio_cb_free)); // free
    esp32_store32(esp_bt_osi+120,esp32_callback32(esp_bt_mac)); // read_efuse_mac
    esp32_store32(esp_bt_osi+124,esp32_callback32(esp_bt_srand)); // srand
    esp32_store32(esp_bt_osi+128,esp32_iram_callback32(esp_radio_cb_random)); // rand
    esp32_store32(esp_bt_osi+132,esp32_iram_callback32(esp_bt_cycles_hus)); // btdm_lpcycles_2_hus
    esp32_store32(esp_bt_osi+136,esp32_iram_callback32(esp_bt_hus_cycles)); // btdm_hus_2_lpcycles
    esp32_store32(esp_bt_osi+140,esp32_iram_callback32(esp_bt_awake)); // btdm_sleep_check_duration
    esp32_store32(esp_bt_osi+144,esp32_callback32(esp_bt_sleep_phase)); // btdm_sleep_enter_phase1
    esp32_store32(esp_bt_osi+148,esp32_callback32(esp_bt_sleep_phase)); // btdm_sleep_enter_phase2
    esp32_store32(esp_bt_osi+152,esp32_callback32(esp_bt_sleep_phase)); // btdm_sleep_exit_phase1
    esp32_store32(esp_bt_osi+156,esp32_callback32(esp_bt_sleep_phase)); // btdm_sleep_exit_phase2
    esp32_store32(esp_bt_osi+160,esp32_callback32(esp_bt_sleep_phase)); // btdm_sleep_exit_phase3
    esp32_store32(esp_bt_osi+164,esp32_iram_callback32(esp_bt_no_coex)); // coex_bt_wakeup_request
    esp32_store32(esp_bt_osi+168,esp32_iram_callback32(esp_bt_no_coex)); // coex_bt_wakeup_request_end
    esp32_store32(esp_bt_osi+172,esp32_iram_callback32(esp_bt_no_coex)); // coex_bt_request
    esp32_store32(esp_bt_osi+176,esp32_iram_callback32(esp_bt_no_coex)); // coex_bt_release
    esp32_store32(esp_bt_osi+180,esp32_iram_callback32(esp_bt_no_coex)); // coex_register_bt_cb
    esp32_store32(esp_bt_osi+184,esp32_iram_callback32(esp_bt_no_coex)); // coex_bb_reset_lock
    esp32_store32(esp_bt_osi+188,esp32_iram_callback32(esp_bt_no_coex)); // coex_bb_reset_unlock
    esp32_store32(esp_bt_osi+192,esp32_iram_callback32(esp_bt_no_coex)); // coex_schm_register_btdm_callback
    esp32_store32(esp_bt_osi+196,esp32_iram_callback32(esp_bt_no_coex)); // coex_schm_status_bit_clear
    esp32_store32(esp_bt_osi+200,esp32_iram_callback32(esp_bt_no_coex)); // coex_schm_status_bit_set
    esp32_store32(esp_bt_osi+204,esp32_iram_callback32(esp_bt_no_coex)); // coex_schm_interval_get
    esp32_store32(esp_bt_osi+208,esp32_iram_callback32(esp_bt_no_coex)); // coex_schm_curr_period_get
    esp32_store32(esp_bt_osi+212,esp32_iram_callback32(esp_bt_no_coex)); // coex_schm_curr_phase_get
    esp32_store32(esp_bt_osi+216,esp32_iram_callback32(esp_bt_no_channel)); // coex_wifi_channel_get
    esp32_store32(esp_bt_osi+220,esp32_iram_callback32(esp_bt_no_coex)); // coex_register_wifi_channel_change_callback
    esp32_store32(esp_bt_osi+224,esp32_callback32(esp_bt_set_isr)); // set_isr_l3
    esp32_store32(esp_bt_osi+228,esp32_iram_callback32(esp_bt_disable)); // interrupt_l3_disable
    esp32_store32(esp_bt_osi+232,esp32_iram_callback32(esp_bt_restore)); // interrupt_l3_restore
    esp32_store32(esp_bt_osi+236,esp32_callback32(esp_radio_cb_queue)); // custom_queue_create
    esp32_store32(esp_bt_osi+240,esp32_iram_callback32(esp_bt_no_channel)); // coex_version_get
    esp32_store32(esp_bt_osi+244,esp32_callback32(esp_bt_patch)); // patch_apply
    esp32_store32(esp_bt_osi+248,4208901805); // magic
    esp32_callback32(free);esp32_callback32(malloc);esp32_callback32(calloc);esp32_callback32(realloc);esp32_iram_callback32(phy_enter_critical);esp32_iram_callback32(phy_exit_critical);esp32_iram_callback32(esp_dport_access_reg_read);esp32_callback32(rtc_get_xtal);esp32_callback32(puts);esp32_callback32(__esp_radio_printf);
    return 0;
}
fn esp_bt_controller_setup() {
    if esp_bt_max_connections<1 || esp_bt_max_connections>4 {return -22;}esp32_iram_callback(esp_irq_dispatch);
    let setup=esp_bt_rom_memory();if setup {return setup;}setup=esp_bt_os_init();if setup {return setup;}
    esp32_store32(0x3ff000cc,4294967295);esp32_store32(0x3ff48084,esp32_load32(0x3ff48084)&~(1<<17));esp32_call32(esp32_external("ets_delay_us"),10,0,0,0,0,0,0,0);esp32_store32(0x3ff48088,esp32_load32(0x3ff48088)&~(1<<28));
    let cfg=esp_sdk_calloc(1,48);if !cfg {return -12;}
    // BT_CONTROLLER_INIT_CONFIG_DEFAULT, BLE-only, VHCI and no modem sleep.
    store8(cfg,0);store8(cfg+1,32);store8(cfg+2,23);store8(cfg+3,1);esp32_store32(cfg+4,921600);
    store8(cfg+10,20);store8(cfg+14,232);store8(cfg+15,3);store8(cfg+20,1);store8(cfg+21,esp_bt_max_connections);store8(cfg+26,1);store8(cfg+27,1);store8(cfg+32,7);store8(cfg+39,1);store8(cfg+40,1);esp32_store32(cfg+44,539296536);
    let r=esp32_call32(esp32_external("btdm_osi_funcs_register"),esp_bt_osi,0,0,0,0,0,0,0);if r {esp_sdk_free(cfg);return r;}
    if !esp32_call32(esp32_external("btdm_lpclk_select_src"),0,0,0,0,0,0,0,0) || !esp32_call32(esp32_external("btdm_lpclk_set_div"),79,0,0,0,0,0,0,0) {esp_sdk_free(cfg);return -22;}
    esp32_call32(esp32_external("btdm_controller_set_sleep_mode"),0,0,0,0,0,0,0,0);
    r=esp32_call32(esp32_external("btdm_controller_init"),24,cfg,0,0,0,0,0,0);esp_sdk_free(cfg);if r {return r;}esp_bt_vendor_initialized=1;
    esp_radio_phy_enable();esp_bt_phy_owned=1;esp32_call32(esp32_external("btdm_rf_bb_init_phase2"),0,0,0,0,0,0,0,0);esp32_call32(esp32_external("coex_bt_high_prio"),0,0,0,0,0,0,0,0);
    esp32_call32(esp32_external("btdm_controller_enable"),1,0,0,0,0,0,0,0);
    if esp_bt_transport_init() {return -12;}let callbacks=esp_sdk_calloc(1,8);if !callbacks {return -12;}esp_bt_callbacks=callbacks;
    esp32_store32(callbacks,esp32_iram_callback32(esp_bt_send_ready));esp32_store32(callbacks+4,esp32_callback32(esp_bt_recv));
    return esp32_call32(esp32_external("API_vhci_host_register_callback"),callbacks,0,0,0,0,0,0,0);
}
fn esp_bt_hci_command(opcode,params,size) {
    if opcode<0 || opcode>65535 || size<0 || size>255 || (size && !params) || !esp_bt_tx {return -22;}if esp_bt_cmd_busy {return -16;}
    esp_bt_cmd_busy=1;esp_bt_cmd_opcode=opcode;esp_bt_cmd_size=0;let deadline=esp_sdk_now()+2000000;
    while !esp_bt_cmd_credits || esp_bt_tx_inflight || !esp32_call32(esp32_external("API_vhci_host_check_send_available"),0,0,0,0,0,0,0,0) {if esp_sdk_now()>=deadline {esp_bt_cmd_busy=0;return -110;}esp_sdk_delay(1);}
    let packet=esp_bt_tx;store8(packet,1);store8(packet+1,opcode);store8(packet+2,opcode>>8);store8(packet+3,size);let i=0;while i<size {store8(packet+4+i,load8(params+i));i=i+1;}
    esp_bt_cmd_credits=esp_bt_cmd_credits-1;esp_bt_tx_inflight=1;esp_bt_tx_ready=0;esp32_call32(esp32_external("API_vhci_host_send_packet"),packet,size+4,0,0,0,0,0,0);
    while !esp_bt_cmd_size {if esp_sdk_now()>=deadline {esp_bt_cmd_busy=0;return -110;}esp_sdk_delay(1);}
    let ps=esp32_irq_save();esp_bt_rx_size=esp_bt_cmd_size;i=0;while i<esp_bt_rx_size {store8(esp_bt_rx+i,load8(esp_bt_cmd+i));i=i+1;}esp_bt_cmd_busy=0;esp32_irq_restore(ps);
    if esp_bt_rx_size<7 || load8(esp_bt_rx)!=4 {return -71;}if load8(esp_bt_rx+1)==15 {return load8(esp_bt_rx+3);}return load8(esp_bt_rx+6);
}

fn esp_bt_transport_release() {
    esp_sdk_free(esp_bt_rx);esp_sdk_free(esp_bt_cmd);esp_sdk_free(esp_bt_tx);esp_sdk_free(esp_bt_event_ring);esp_sdk_free(esp_bt_acl_ring);
    esp_bt_rx=0;esp_bt_rx_size=0;esp_bt_tx_ready=0;esp_bt_tx_inflight=0;esp_bt_tx=0;esp_bt_cmd=0;esp_bt_cmd_size=0;esp_bt_cmd_opcode=0;esp_bt_cmd_busy=0;esp_bt_cmd_credits=1;esp_bt_event_ring=0;esp_bt_event_head=0;esp_bt_event_count=0;esp_bt_event_dropped=0;esp_bt_acl_ring=0;esp_bt_acl_head=0;esp_bt_acl_count=0;esp_bt_acl_dropped=0;esp_bt_acl_packet=0;esp_bt_acl_size=0;esp_bt_receive_sequence=0;esp_bt_cmd_sequence=0;esp_bt_event_sequence=0;esp_bt_acl_sequence=0;esp_bt_packet=0;esp_bt_packet_size=0;esp_bt_packet_sequence=0;esp_bt_packet_kind=0;return 0;
}

fn esp_bt_teardown() {
    // The pinned ROM ABI declares deinit void. It stops/deletes the controller
    // task; do not interpret an unspecified return register as an error.
    if esp_bt_vendor_initialized {esp32_call32(esp32_external("btdm_controller_deinit"),0,0,0,0,0,0,0,0);esp_bt_vendor_initialized=0;}
    let deadline=esp_sdk_now()+100000;let r=esp_radio_resources_ready();while r && esp_sdk_now()<deadline {esp_sdk_delay(1);r=esp_radio_resources_ready();}if r {return r;}
    if esp_bt_phy_owned {esp_radio_phy_disable();esp_bt_phy_owned=0;}r=esp_radio_phy_release_buffers();if r {return r;}
    r=esp_radio_resources_end(esp32_iram_callback(esp_bt_irq));if r {return r;}
    esp_bt_transport_release();esp_sdk_free(esp_bt_callbacks);esp_sdk_free(esp_bt_osi);esp_bt_callbacks=0;esp_bt_osi=0;esp_bt_initialized=0;esp_bt_control_task=0;
    esp_bt_irq5=0;esp_bt_arg5=0;esp_bt_irq7=0;esp_bt_arg7=0;esp_bt_irq8=0;esp_bt_arg8=0;esp_bt_critical_depth=0;esp_bt_critical_ps=0;return 0;
}
fn esp_bt_controller_deinit() {
    if esp_bt_lifecycle_busy || esp_bt_host_active || esp_bt_cmd_busy || esp32_load32(esp32_state()+16) || esp_sdk_timer_active || (esp_radio_owner && esp_radio_owner!=2) || (esp_bt_control_task && esp_bt_control_task!=esp_sdk_current) {return -16;}
    if !esp_radio_owner && !esp_bt_osi && !esp_bt_rx {return 0;}esp_bt_lifecycle_busy=1;let r=esp_bt_teardown();esp_bt_lifecycle_busy=0;esp_bt_cleanup_error=r;return r;
}
fn esp_bt_controller_init() {
    // Check before copying/zeroing ROM RAM: a repeated init must never erase
    // an already running controller's data.
    if esp_bt_lifecycle_busy || esp_bt_osi || esp_bt_rx || esp_radio_owner || esp_bt_initialized || esp_bt_host_active {return -16;}
    if !esp_sdk_current {return -19;}if esp32_load32(esp32_state()+16) || esp_sdk_timer_active {return -16;}
    if esp_bt_max_connections<1 || esp_bt_max_connections>4 || esp32_state()!=0x3ffc0000 {return -22;}
    if esp_irq_handler(4) || esp_irq_handler(6) || esp_irq_handler(7) || esp_irq_soft_handler {return -16;}
    esp_bt_lifecycle_busy=1;esp_bt_cleanup_error=0;let r=esp_radio_resources_begin(2);
    if !r {esp_bt_control_task=esp_sdk_current;r=esp_bt_controller_setup();if r {esp_bt_cleanup_error=esp_bt_teardown();}else {esp_bt_initialized=1;}}
    esp_bt_lifecycle_busy=0;return r;
}
