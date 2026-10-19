import "esp32-radio-random.flex";
import "esp32-radio-os-state.flex";
// Shared SDK/C callbacks. Import a chip wrapper, not this module alone.
fn esp_radio_cb_env(a,b,c,d,e,f,g,h) {return 1;
}
fn esp_radio_cb_isr(a,b,c,d,e,f,g,h) {return esp32_load32(esp32_state()+16)!=0;
}
fn esp_radio_cb_spin(a,b,c,d,e,f,g,h) {return esp_radio_owned(esp_sdk_calloc(1,16));
}
fn esp_radio_cb_free(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let t=esp_sdk_tasks;while a && t {if load64(t+568)==a {store64(t+568,0);}t=load64(t+536);if t==esp_sdk_tasks {t=0;}}let result=esp_sdk_free(a);esp32_irq_restore(ps);return result;
}
fn esp_radio_cb_disable(a,b,c,d,e,f,g,h) {return esp32_irq_save();
}
fn esp_radio_cb_restore(a,b,c,d,e,f,g,h) {esp32_irq_restore(b);return 0;
}
fn esp_radio_cb_yield_isr(a,b,c,d,e,f,g,h) {return esp_sdk_reschedule_request(); // Optional preemption consumes this only after ISR callbacks return.
}
fn esp_radio_cb_sem_create(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let result=esp_radio_owned(esp_sdk_sem_create(a,b));esp32_irq_restore(ps);return result;
}
fn esp_radio_cb_sem_take(a,b,c,d,e,f,g,h) {return esp_sdk_sem_take(a,b);
}
fn esp_radio_cb_sem_give(a,b,c,d,e,f,g,h) {return esp_sdk_sem_give(a);
}
fn esp_radio_cb_thread_sem(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let p=esp_sdk_current+568;let s=load64(p);if !s {s=esp_radio_owned(esp_sdk_sem_create(1,0));store64(p,s);}esp32_irq_restore(ps);return s;
}
fn esp_radio_cb_mutex(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let result=esp_radio_owned(esp_sdk_mutex_create(0));esp32_irq_restore(ps);return result;
}
fn esp_radio_cb_recursive(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let result=esp_radio_owned(esp_sdk_mutex_create(1));esp32_irq_restore(ps);return result;
}
fn esp_radio_cb_lock(a,b,c,d,e,f,g,h) {return esp_sdk_mutex_lock(a);
}
fn esp_radio_cb_unlock(a,b,c,d,e,f,g,h) {return esp_sdk_mutex_unlock(a);
}
fn esp_radio_cb_queue(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let result=esp_radio_owned(esp_sdk_queue_create(a,b));esp32_irq_restore(ps);return result;
}
fn esp_radio_cb_send(a,b,c,d,e,f,g,h) {return esp_sdk_queue_op(a,b,c,1);
}
fn esp_radio_cb_send_isr(a,b,c,d,e,f,g,h) {return esp_sdk_queue_isr(a,b,1,c);
}
fn esp_radio_cb_front(a,b,c,d,e,f,g,h) {return esp_sdk_queue_op(a,b,c,2);
}
fn esp_radio_cb_recv(a,b,c,d,e,f,g,h) {return esp_sdk_queue_op(a,b,c,0);
}
fn esp_radio_cb_waiting(a,b,c,d,e,f,g,h) {if !a {return 0;}return load64(a+24);
}
fn esp_radio_cb_event_create(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let result=esp_radio_owned(esp_sdk_event_create());esp32_irq_restore(ps);return result;
}
fn esp_radio_cb_event_set(a,b,c,d,e,f,g,h) {return esp_sdk_event_set(a,b);
}
fn esp_radio_cb_event_clear(a,b,c,d,e,f,g,h) {return esp_sdk_event_clear(a,b);
}
fn esp_radio_cb_event_wait(a,b,c,d,e,f,g,h) {return esp_sdk_event_wait(a,b,c,d,e);
}
fn esp_radio_cb_task_create(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();if g!=0 && g!=4294967295 {esp32_irq_restore(ps);return 0;}let bytes=c;if bytes<8192 {bytes=8192;}let t=esp_radio_task_owned(esp_sdk_task_create(a,d,bytes,e));if f {esp32_store32(f,t);}esp32_irq_restore(ps);return t!=0;
}
fn esp_radio_cb_task_create_any(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let bytes=c;if bytes<8192 {bytes=8192;}let t=esp_radio_task_owned(esp_sdk_task_create(a,d,bytes,e));if f {esp32_store32(f,t);}esp32_irq_restore(ps);return t!=0;
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
fn esp_radio_cb_malloc(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let result=esp_radio_owned(esp_sdk_malloc(a));esp32_irq_restore(ps);return result;
}
fn esp_radio_cb_calloc(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let result=esp_radio_owned(esp_sdk_calloc(a,b));esp32_irq_restore(ps);return result;
}
fn esp_radio_cb_zalloc(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let result=esp_radio_owned(esp_sdk_calloc(1,a));esp32_irq_restore(ps);return result;
}
fn esp_radio_cb_realloc(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let result=esp_radio_owned(esp_sdk_realloc(a,b));esp32_irq_restore(ps);return result;
}
fn esp_radio_cb_heap(a,b,c,d,e,f,g,h) {return esp_sdk_heap_free();
}
fn esp_radio_cb_event_post(a,b,c,d,e,f,g,h) {return esp_radio_dispatch_event(b,c,d);
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
fn esp_radio_cb_timer_setfn(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let t=esp_sdk_timer_find(a);if t && esp_radio_owner && esp_sdk_heap_owner(t)!=esp_radio_owner {esp32_irq_restore(ps);return -16;}let r=esp_sdk_timer_setfn(a,b,c);if !r {esp_radio_owned(esp_sdk_timer_find(a));}esp32_irq_restore(ps);return r;
}
fn esp_radio_cb_timer_disarm(a,b,c,d,e,f,g,h) {return esp_sdk_timer_disarm(a);
}
fn esp_radio_cb_timer_done(a,b,c,d,e,f,g,h) {return esp_sdk_timer_done(a);
}
fn esp_radio_cb_timer_arm(a,b,c,d,e,f,g,h) {return esp_sdk_timer_arm(a,b*1000,c);
}
fn esp_radio_cb_timer_us(a,b,c,d,e,f,g,h) {return esp_sdk_timer_arm(a,b,c);
}




fn phy_enter_critical(a,b,c,d,e,f,g,h) {return esp32_irq_save();
}
fn phy_exit_critical(a,b,c,d,e,f,g,h) {esp32_irq_restore(a);return 0;
}
fn esp_dport_access_reg_read(a,b,c,d,e,f,g,h) {return esp32_load32(a);
}
fn rtc_get_xtal(a,b,c,d,e,f,g,h) {return 40;
}

fn __esp_radio_printf(a,b,c,d,e,f,g,h) {if esp_radio_log && b {esp_uart_write(b);esp_uart_write("\r\n");}return 0;
}
fn vTaskDelay(a,b,c,d,e,f,g,h) {return esp_sdk_delay(a);
}
fn esp_event_post(a,b,c,d,e,f,g,h) {return esp_radio_dispatch_event(b,c,d);
}
fn gettimeofday(a,b,c,d,e,f,g,h) {let now=esp_sdk_now();store64(a,now/1000000);esp32_store32(a+8,now%1000000);return 0;
}

fn sleep(a,b,c,d,e,f,g,h) {esp_sdk_delay(a*1000);return 0;
}
fn usleep(a,b,c,d,e,f,g,h) {esp_sdk_delay((a+999)/1000);return 0;
}

fn esp_radio_cb_wifi_queue(a,b,c,d,e,f,g,h) {let q=esp_radio_owned(esp_sdk_queue_create(a,b));if !q {return 0;}let p=esp_radio_owned(esp_sdk_calloc(1,4));if !p {esp_sdk_free(q);return 0;}esp32_store32(p,q);return p;}
fn esp_radio_cb_wifi_delete_queue(a,b,c,d,e,f,g,h) {if a {esp_sdk_free(esp32_load32(a));esp_sdk_free(a);}return 0;}
fn esp_radio_nvs_patch(table) {if table && esp_radio_nvs_table {let i=0;while i<12 {esp32_store32(table+esp_radio_nvs_offset()+i*4,esp32_load32(esp_radio_nvs_table+i*4));i=i+1;}}return 0;}
fn esp_radio_nvs_apply() {let ps=esp32_irq_save();esp_radio_nvs_patch(esp_radio_osi);esp32_irq_restore(ps);return 0;}
fn esp_radio_dispatch_event(id,data,size) {
    let ps=esp32_irq_save();esp_radio_last_event=id;esp_radio_events=esp_radio_events+1;
    if id==1 {esp_radio_scan_status= -1;if data && size>=6 {esp_radio_scan_status=esp32_load32(data);}esp_radio_scan_done=1;}
    let hook=esp_radio_event_hook;if hook {
        let previous_data=esp_radio_event_data;let previous_size=esp_radio_event_size;esp_radio_event_data=data;esp_radio_event_size=size;
        esp32_call(hook,id);esp_radio_event_data=previous_data;esp_radio_event_size=previous_size;
    }esp32_irq_restore(ps);return 0;
}
fn esp_radio_os_finish() {
    let exports=esp_radio_libc_exports();if exports {return exports;}
    esp32_callback32(phy_enter_critical);
    esp32_callback32(phy_exit_critical);
    esp32_callback32(esp_dport_access_reg_read);
    esp32_callback32(rtc_get_xtal);
    esp32_callback32(__esp_radio_printf);
    esp32_callback32(vTaskDelay);
    esp32_callback32(esp_event_post);
    esp32_callback32(gettimeofday);
    esp32_callback32(esp_fill_random);
    esp32_callback32(sleep);
    esp32_callback32(usleep);
    let ps=esp32_irq_save();if esp_sdk_timer_task {esp32_irq_restore(ps);return 0;}let r=esp_sdk_timer_init();if !r {esp_radio_timer_created=1;}esp32_irq_restore(ps);return r;
}
// Prepare and commit the complete ABI table as one task transaction. A failed
// scratch/timer allocation leaves both the vendor table and ready pointer intact.
fn esp_radio_os_init() {
    let ps=esp32_irq_save();if esp_radio_osi || !esp_sdk_current || esp32_load32(esp32_state()+16) || (esp_radio_owner && esp_radio_owner!=1) {esp32_irq_restore(ps);return -16;}
    let bytes=esp_radio_os_size();let prepared=esp_sdk_calloc(1,bytes);if !prepared {esp32_irq_restore(ps);return -12;}
    let claimed=!esp_radio_owner;let result=0;if claimed {result=esp_radio_resources_begin(1);}
    if !result {esp_radio_os_build(prepared);esp_radio_nvs_patch(prepared);result=esp_radio_os_finish();}
    if result {esp_sdk_free(prepared);if claimed && esp_radio_owner==1 {esp_radio_resources_end(esp32_callback(esp_radio_irq));}esp32_irq_restore(ps);return result;}
    let target=esp32_external("g_wifi_osi_funcs");let i=0;while i<bytes {esp32_store32(target+i,esp32_load32(prepared+i));i=i+4;}
    esp_radio_osi=target;esp_sdk_free(prepared);esp32_irq_restore(ps);return 0;
}
