import "esp32s3-radio-hardware.flex";
import "esp32s3-sdk-sync.flex";
import "esp32s3-radio-irq.flex";
import "esp32s3-radio-phy.flex";
import "esp32-radio-os-core.flex";
// Exact S3 OSI-v9 contract from esp-wifi-sys 5afc3a38 (480 bytes).
fn esp_radio_os_size() {return 480;}
fn esp_radio_nvs_offset() {return 268;}






fn esp_radio_cb_phy_on(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();let result=esp_radio_phy_enable();if !result {esp32_call32(esp32_external("phy_wifi_enable_set"),1,0,0,0,0,0,0,0);}esp32_irq_restore(ps);if result {return esp_radio_fail(0x2001);}return 0;}
fn esp_radio_cb_phy_off(a,b,c,d,e,f,g,h) {let ps=esp32_irq_save();esp32_call32(esp32_external("phy_wifi_enable_set"),0,0,0,0,0,0,0,0);let result=esp_radio_phy_disable();esp32_irq_restore(ps);return result;}
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
    esp32_store32(table+216,esp32_callback32(esp_radio_cb_unsupported)); // _phy_update_country_info
    esp32_store32(table+220,esp32_callback32(esp_radio_cb_read_mac)); // _read_mac
    esp32_store32(table+224,esp32_callback32(esp_radio_cb_timer_arm)); // _timer_arm
    esp32_store32(table+228,esp32_callback32(esp_radio_cb_timer_disarm)); // _timer_disarm
    esp32_store32(table+232,esp32_callback32(esp_radio_cb_timer_done)); // _timer_done
    esp32_store32(table+236,esp32_callback32(esp_radio_cb_timer_setfn)); // _timer_setfn
    esp32_store32(table+240,esp32_callback32(esp_radio_cb_timer_us)); // _timer_arm_us
    esp32_store32(table+244,esp32_callback32(esp_radio_cb_wifi_reset)); // _wifi_reset_mac
    esp32_store32(table+248,esp32_callback32(esp_radio_cb_wifi_clock_on)); // _wifi_clock_enable
    esp32_store32(table+252,esp32_callback32(esp_radio_cb_wifi_clock_off)); // _wifi_clock_disable
    esp32_store32(table+256,esp32_callback32(esp_radio_cb_unsupported)); // _wifi_rtc_enable_iso
    esp32_store32(table+260,esp32_callback32(esp_radio_cb_unsupported)); // _wifi_rtc_disable_iso
    esp32_store32(table+264,esp32_callback32(esp_radio_cb_time)); // _esp_timer_get_time
    esp32_store32(table+268,esp32_callback32(esp_radio_cb_nvs)); // _nvs_set_i8
    esp32_store32(table+272,esp32_callback32(esp_radio_cb_nvs)); // _nvs_get_i8
    esp32_store32(table+276,esp32_callback32(esp_radio_cb_nvs)); // _nvs_set_u8
    esp32_store32(table+280,esp32_callback32(esp_radio_cb_nvs)); // _nvs_get_u8
    esp32_store32(table+284,esp32_callback32(esp_radio_cb_nvs)); // _nvs_set_u16
    esp32_store32(table+288,esp32_callback32(esp_radio_cb_nvs)); // _nvs_get_u16
    esp32_store32(table+292,esp32_callback32(esp_radio_cb_nvs)); // _nvs_open
    esp32_store32(table+296,esp32_callback32(esp_radio_cb_nvs)); // _nvs_close
    esp32_store32(table+300,esp32_callback32(esp_radio_cb_nvs)); // _nvs_commit
    esp32_store32(table+304,esp32_callback32(esp_radio_cb_nvs)); // _nvs_set_blob
    esp32_store32(table+308,esp32_callback32(esp_radio_cb_nvs)); // _nvs_get_blob
    esp32_store32(table+312,esp32_callback32(esp_radio_cb_nvs)); // _nvs_erase_key
    esp32_store32(table+316,esp32_callback32(esp_radio_cb_get_random)); // _get_random
    esp32_store32(table+320,esp32_callback32(esp_radio_cb_get_time)); // _get_time
    esp32_store32(table+324,esp32_callback32(esp_radio_cb_random)); // _random
    esp32_store32(table+328,esp32_callback32(esp_radio_cb_slowclk_cal)); // _slowclk_cal_get
    esp32_store32(table+332,0); // _log_write
    esp32_store32(table+336,0); // _log_writev
    esp32_store32(table+340,esp32_callback32(esp_radio_cb_timestamp)); // _log_timestamp
    esp32_store32(table+344,esp32_callback32(esp_radio_cb_malloc)); // _malloc_internal
    esp32_store32(table+348,esp32_callback32(esp_radio_cb_realloc)); // _realloc_internal
    esp32_store32(table+352,esp32_callback32(esp_radio_cb_calloc)); // _calloc_internal
    esp32_store32(table+356,esp32_callback32(esp_radio_cb_zalloc)); // _zalloc_internal
    esp32_store32(table+360,esp32_callback32(esp_radio_cb_malloc)); // _wifi_malloc
    esp32_store32(table+364,esp32_callback32(esp_radio_cb_realloc)); // _wifi_realloc
    esp32_store32(table+368,esp32_callback32(esp_radio_cb_calloc)); // _wifi_calloc
    esp32_store32(table+372,esp32_callback32(esp_radio_cb_zalloc)); // _wifi_zalloc
    esp32_store32(table+376,esp32_callback32(esp_radio_cb_wifi_queue)); // _wifi_create_queue
    esp32_store32(table+380,esp32_callback32(esp_radio_cb_wifi_delete_queue)); // _wifi_delete_queue
    esp32_store32(table+384,esp32_callback32(esp_radio_cb_no_coex)); // _coex_init
    esp32_store32(table+388,esp32_callback32(esp_radio_cb_no_coex)); // _coex_deinit
    esp32_store32(table+392,esp32_callback32(esp_radio_cb_no_coex)); // _coex_enable
    esp32_store32(table+396,esp32_callback32(esp_radio_cb_no_coex)); // _coex_disable
    esp32_store32(table+400,esp32_callback32(esp_radio_cb_no_coex)); // _coex_status_get
    esp32_store32(table+404,0); // _coex_condition_set
    esp32_store32(table+408,esp32_callback32(esp_radio_cb_no_coex)); // _coex_wifi_request
    esp32_store32(table+412,esp32_callback32(esp_radio_cb_no_coex)); // _coex_wifi_release
    esp32_store32(table+416,esp32_callback32(esp_radio_cb_no_coex)); // _coex_wifi_channel_set
    esp32_store32(table+420,esp32_callback32(esp_radio_cb_no_coex)); // _coex_event_duration_get
    esp32_store32(table+424,esp32_callback32(esp_radio_cb_no_coex)); // _coex_pti_get
    esp32_store32(table+428,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_status_bit_clear
    esp32_store32(table+432,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_status_bit_set
    esp32_store32(table+436,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_interval_set
    esp32_store32(table+440,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_interval_get
    esp32_store32(table+444,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_curr_period_get
    esp32_store32(table+448,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_curr_phase_get
    esp32_store32(table+452,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_process_restart
    esp32_store32(table+456,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_register_cb
    esp32_store32(table+460,esp32_callback32(esp_radio_cb_no_coex)); // _coex_register_start_cb
    esp32_store32(table+464,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_flexible_period_set
    esp32_store32(table+468,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_flexible_period_get
    esp32_store32(table+472,esp32_callback32(esp_radio_cb_no_coex)); // _coex_schm_get_phase_by_idx
    esp32_store32(table+476,3735928495); // _magic
    return 0;
}
