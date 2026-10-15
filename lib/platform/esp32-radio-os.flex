import "esp32.flex";
import "esp32-irq.flex";
import "esp32-sdk-sync.flex";
import "esp32-sdk-timer.flex";
import "esp32-radio-lifecycle.flex";
// Pinned esp-wifi-sys 5afc3a38, ESP_WIFI_OS_ADAPTER_VERSION=9, original ESP32.
// Single CPU; optional native NVS table, no light sleep/coexistence.
global esp_radio_osi=0;
global esp_radio_nvs_table=0;
global esp_radio_events=0;
global esp_radio_scan_done=0;
global esp_radio_scan_status= -1;
global esp_radio_last_event=0;
global esp_radio_phy_refs=0;
global esp_radio_phy_cal=0;
global esp_radio_phy_init_data=0;
global esp_radio_phy_result=0;
global esp_radio_phy_clock_refs=0;
global esp_radio_irq_count=0;
global esp_radio_isr=0;
global esp_radio_isr_arg=0;
global esp_radio_callback_fault=0;
global esp_radio_log=0;
global esp_radio_event_hook=0;
global esp_radio_event_data=0;
global esp_radio_event_size=0;
fn esp_radio_fail(code) {esp_radio_callback_fault=code;esp_uart_write("RADIO callback unsupported ");esp_uart_hex(code);esp_uart_write("\r\n");while 1 {}return 0;}
fn esp_radio_irq(source) {if !(esp32_load32(0x3ff000ec)&1) {return 0;}esp_radio_irq_count=esp_radio_irq_count+1;if esp_radio_isr {esp32_call32(esp_radio_isr,esp_radio_isr_arg,0,0,0,0,0,0,0);}return 0;}
fn esp_radio_phy_clock(enable) {let ps=esp32_irq_save();let value=esp32_load32(0x3ff000cc);if enable {esp_radio_phy_clock_refs=esp_radio_phy_clock_refs+1;value=value|0x3c9;}else if esp_radio_phy_clock_refs {esp_radio_phy_clock_refs=esp_radio_phy_clock_refs-1;if !esp_radio_phy_clock_refs {value=value&~0x3c9;}}esp32_store32(0x3ff000cc,value);esp32_irq_restore(ps);return 0;}
fn esp_radio_cb_env(a,b,c,d,e,f,g,h) {return 1;
}
fn esp_radio_cb_set_intr(a,b,c,d,e,f,g,h) {if b>=69 {return esp_radio_fail(2);}let r=esp_radio_irq_claim(b);if r {return r;}esp32_store32(0x3ff00104+b*4,1);return 0;
}
fn esp_radio_cb_clear_intr(a,b,c,d,e,f,g,h) {if a<69 {esp32_store32(0x3ff00104+a*4,6);}return 0;
}
fn esp_radio_cb_set_isr(a,b,c,d,e,f,g,h) {if a>1 {return esp_radio_fail(4);}let r=esp_radio_irq_claim(0);if r {return r;}esp_radio_isr=b;esp_radio_isr_arg=c;return esp_irq_attach(0,esp32_callback(esp_radio_irq));
}
fn esp_radio_cb_ints_on(a,b,c,d,e,f,g,h) {if esp_radio_isr {esp32_store32(0x3ff00104,1);}esp32_irq_mask(esp32_irq_enabled()|2);return 0;
}
fn esp_radio_cb_ints_off(a,b,c,d,e,f,g,h) {esp32_store32(0x3ff00104,6);return 0;
}
fn esp_radio_cb_isr(a,b,c,d,e,f,g,h) {return esp32_load32(esp32_state()+16)!=0;
}
fn esp_radio_cb_spin(a,b,c,d,e,f,g,h) {return esp_radio_owned(esp_sdk_calloc(1,16));
}
fn esp_radio_cb_free(a,b,c,d,e,f,g,h) {let t=esp_sdk_tasks;while a && t {if load64(t+568)==a {store64(t+568,0);}t=load64(t+536);if t==esp_sdk_tasks {t=0;}}return esp_sdk_free(a);
}
fn esp_radio_cb_disable(a,b,c,d,e,f,g,h) {return esp32_irq_save();
}
fn esp_radio_cb_restore(a,b,c,d,e,f,g,h) {esp32_irq_restore(b);return 0;
}
fn esp_radio_cb_yield_isr(a,b,c,d,e,f,g,h) {return 0; // Cooperative wakeups are observed by the next scheduler yield.
}
fn esp_radio_cb_sem_create(a,b,c,d,e,f,g,h) {return esp_radio_owned(esp_sdk_sem_create(a,b));
}
fn esp_radio_cb_sem_take(a,b,c,d,e,f,g,h) {return esp_sdk_sem_take(a,b);
}
fn esp_radio_cb_sem_give(a,b,c,d,e,f,g,h) {return esp_sdk_sem_give(a);
}
fn esp_radio_cb_thread_sem(a,b,c,d,e,f,g,h) {let p=esp_sdk_current+568;let s=load64(p);if !s {s=esp_radio_owned(esp_sdk_sem_create(1,0));store64(p,s);}return s;
}
fn esp_radio_cb_mutex(a,b,c,d,e,f,g,h) {return esp_radio_owned(esp_sdk_mutex_create(0));
}
fn esp_radio_cb_recursive(a,b,c,d,e,f,g,h) {return esp_radio_owned(esp_sdk_mutex_create(1));
}
fn esp_radio_cb_lock(a,b,c,d,e,f,g,h) {return esp_sdk_mutex_lock(a);
}
fn esp_radio_cb_unlock(a,b,c,d,e,f,g,h) {return esp_sdk_mutex_unlock(a);
}
fn esp_radio_cb_queue(a,b,c,d,e,f,g,h) {return esp_radio_owned(esp_sdk_queue_create(a,b));
}
fn esp_radio_cb_send(a,b,c,d,e,f,g,h) {return esp_sdk_queue_op(a,b,c,1);
}
fn esp_radio_cb_send_isr(a,b,c,d,e,f,g,h) {if c {store8(c,0);}return esp_sdk_queue_op(a,b,0,1);
}
fn esp_radio_cb_front(a,b,c,d,e,f,g,h) {return esp_sdk_queue_op(a,b,c,2);
}
fn esp_radio_cb_recv(a,b,c,d,e,f,g,h) {return esp_sdk_queue_op(a,b,c,0);
}
fn esp_radio_cb_waiting(a,b,c,d,e,f,g,h) {if !a {return 0;}return load64(a+24);
}
fn esp_radio_cb_event_create(a,b,c,d,e,f,g,h) {return esp_radio_owned(esp_sdk_event_create());
}
fn esp_radio_cb_event_set(a,b,c,d,e,f,g,h) {return esp_sdk_event_set(a,b);
}
fn esp_radio_cb_event_clear(a,b,c,d,e,f,g,h) {return esp_sdk_event_clear(a,b);
}
fn esp_radio_cb_event_wait(a,b,c,d,e,f,g,h) {return esp_sdk_event_wait(a,b,c,d,e);
}
fn esp_radio_cb_task_create(a,b,c,d,e,f,g,h) {if g!=0 && g!=4294967295 {return 0;}let bytes=c;if bytes<8192 {bytes=8192;}let t=esp_radio_task_owned(esp_sdk_task_create(a,d,bytes,e));if f {esp32_store32(f,t);}return t!=0;
}
fn esp_radio_cb_task_create_any(a,b,c,d,e,f,g,h) {let bytes=c;if bytes<8192 {bytes=8192;}let t=esp_radio_task_owned(esp_sdk_task_create(a,d,bytes,e));if f {esp32_store32(f,t);}return t!=0;
}
fn esp_radio_cb_task_delete(a,b,c,d,e,f,g,h) {return esp_sdk_task_delete(a);
}
fn esp_radio_cb_delay(a,b,c,d,e,f,g,h) {return esp_sdk_delay(a);
}
fn esp_radio_cb_identity(a,b,c,d,e,f,g,h) {return a;
}
fn esp_radio_cb_current(a,b,c,d,e,f,g,h) {return esp_sdk_current;
}
fn esp_radio_cb_max_priority(a,b,c,d,e,f,g,h) {return 25;
}
fn esp_radio_cb_malloc(a,b,c,d,e,f,g,h) {return esp_radio_owned(esp_sdk_malloc(a));
}
fn esp_radio_cb_calloc(a,b,c,d,e,f,g,h) {return esp_radio_owned(esp_sdk_calloc(a,b));
}
fn esp_radio_cb_zalloc(a,b,c,d,e,f,g,h) {return esp_radio_owned(esp_sdk_calloc(1,a));
}
fn esp_radio_cb_realloc(a,b,c,d,e,f,g,h) {return esp_radio_owned(esp_sdk_realloc(a,b));
}
fn esp_radio_cb_heap(a,b,c,d,e,f,g,h) {return esp_sdk_heap_free();
}
fn esp_radio_cb_event_post(a,b,c,d,e,f,g,h) {return esp_radio_dispatch_event(b,c,d);
}
fn esp_radio_cb_random(a,b,c,d,e,f,g,h) {return esp32_load32(0x3ff75144);
}
fn esp_radio_cb_get_random(a,b,c,d,e,f,g,h) {let i=0;while i<b {let n=esp32_load32(0x3ff75144);let j=0;while j<4 && i<b {store8(a+i,n>>(j*8));i=i+1;j=j+1;}}return 0;
}
fn esp_radio_cb_time(a,b,c,d,e,f,g,h) {return esp_sdk_now();
}
fn esp_radio_cb_timestamp(a,b,c,d,e,f,g,h) {return esp_sdk_now()/1000;
}
fn esp_radio_cb_get_time(a,b,c,d,e,f,g,h) {let now=esp_sdk_now();store64(a,now/1000000);esp32_store32(a+8,now%1000000);return 0;
}
fn esp_radio_cb_single_core(a,b,c,d,e,f,g,h) {return 0; // CPU1 remains stalled; no remote DPORT synchronization needed.
}
fn esp_radio_cb_awake(a,b,c,d,e,f,g,h) {return 0; // Modem/light sleep disabled; clocks remain awake.
}
fn esp_radio_cb_nvs(a,b,c,d,e,f,g,h) {return 0x1102; // ESP_ERR_NVS_NOT_FOUND; persistent storage is disabled.
}
fn esp_radio_cb_no_coex(a,b,c,d,e,f,g,h) {return 0; // No second radio active in the standalone Wi-Fi image.
}
fn esp_radio_cb_unsupported(a,b,c,d,e,f,g,h) {return 0x106; // ESP_ERR_NOT_SUPPORTED: coexistence and power-saving not configured.
}
fn esp_radio_cb_phy_clock_on(a,b,c,d,e,f,g,h) {return esp_radio_phy_clock(1);
}
fn esp_radio_cb_phy_clock_off(a,b,c,d,e,f,g,h) {return esp_radio_phy_clock(0);
}
fn esp_radio_cb_wifi_clock_on(a,b,c,d,e,f,g,h) {esp32_store32(0x3ff000cc,esp32_load32(0x3ff000cc)|0x406);return 0;
}
fn esp_radio_cb_wifi_clock_off(a,b,c,d,e,f,g,h) {esp32_store32(0x3ff000cc,esp32_load32(0x3ff000cc)&~0x406);return 0;
}
fn esp_radio_cb_wifi_reset(a,b,c,d,e,f,g,h) {esp32_store32(0x3ff000d0,esp32_load32(0x3ff000d0)|4);esp32_store32(0x3ff000d0,esp32_load32(0x3ff000d0)&~4);return 0;
}
fn esp_radio_cb_timer_setfn(a,b,c,d,e,f,g,h) {let t=esp_sdk_timer_find(a);if t && esp_radio_owner && esp_sdk_heap_owner(t)!=esp_radio_owner {return -16;}let r=esp_sdk_timer_setfn(a,b,c);if !r {esp_radio_owned(esp_sdk_timer_find(a));}return r;
}
fn esp_radio_cb_timer_disarm(a,b,c,d,e,f,g,h) {return esp_sdk_timer_disarm(a);
}
fn esp_radio_cb_timer_done(a,b,c,d,e,f,g,h) {return esp_sdk_timer_done(a);
}
fn esp_radio_cb_timer_arm(a,b,c,d,e,f,g,h) {return esp_sdk_timer_arm(a,b*1000,c);
}
fn esp_radio_cb_timer_us(a,b,c,d,e,f,g,h) {return esp_sdk_timer_arm(a,b,c);
}
fn esp_radio_cb_read_mac(a,b,c,d,e,f,g,h) {if !a || b>2 {return -1;}let lo=esp32_load32(0x3ff5a004);let hi=esp32_load32(0x3ff5a008);store8(a,hi>>8);store8(a+1,hi);store8(a+2,lo>>24);store8(a+3,lo>>16);store8(a+4,lo>>8);store8(a+5,lo+b);return 0;
}
fn esp_radio_cb_phy_on(a,b,c,d,e,f,g,h) {esp_radio_phy_enable();esp32_call32(esp32_external("phy_wifi_enable_set"),1,0,0,0,0,0,0,0);return 0;
}
fn esp_radio_cb_phy_off(a,b,c,d,e,f,g,h) {esp32_call32(esp32_external("phy_wifi_enable_set"),0,0,0,0,0,0,0,0);if esp_radio_phy_refs {esp_radio_phy_refs=esp_radio_phy_refs-1;if !esp_radio_phy_refs {esp32_call32(esp32_external("phy_close_rf"),0,0,0,0,0,0,0,0);}esp_radio_phy_clock(0);}return 0;
}
fn free(a,b,c,d,e,f,g,h) {return esp_sdk_free(a);
}
fn malloc(a,b,c,d,e,f,g,h) {return esp_sdk_malloc(a);
}
fn calloc(a,b,c,d,e,f,g,h) {return esp_sdk_calloc(a,b);
}
fn realloc(a,b,c,d,e,f,g,h) {return esp_sdk_realloc(a,b);
}
fn phy_enter_critical(a,b,c,d,e,f,g,h) {return esp32_irq_save();
}
fn phy_exit_critical(a,b,c,d,e,f,g,h) {esp32_irq_restore(a);return 0;
}
fn esp_dport_access_reg_read(a,b,c,d,e,f,g,h) {return esp32_load32(a);
}
fn rtc_get_xtal(a,b,c,d,e,f,g,h) {return 40;
}
fn puts(a,b,c,d,e,f,g,h) {esp_uart_write(a);esp_uart_write("\r\n");return 0;
}
fn __esp_radio_printf(a,b,c,d,e,f,g,h) {if esp_radio_log && b {esp_uart_write(b);esp_uart_write("\r\n");}return 0;
}
fn vTaskDelay(a,b,c,d,e,f,g,h) {return esp_sdk_delay(a);
}
fn esp_event_post(a,b,c,d,e,f,g,h) {return esp_radio_dispatch_event(b,c,d);
}
fn gettimeofday(a,b,c,d,e,f,g,h) {let now=esp_sdk_now();store64(a,now/1000000);esp32_store32(a+8,now%1000000);return 0;
}
fn esp_fill_random(a,b,c,d,e,f,g,h) {let i=0;while i<b {let n=esp32_load32(0x3ff75144);let j=0;while j<4 && i<b {store8(a+i,n>>(j*8));i=i+1;j=j+1;}}return 0;
}
fn sleep(a,b,c,d,e,f,g,h) {esp_sdk_delay(a*1000);return 0;
}
fn usleep(a,b,c,d,e,f,g,h) {esp_sdk_delay((a+999)/1000);return 0;
}
fn __assert_func(a,b,c,d,e,f,g,h) {esp_uart_write("Vendor assertion ");esp_uart_write(a);esp_uart_hex(b);esp_uart_write(d);return esp_radio_fail(0x4000);
}
fn esp_radio_phy_enable() {
    esp_radio_phy_clock(1);if !esp_radio_phy_refs {
        if !esp_radio_phy_cal {esp_radio_phy_cal=esp_sdk_calloc(1,1904);if !esp_radio_phy_cal {return esp_radio_fail(0x2001);}let data=esp_sdk_calloc(1,128);esp_radio_phy_init_data=data;if !data {return esp_radio_fail(0x2002);}
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
        esp32_call32(esp32_external("phy_init_param_set"),1,0,0,0,0,0,0,0);esp_radio_phy_result=esp32_call32(esp32_external("register_chipv7_phy"),data,esp_radio_phy_cal,2,0,0,0,0,0);
        }else {esp32_call32(esp32_external("phy_wakeup_init"),0,0,0,0,0,0,0,0);}
    }esp_radio_phy_refs=esp_radio_phy_refs+1;return 0;
}
fn esp_radio_cb_wifi_queue(a,b,c,d,e,f,g,h) {let q=esp_radio_owned(esp_sdk_queue_create(a,b));if !q {return 0;}let p=esp_radio_owned(esp_sdk_calloc(1,4));if !p {esp_sdk_free(q);return 0;}esp32_store32(p,q);return p;}
fn esp_radio_cb_wifi_delete_queue(a,b,c,d,e,f,g,h) {if a {esp_sdk_free(esp32_load32(a));esp_sdk_free(a);}return 0;}
fn esp_radio_nvs_apply() {if esp_radio_osi && esp_radio_nvs_table {let i=0;while i<12 {esp32_store32(esp_radio_osi+276+i*4,esp32_load32(esp_radio_nvs_table+i*4));i=i+1;}}return 0;}
fn esp_radio_os_init() {
    if esp_radio_osi {return -16;}if !esp_radio_owner {let r=esp_radio_resources_begin(1);if r {return r;}}if esp_radio_owner!=1 {return -16;}esp_radio_osi=esp32_external("g_wifi_osi_funcs");
    esp32_store32(esp_radio_osi+0,9); // _version
    esp32_store32(esp_radio_osi+4,esp32_callback32(esp_radio_cb_env)); // _env_is_chip
    esp32_store32(esp_radio_osi+8,esp32_callback32(esp_radio_cb_set_intr)); // _set_intr
    esp32_store32(esp_radio_osi+12,esp32_callback32(esp_radio_cb_clear_intr)); // _clear_intr
    esp32_store32(esp_radio_osi+16,esp32_callback32(esp_radio_cb_set_isr)); // _set_isr
    esp32_store32(esp_radio_osi+20,esp32_callback32(esp_radio_cb_ints_on)); // _ints_on
    esp32_store32(esp_radio_osi+24,esp32_callback32(esp_radio_cb_ints_off)); // _ints_off
    esp32_store32(esp_radio_osi+28,esp32_callback32(esp_radio_cb_isr)); // _is_from_isr
    esp32_store32(esp_radio_osi+32,esp32_callback32(esp_radio_cb_spin)); // _spin_lock_create
    esp32_store32(esp_radio_osi+36,esp32_callback32(esp_radio_cb_free)); // _spin_lock_delete
    esp32_store32(esp_radio_osi+40,esp32_callback32(esp_radio_cb_disable)); // _wifi_int_disable
    esp32_store32(esp_radio_osi+44,esp32_callback32(esp_radio_cb_restore)); // _wifi_int_restore
    esp32_store32(esp_radio_osi+48,esp32_callback32(esp_radio_cb_yield_isr)); // _task_yield_from_isr
    esp32_store32(esp_radio_osi+52,esp32_callback32(esp_radio_cb_sem_create)); // _semphr_create
    esp32_store32(esp_radio_osi+56,esp32_callback32(esp_radio_cb_free)); // _semphr_delete
    esp32_store32(esp_radio_osi+60,esp32_callback32(esp_radio_cb_sem_take)); // _semphr_take
    esp32_store32(esp_radio_osi+64,esp32_callback32(esp_radio_cb_sem_give)); // _semphr_give
    esp32_store32(esp_radio_osi+68,esp32_callback32(esp_radio_cb_thread_sem)); // _wifi_thread_semphr_get
    esp32_store32(esp_radio_osi+72,esp32_callback32(esp_radio_cb_mutex)); // _mutex_create
    esp32_store32(esp_radio_osi+76,esp32_callback32(esp_radio_cb_recursive)); // _recursive_mutex_create
    esp32_store32(esp_radio_osi+80,esp32_callback32(esp_radio_cb_free)); // _mutex_delete
    esp32_store32(esp_radio_osi+84,esp32_callback32(esp_radio_cb_lock)); // _mutex_lock
    esp32_store32(esp_radio_osi+88,esp32_callback32(esp_radio_cb_unlock)); // _mutex_unlock
    esp32_store32(esp_radio_osi+92,esp32_callback32(esp_radio_cb_queue)); // _queue_create
    esp32_store32(esp_radio_osi+96,esp32_callback32(esp_radio_cb_free)); // _queue_delete
    esp32_store32(esp_radio_osi+100,esp32_callback32(esp_radio_cb_send)); // _queue_send
    esp32_store32(esp_radio_osi+104,esp32_callback32(esp_radio_cb_send_isr)); // _queue_send_from_isr
    esp32_store32(esp_radio_osi+108,esp32_callback32(esp_radio_cb_send)); // _queue_send_to_back
    esp32_store32(esp_radio_osi+112,esp32_callback32(esp_radio_cb_front)); // _queue_send_to_front
    esp32_store32(esp_radio_osi+116,esp32_callback32(esp_radio_cb_recv)); // _queue_recv
    esp32_store32(esp_radio_osi+120,esp32_callback32(esp_radio_cb_waiting)); // _queue_msg_waiting
    esp32_store32(esp_radio_osi+124,esp32_callback32(esp_radio_cb_event_create)); // _event_group_create
    esp32_store32(esp_radio_osi+128,esp32_callback32(esp_radio_cb_free)); // _event_group_delete
    esp32_store32(esp_radio_osi+132,esp32_callback32(esp_radio_cb_event_set)); // _event_group_set_bits
    esp32_store32(esp_radio_osi+136,esp32_callback32(esp_radio_cb_event_clear)); // _event_group_clear_bits
    esp32_store32(esp_radio_osi+140,esp32_callback32(esp_radio_cb_event_wait)); // _event_group_wait_bits
    esp32_store32(esp_radio_osi+144,esp32_callback32(esp_radio_cb_task_create)); // _task_create_pinned_to_core
    esp32_store32(esp_radio_osi+148,esp32_callback32(esp_radio_cb_task_create_any)); // _task_create
    esp32_store32(esp_radio_osi+152,esp32_callback32(esp_radio_cb_task_delete)); // _task_delete
    esp32_store32(esp_radio_osi+156,esp32_callback32(esp_radio_cb_delay)); // _task_delay
    esp32_store32(esp_radio_osi+160,esp32_callback32(esp_radio_cb_identity)); // _task_ms_to_tick
    esp32_store32(esp_radio_osi+164,esp32_callback32(esp_radio_cb_current)); // _task_get_current_task
    esp32_store32(esp_radio_osi+168,esp32_callback32(esp_radio_cb_max_priority)); // _task_get_max_priority
    esp32_store32(esp_radio_osi+172,esp32_callback32(esp_radio_cb_malloc)); // _malloc
    esp32_store32(esp_radio_osi+176,esp32_callback32(esp_radio_cb_free)); // _free
    esp32_store32(esp_radio_osi+180,esp32_callback32(esp_radio_cb_event_post)); // _event_post
    esp32_store32(esp_radio_osi+184,esp32_callback32(esp_radio_cb_heap)); // _get_free_heap_size
    esp32_store32(esp_radio_osi+188,esp32_callback32(esp_radio_cb_random)); // _rand
    esp32_store32(esp_radio_osi+192,esp32_callback32(esp_radio_cb_single_core)); // _dport_access_stall_other_cpu_start_wrap
    esp32_store32(esp_radio_osi+196,esp32_callback32(esp_radio_cb_single_core)); // _dport_access_stall_other_cpu_end_wrap
    esp32_store32(esp_radio_osi+200,esp32_callback32(esp_radio_cb_awake)); // _wifi_pm_sleep_lock_acquire
    esp32_store32(esp_radio_osi+204,esp32_callback32(esp_radio_cb_awake)); // _wifi_pm_sleep_lock_release
    esp32_store32(esp_radio_osi+208,esp32_callback32(esp_radio_cb_phy_off)); // _phy_disable
    esp32_store32(esp_radio_osi+212,esp32_callback32(esp_radio_cb_phy_on)); // _phy_enable
    esp32_store32(esp_radio_osi+216,esp32_callback32(esp_radio_cb_phy_clock_on)); // _phy_common_clock_enable
    esp32_store32(esp_radio_osi+220,esp32_callback32(esp_radio_cb_phy_clock_off)); // _phy_common_clock_disable
    esp32_store32(esp_radio_osi+224,esp32_callback32(esp_radio_cb_unsupported)); // _phy_update_country_info
    esp32_store32(esp_radio_osi+228,esp32_callback32(esp_radio_cb_read_mac)); // _read_mac
    esp32_store32(esp_radio_osi+232,esp32_callback32(esp_radio_cb_timer_arm)); // _timer_arm
    esp32_store32(esp_radio_osi+236,esp32_callback32(esp_radio_cb_timer_disarm)); // _timer_disarm
    esp32_store32(esp_radio_osi+240,esp32_callback32(esp_radio_cb_timer_done)); // _timer_done
    esp32_store32(esp_radio_osi+244,esp32_callback32(esp_radio_cb_timer_setfn)); // _timer_setfn
    esp32_store32(esp_radio_osi+248,esp32_callback32(esp_radio_cb_timer_us)); // _timer_arm_us
    esp32_store32(esp_radio_osi+252,esp32_callback32(esp_radio_cb_wifi_reset)); // _wifi_reset_mac
    esp32_store32(esp_radio_osi+256,esp32_callback32(esp_radio_cb_wifi_clock_on)); // _wifi_clock_enable
    esp32_store32(esp_radio_osi+260,esp32_callback32(esp_radio_cb_wifi_clock_off)); // _wifi_clock_disable
    esp32_store32(esp_radio_osi+264,esp32_callback32(esp_radio_cb_unsupported)); // _wifi_rtc_enable_iso
    esp32_store32(esp_radio_osi+268,esp32_callback32(esp_radio_cb_unsupported)); // _wifi_rtc_disable_iso
    esp32_store32(esp_radio_osi+272,esp32_callback32(esp_radio_cb_time)); // _esp_timer_get_time
    esp32_store32(esp_radio_osi+276,esp32_callback32(esp_radio_cb_nvs)); // _nvs_set_i8
    esp32_store32(esp_radio_osi+280,esp32_callback32(esp_radio_cb_nvs)); // _nvs_get_i8
    esp32_store32(esp_radio_osi+284,esp32_callback32(esp_radio_cb_nvs)); // _nvs_set_u8
    esp32_store32(esp_radio_osi+288,esp32_callback32(esp_radio_cb_nvs)); // _nvs_get_u8
    esp32_store32(esp_radio_osi+292,esp32_callback32(esp_radio_cb_nvs)); // _nvs_set_u16
    esp32_store32(esp_radio_osi+296,esp32_callback32(esp_radio_cb_nvs)); // _nvs_get_u16
    esp32_store32(esp_radio_osi+300,esp32_callback32(esp_radio_cb_nvs)); // _nvs_open
    esp32_store32(esp_radio_osi+304,esp32_callback32(esp_radio_cb_nvs)); // _nvs_close
    esp32_store32(esp_radio_osi+308,esp32_callback32(esp_radio_cb_nvs)); // _nvs_commit
    esp32_store32(esp_radio_osi+312,esp32_callback32(esp_radio_cb_nvs)); // _nvs_set_blob
    esp32_store32(esp_radio_osi+316,esp32_callback32(esp_radio_cb_nvs)); // _nvs_get_blob
    esp32_store32(esp_radio_osi+320,esp32_callback32(esp_radio_cb_nvs)); // _nvs_erase_key
    esp_radio_nvs_apply();
    esp32_store32(esp_radio_osi+324,esp32_callback32(esp_radio_cb_get_random)); // _get_random
    esp32_store32(esp_radio_osi+328,esp32_callback32(esp_radio_cb_get_time)); // _get_time
    esp32_store32(esp_radio_osi+332,esp32_callback32(esp_radio_cb_random)); // _random
    esp32_store32(esp_radio_osi+336,0); // _log_write
    esp32_store32(esp_radio_osi+340,0); // _log_writev
    esp32_store32(esp_radio_osi+344,esp32_callback32(esp_radio_cb_timestamp)); // _log_timestamp
    esp32_store32(esp_radio_osi+348,esp32_callback32(esp_radio_cb_malloc)); // _malloc_internal
    esp32_store32(esp_radio_osi+352,esp32_callback32(esp_radio_cb_realloc)); // _realloc_internal
    esp32_store32(esp_radio_osi+356,esp32_callback32(esp_radio_cb_calloc)); // _calloc_internal
    esp32_store32(esp_radio_osi+360,esp32_callback32(esp_radio_cb_zalloc)); // _zalloc_internal
    esp32_store32(esp_radio_osi+364,esp32_callback32(esp_radio_cb_malloc)); // _wifi_malloc
    esp32_store32(esp_radio_osi+368,esp32_callback32(esp_radio_cb_realloc)); // _wifi_realloc
    esp32_store32(esp_radio_osi+372,esp32_callback32(esp_radio_cb_calloc)); // _wifi_calloc
    esp32_store32(esp_radio_osi+376,esp32_callback32(esp_radio_cb_zalloc)); // _wifi_zalloc
    esp32_store32(esp_radio_osi+380,esp32_callback32(esp_radio_cb_wifi_queue)); // _wifi_create_queue
    esp32_store32(esp_radio_osi+384,esp32_callback32(esp_radio_cb_wifi_delete_queue)); // _wifi_delete_queue
    esp32_store32(esp_radio_osi+388,esp32_callback32(esp_radio_cb_no_coex)); // _coex_init
    esp32_store32(esp_radio_osi+392,esp32_callback32(esp_radio_cb_no_coex)); // _coex_deinit
    esp32_store32(esp_radio_osi+396,esp32_callback32(esp_radio_cb_no_coex)); // _coex_enable
    esp32_store32(esp_radio_osi+400,esp32_callback32(esp_radio_cb_no_coex)); // _coex_disable
    esp32_store32(esp_radio_osi+404,esp32_callback32(esp_radio_cb_no_coex)); // _coex_status_get
    esp32_store32(esp_radio_osi+408,0); // _coex_condition_set
    esp32_store32(esp_radio_osi+412,esp32_callback32(esp_radio_cb_no_coex)); // _coex_wifi_request
    esp32_store32(esp_radio_osi+416,esp32_callback32(esp_radio_cb_no_coex)); // _coex_wifi_release
    esp32_store32(esp_radio_osi+420,esp32_callback32(esp_radio_cb_no_coex)); // _coex_wifi_channel_set
    esp32_store32(esp_radio_osi+424,esp32_callback32(esp_radio_cb_no_coex)); // _coex_event_duration_get
    esp32_store32(esp_radio_osi+428,esp32_callback32(esp_radio_cb_no_coex)); // _coex_pti_get
    esp32_store32(esp_radio_osi+432,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_status_bit_clear
    esp32_store32(esp_radio_osi+436,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_status_bit_set
    esp32_store32(esp_radio_osi+440,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_interval_set
    esp32_store32(esp_radio_osi+444,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_interval_get
    esp32_store32(esp_radio_osi+448,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_curr_period_get
    esp32_store32(esp_radio_osi+452,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_curr_phase_get
    esp32_store32(esp_radio_osi+456,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_process_restart
    esp32_store32(esp_radio_osi+460,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_register_cb
    esp32_store32(esp_radio_osi+464,esp32_callback32(esp_radio_cb_no_coex)); // _coex_register_start_cb
    esp32_store32(esp_radio_osi+468,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_flexible_period_set
    esp32_store32(esp_radio_osi+472,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_flexible_period_get
    esp32_store32(esp_radio_osi+476,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_get_phase_by_idx
    esp32_store32(esp_radio_osi+480,3735928495); // _magic
    esp32_callback32(free);
    esp32_callback32(malloc);
    esp32_callback32(calloc);
    esp32_callback32(realloc);
    esp32_callback32(phy_enter_critical);
    esp32_callback32(phy_exit_critical);
    esp32_callback32(esp_dport_access_reg_read);
    esp32_callback32(rtc_get_xtal);
    esp32_callback32(puts);
    esp32_callback32(__esp_radio_printf);
    esp32_callback32(vTaskDelay);
    esp32_callback32(esp_event_post);
    esp32_callback32(gettimeofday);
    esp32_callback32(esp_fill_random);
    esp32_callback32(sleep);
    esp32_callback32(usleep);
    esp32_callback32(__assert_func);
    if esp_sdk_timer_task {return 0;}let r=esp_sdk_timer_init();if !r {esp_radio_timer_created=1;}return r;
}

// Hook data is valid only during this bounded, nonblocking callback.
fn esp_radio_dispatch_event(id,data,size) {
    esp_radio_last_event=id;esp_radio_events=esp_radio_events+1;if id==1 {esp_radio_scan_status= -1;if data && size>=6 {esp_radio_scan_status=esp32_load32(data);}esp_radio_scan_done=1;}
    if esp_radio_event_hook {let ps=esp32_irq_save();esp_radio_event_data=data;esp_radio_event_size=size;esp32_call(esp_radio_event_hook,id);esp_radio_event_data=0;esp_radio_event_size=0;esp32_irq_restore(ps);}return 0;
}

// Controller must be quiescent before dropping its final native PHY guard.
fn esp_radio_phy_disable() {
    if esp_radio_phy_refs {esp_radio_phy_refs=esp_radio_phy_refs-1;if !esp_radio_phy_refs {esp32_call32(esp32_external("phy_close_rf"),0,0,0,0,0,0,0,0);}esp_radio_phy_clock(0);}return 0;
}
fn esp_radio_phy_release_buffers() {
    if esp_radio_phy_refs || esp_radio_phy_clock_refs {return -16;}esp_sdk_free(esp_radio_phy_cal);esp_sdk_free(esp_radio_phy_init_data);esp_radio_phy_cal=0;esp_radio_phy_init_data=0;return 0;
}
