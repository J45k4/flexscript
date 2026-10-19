import "esp32.flex";
import "esp32-irq.flex";
import "esp32-sdk-sync.flex";
import "esp32-sdk-timer.flex";
import "esp32-radio-lifecycle.flex";
import "esp32-radio-os-core.flex";
import "esp32-radio-os-xtensa.flex";
// Pinned esp-wifi-sys 5afc3a38, ESP_WIFI_OS_ADAPTER_VERSION=9, original ESP32.
// Single CPU; optional native NVS table, no light sleep/coexistence.
global esp_radio_irq_count=0;
global esp_radio_isr=0;
global esp_radio_isr_arg=0;

fn esp_radio_irq(source) {if !(esp32_load32(0x3ff000ec)&1) {return 0;}esp_radio_irq_count=esp_radio_irq_count+1;if esp_radio_isr {esp32_call32(esp_radio_isr,esp_radio_isr_arg,0,0,0,0,0,0,0);}return 0;}
fn esp_radio_phy_clock(enable) {let ps=esp32_irq_save();let value=esp32_load32(0x3ff000cc);if enable {esp_radio_phy_clock_refs=esp_radio_phy_clock_refs+1;value=value|0x3c9;}else if esp_radio_phy_clock_refs {esp_radio_phy_clock_refs=esp_radio_phy_clock_refs-1;if !esp_radio_phy_clock_refs {value=value&~0x3c9;}}esp32_store32(0x3ff000cc,value);esp32_irq_restore(ps);return 0;}

fn esp_radio_cb_set_intr(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();if b>=69 {esp32_irq_restore(ps);return esp_radio_fail(2);}let r=esp_radio_irq_claim(b);if r {esp32_irq_restore(ps);return r;}esp32_store32(0x3ff00104+b*4,1);esp32_irq_restore(ps);return 0;
}
fn esp_radio_cb_clear_intr(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();if a<69 {esp32_store32(0x3ff00104+a*4,6);}esp32_irq_restore(ps);return 0;
}
fn esp_radio_cb_set_isr(a,b,c,d,e,f,g,h) {
    if a>1 {return esp_radio_fail(4);}let ps=esp32_irq_save();let handler=esp32_callback(esp_radio_irq);let r=esp_radio_irq_can_claim(0,handler);if r {esp32_irq_restore(ps);return r;}
    r=esp_irq_reserve(!esp_irq_handler(0));if r {esp32_irq_restore(ps);return r;}r=esp_radio_irq_claim(0);if r {esp32_irq_restore(ps);return r;}
    esp_radio_isr=b;esp_radio_isr_arg=c;r=esp_irq_attach(0,handler);esp32_irq_restore(ps);return r;
}
fn esp_radio_cb_ints_on(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();if esp_radio_isr {esp32_store32(0x3ff00104,1);}esp32_irq_mask(esp32_irq_enabled()|2);esp32_irq_restore(ps);return 0;
}
fn esp_radio_cb_ints_off(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();esp32_store32(0x3ff00104,6);esp32_irq_restore(ps);return 0;
}

fn esp_radio_cb_wifi_clock_on(a,b,c,d,e,f,g,h) {esp32_store32(0x3ff000cc,esp32_load32(0x3ff000cc)|0x406);return 0;
}
fn esp_radio_cb_wifi_clock_off(a,b,c,d,e,f,g,h) {esp32_store32(0x3ff000cc,esp32_load32(0x3ff000cc)&~0x406);return 0;
}
fn esp_radio_cb_wifi_reset(a,b,c,d,e,f,g,h) {esp32_store32(0x3ff000d0,esp32_load32(0x3ff000d0)|4);esp32_store32(0x3ff000d0,esp32_load32(0x3ff000d0)&~4);return 0;
}

fn esp_radio_cb_read_mac(a,b,c,d,e,f,g,h) {if !a || b>2 {return -1;}let lo=esp32_load32(0x3ff5a004);let hi=esp32_load32(0x3ff5a008);store8(a,hi>>8);store8(a+1,hi);store8(a+2,lo>>24);store8(a+3,lo>>16);store8(a+4,lo>>8);store8(a+5,lo+b);return 0;
}
fn esp_radio_cb_phy_on(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let r=esp_radio_phy_enable();if !r {esp32_call32(esp32_external("phy_wifi_enable_set"),1,0,0,0,0,0,0,0);}esp32_irq_restore(ps);if r {return esp_radio_fail(0x2001);}return 0;
}
fn esp_radio_cb_phy_off(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();esp32_call32(esp32_external("phy_wifi_enable_set"),0,0,0,0,0,0,0,0);let r=esp_radio_phy_disable();esp32_irq_restore(ps);return r;
}

// Prepare the complete pair before publishing either pointer. A prepared pair
// is not calibrated until the first hardware enable; later wakes reuse it.
fn esp_radio_phy_buffers_init() {
    let ps=esp32_irq_save();if esp_radio_phy_cal && esp_radio_phy_init_data {esp32_irq_restore(ps);return 0;}
    if esp_radio_phy_cal || esp_radio_phy_init_data || esp_radio_phy_refs {esp32_irq_restore(ps);return -16;}
    let cal=esp_sdk_calloc(1,1904);let data=esp_sdk_calloc(1,128);
    if !cal || !data {esp_sdk_free(cal);esp_sdk_free(data);esp32_irq_restore(ps);return -12;}
        store8(data+0,3);
        store8(data+1,3);
        store8(data+2,5);
        store8(data+3,9);
        store8(data+4,6);
        store8(data+5,5);
        store8(data+6,3);
        store8(data+7,6);
        store8(data+8,5);
        store8(data+9,4);
        store8(data+10,6);
        store8(data+11,4);
        store8(data+12,5);
        store8(data+17,5);
        store8(data+18,9);
        store8(data+19,6);
        store8(data+20,5);
        store8(data+21,3);
        store8(data+22,6);
        store8(data+23,5);
        store8(data+32,252);
        store8(data+33,252);
        store8(data+34,254);
        store8(data+35,240);
        store8(data+36,240);
        store8(data+37,240);
        store8(data+38,224);
        store8(data+39,224);
        store8(data+40,224);
        store8(data+41,24);
        store8(data+42,24);
        store8(data+43,24);
        store8(data+44,80);
        store8(data+45,72);
        store8(data+46,66);
        store8(data+47,60);
        store8(data+48,56);
        store8(data+49,52);
        store8(data+51,1);
        store8(data+52,1);
        store8(data+53,2);
        store8(data+54,2);
        store8(data+55,3);
        store8(data+56,4);
        store8(data+57,5);
    esp_radio_phy_cal=cal;esp_radio_phy_init_data=data;esp_radio_phy_calibrated=0;esp32_irq_restore(ps);return 0;
}
// Single-core PHY transitions include the vendor operation: the pinned adapter
// serializes calibration/wakeup/close with its reference-count state as well.
fn esp_radio_phy_enable() {
    let ps=esp32_irq_save();let r=esp_radio_phy_buffers_init();if r {esp32_irq_restore(ps);return r;}
    esp_radio_phy_clock(1);if !esp_radio_phy_refs {
        if !esp_radio_phy_calibrated {
            esp32_call32(esp32_external("phy_init_param_set"),1,0,0,0,0,0,0,0);
            esp_radio_phy_result=esp32_call32(esp32_external("register_chipv7_phy"),esp_radio_phy_init_data,esp_radio_phy_cal,2,0,0,0,0,0);esp_radio_phy_calibrated=1;
        }else {esp32_call32(esp32_external("phy_wakeup_init"),0,0,0,0,0,0,0,0);}
    }esp_radio_phy_refs=esp_radio_phy_refs+1;esp32_irq_restore(ps);return 0;
}

fn esp_radio_os_size() {return 484;}
fn esp_radio_nvs_offset() {return 276;}
fn esp_radio_random_word() {return esp32_load32(0x3ff75144);}
fn esp_radio_os_build(table) {
    esp32_store32(table+0,9); // _version
    esp32_store32(table+4,esp32_callback32(esp_radio_cb_env)); // _env_is_chip
    esp32_store32(table+8,esp32_callback32(esp_radio_cb_set_intr)); // _set_intr
    esp32_store32(table+12,esp32_callback32(esp_radio_cb_clear_intr)); // _clear_intr
    esp32_store32(table+16,esp32_callback32(esp_radio_cb_set_isr)); // _set_isr
    esp32_store32(table+20,esp32_callback32(esp_radio_cb_ints_on)); // _ints_on
    esp32_store32(table+24,esp32_callback32(esp_radio_cb_ints_off)); // _ints_off
    esp32_store32(table+28,esp32_callback32(esp_radio_cb_isr)); // _is_from_isr
    esp32_store32(table+32,esp32_callback32(esp_radio_cb_spin)); // _spin_lock_create
    esp32_store32(table+36,esp32_callback32(esp_radio_cb_free)); // _spin_lock_delete
    esp32_store32(table+40,esp32_callback32(esp_radio_cb_disable)); // _wifi_int_disable
    esp32_store32(table+44,esp32_callback32(esp_radio_cb_restore)); // _wifi_int_restore
    esp32_store32(table+48,esp32_callback32(esp_radio_cb_yield_isr)); // _task_yield_from_isr
    esp32_store32(table+52,esp32_callback32(esp_radio_cb_sem_create)); // _semphr_create
    esp32_store32(table+56,esp32_callback32(esp_radio_cb_free)); // _semphr_delete
    esp32_store32(table+60,esp32_callback32(esp_radio_cb_sem_take)); // _semphr_take
    esp32_store32(table+64,esp32_callback32(esp_radio_cb_sem_give)); // _semphr_give
    esp32_store32(table+68,esp32_callback32(esp_radio_cb_thread_sem)); // _wifi_thread_semphr_get
    esp32_store32(table+72,esp32_callback32(esp_radio_cb_mutex)); // _mutex_create
    esp32_store32(table+76,esp32_callback32(esp_radio_cb_recursive)); // _recursive_mutex_create
    esp32_store32(table+80,esp32_callback32(esp_radio_cb_free)); // _mutex_delete
    esp32_store32(table+84,esp32_callback32(esp_radio_cb_lock)); // _mutex_lock
    esp32_store32(table+88,esp32_callback32(esp_radio_cb_unlock)); // _mutex_unlock
    esp32_store32(table+92,esp32_callback32(esp_radio_cb_queue)); // _queue_create
    esp32_store32(table+96,esp32_callback32(esp_radio_cb_free)); // _queue_delete
    esp32_store32(table+100,esp32_callback32(esp_radio_cb_send)); // _queue_send
    esp32_store32(table+104,esp32_callback32(esp_radio_cb_send_isr)); // _queue_send_from_isr
    esp32_store32(table+108,esp32_callback32(esp_radio_cb_send)); // _queue_send_to_back
    esp32_store32(table+112,esp32_callback32(esp_radio_cb_front)); // _queue_send_to_front
    esp32_store32(table+116,esp32_callback32(esp_radio_cb_recv)); // _queue_recv
    esp32_store32(table+120,esp32_callback32(esp_radio_cb_waiting)); // _queue_msg_waiting
    esp32_store32(table+124,esp32_callback32(esp_radio_cb_event_create)); // _event_group_create
    esp32_store32(table+128,esp32_callback32(esp_radio_cb_free)); // _event_group_delete
    esp32_store32(table+132,esp32_callback32(esp_radio_cb_event_set)); // _event_group_set_bits
    esp32_store32(table+136,esp32_callback32(esp_radio_cb_event_clear)); // _event_group_clear_bits
    esp32_store32(table+140,esp32_callback32(esp_radio_cb_event_wait)); // _event_group_wait_bits
    esp32_store32(table+144,esp32_callback32(esp_radio_cb_task_create)); // _task_create_pinned_to_core
    esp32_store32(table+148,esp32_callback32(esp_radio_cb_task_create_any)); // _task_create
    esp32_store32(table+152,esp32_callback32(esp_radio_cb_task_delete)); // _task_delete
    esp32_store32(table+156,esp32_callback32(esp_radio_cb_delay)); // _task_delay
    esp32_store32(table+160,esp32_callback32(esp_radio_cb_identity)); // _task_ms_to_tick
    esp32_store32(table+164,esp32_callback32(esp_radio_cb_current)); // _task_get_current_task
    esp32_store32(table+168,esp32_callback32(esp_radio_cb_max_priority)); // _task_get_max_priority
    esp32_store32(table+172,esp32_callback32(esp_radio_cb_malloc)); // _malloc
    esp32_store32(table+176,esp32_callback32(esp_radio_cb_free)); // _free
    esp32_store32(table+180,esp32_callback32(esp_radio_cb_event_post)); // _event_post
    esp32_store32(table+184,esp32_callback32(esp_radio_cb_heap)); // _get_free_heap_size
    esp32_store32(table+188,esp32_callback32(esp_radio_cb_random)); // _rand
    esp32_store32(table+192,esp32_callback32(esp_radio_cb_single_core)); // _dport_access_stall_other_cpu_start_wrap
    esp32_store32(table+196,esp32_callback32(esp_radio_cb_single_core)); // _dport_access_stall_other_cpu_end_wrap
    esp32_store32(table+200,esp32_callback32(esp_radio_cb_awake)); // _wifi_pm_sleep_lock_acquire
    esp32_store32(table+204,esp32_callback32(esp_radio_cb_awake)); // _wifi_pm_sleep_lock_release
    esp32_store32(table+208,esp32_callback32(esp_radio_cb_phy_off)); // _phy_disable
    esp32_store32(table+212,esp32_callback32(esp_radio_cb_phy_on)); // _phy_enable
    esp32_store32(table+216,esp32_callback32(esp_radio_cb_phy_clock_on)); // _phy_common_clock_enable
    esp32_store32(table+220,esp32_callback32(esp_radio_cb_phy_clock_off)); // _phy_common_clock_disable
    esp32_store32(table+224,esp32_callback32(esp_radio_cb_unsupported)); // _phy_update_country_info
    esp32_store32(table+228,esp32_callback32(esp_radio_cb_read_mac)); // _read_mac
    esp32_store32(table+232,esp32_callback32(esp_radio_cb_timer_arm)); // _timer_arm
    esp32_store32(table+236,esp32_callback32(esp_radio_cb_timer_disarm)); // _timer_disarm
    esp32_store32(table+240,esp32_callback32(esp_radio_cb_timer_done)); // _timer_done
    esp32_store32(table+244,esp32_callback32(esp_radio_cb_timer_setfn)); // _timer_setfn
    esp32_store32(table+248,esp32_callback32(esp_radio_cb_timer_us)); // _timer_arm_us
    esp32_store32(table+252,esp32_callback32(esp_radio_cb_wifi_reset)); // _wifi_reset_mac
    esp32_store32(table+256,esp32_callback32(esp_radio_cb_wifi_clock_on)); // _wifi_clock_enable
    esp32_store32(table+260,esp32_callback32(esp_radio_cb_wifi_clock_off)); // _wifi_clock_disable
    esp32_store32(table+264,esp32_callback32(esp_radio_cb_unsupported)); // _wifi_rtc_enable_iso
    esp32_store32(table+268,esp32_callback32(esp_radio_cb_unsupported)); // _wifi_rtc_disable_iso
    esp32_store32(table+272,esp32_callback32(esp_radio_cb_time)); // _esp_timer_get_time
    esp32_store32(table+276,esp32_callback32(esp_radio_cb_nvs)); // _nvs_set_i8
    esp32_store32(table+280,esp32_callback32(esp_radio_cb_nvs)); // _nvs_get_i8
    esp32_store32(table+284,esp32_callback32(esp_radio_cb_nvs)); // _nvs_set_u8
    esp32_store32(table+288,esp32_callback32(esp_radio_cb_nvs)); // _nvs_get_u8
    esp32_store32(table+292,esp32_callback32(esp_radio_cb_nvs)); // _nvs_set_u16
    esp32_store32(table+296,esp32_callback32(esp_radio_cb_nvs)); // _nvs_get_u16
    esp32_store32(table+300,esp32_callback32(esp_radio_cb_nvs)); // _nvs_open
    esp32_store32(table+304,esp32_callback32(esp_radio_cb_nvs)); // _nvs_close
    esp32_store32(table+308,esp32_callback32(esp_radio_cb_nvs)); // _nvs_commit
    esp32_store32(table+312,esp32_callback32(esp_radio_cb_nvs)); // _nvs_set_blob
    esp32_store32(table+316,esp32_callback32(esp_radio_cb_nvs)); // _nvs_get_blob
    esp32_store32(table+320,esp32_callback32(esp_radio_cb_nvs)); // _nvs_erase_key
    esp32_store32(table+324,esp32_callback32(esp_radio_cb_get_random)); // _get_random
    esp32_store32(table+328,esp32_callback32(esp_radio_cb_get_time)); // _get_time
    esp32_store32(table+332,esp32_callback32(esp_radio_cb_random)); // _random
    esp32_store32(table+336,0); // _log_write
    esp32_store32(table+340,0); // _log_writev
    esp32_store32(table+344,esp32_callback32(esp_radio_cb_timestamp)); // _log_timestamp
    esp32_store32(table+348,esp32_callback32(esp_radio_cb_malloc)); // _malloc_internal
    esp32_store32(table+352,esp32_callback32(esp_radio_cb_realloc)); // _realloc_internal
    esp32_store32(table+356,esp32_callback32(esp_radio_cb_calloc)); // _calloc_internal
    esp32_store32(table+360,esp32_callback32(esp_radio_cb_zalloc)); // _zalloc_internal
    esp32_store32(table+364,esp32_callback32(esp_radio_cb_malloc)); // _wifi_malloc
    esp32_store32(table+368,esp32_callback32(esp_radio_cb_realloc)); // _wifi_realloc
    esp32_store32(table+372,esp32_callback32(esp_radio_cb_calloc)); // _wifi_calloc
    esp32_store32(table+376,esp32_callback32(esp_radio_cb_zalloc)); // _wifi_zalloc
    esp32_store32(table+380,esp32_callback32(esp_radio_cb_wifi_queue)); // _wifi_create_queue
    esp32_store32(table+384,esp32_callback32(esp_radio_cb_wifi_delete_queue)); // _wifi_delete_queue
    esp32_store32(table+388,esp32_callback32(esp_radio_cb_no_coex)); // _coex_init
    esp32_store32(table+392,esp32_callback32(esp_radio_cb_no_coex)); // _coex_deinit
    esp32_store32(table+396,esp32_callback32(esp_radio_cb_no_coex)); // _coex_enable
    esp32_store32(table+400,esp32_callback32(esp_radio_cb_no_coex)); // _coex_disable
    esp32_store32(table+404,esp32_callback32(esp_radio_cb_no_coex)); // _coex_status_get
    esp32_store32(table+408,0); // _coex_condition_set
    esp32_store32(table+412,esp32_callback32(esp_radio_cb_no_coex)); // _coex_wifi_request
    esp32_store32(table+416,esp32_callback32(esp_radio_cb_no_coex)); // _coex_wifi_release
    esp32_store32(table+420,esp32_callback32(esp_radio_cb_no_coex)); // _coex_wifi_channel_set
    esp32_store32(table+424,esp32_callback32(esp_radio_cb_no_coex)); // _coex_event_duration_get
    esp32_store32(table+428,esp32_callback32(esp_radio_cb_no_coex)); // _coex_pti_get
    esp32_store32(table+432,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_status_bit_clear
    esp32_store32(table+436,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_status_bit_set
    esp32_store32(table+440,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_interval_set
    esp32_store32(table+444,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_interval_get
    esp32_store32(table+448,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_curr_period_get
    esp32_store32(table+452,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_curr_phase_get
    esp32_store32(table+456,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_process_restart
    esp32_store32(table+460,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_register_cb
    esp32_store32(table+464,esp32_callback32(esp_radio_cb_no_coex)); // _coex_register_start_cb
    esp32_store32(table+468,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_flexible_period_set
    esp32_store32(table+472,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_flexible_period_get
    esp32_store32(table+476,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_get_phase_by_idx
    esp32_store32(table+480,3735928495); // _magic
    return 0;
}

// Single-core event publication and its bounded, nonblocking hook are one
// transaction. Nested posts restore the outer borrowed payload view; counters,
// last-event and scan state retain the most recently published event.

// Controller must be quiescent before dropping its final native PHY guard.
fn esp_radio_phy_disable() {
    let ps=esp32_irq_save();if esp_radio_phy_refs {esp_radio_phy_refs=esp_radio_phy_refs-1;if !esp_radio_phy_refs {esp32_call32(esp32_external("phy_close_rf"),0,0,0,0,0,0,0,0);}esp_radio_phy_clock(0);}esp32_irq_restore(ps);return 0;
}
fn esp_radio_phy_release_buffers() {
    let ps=esp32_irq_save();if esp_radio_phy_refs || esp_radio_phy_clock_refs {esp32_irq_restore(ps);return -16;}esp_sdk_free(esp_radio_phy_cal);esp_sdk_free(esp_radio_phy_init_data);esp_radio_phy_cal=0;esp_radio_phy_init_data=0;esp_radio_phy_calibrated=0;esp32_irq_restore(ps);return 0;
}
