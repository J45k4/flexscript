/* GNU C peer compiled against the matching pinned vendor v9 header. */
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "wifi_os_adapter.h"
#include "soc/efuse_reg.h"
#ifdef C6
#include "soc/lp_aon_reg.h"
#define RTC_CNTL_STORE1_REG LP_AON_STORE1_REG
#else
#include "soc/rtc_cntl_reg.h"
#endif
#ifdef C6
_Static_assert(sizeof(wifi_osi_funcs_t)==508,"C6 OSI v9 size");
#else
_Static_assert(sizeof(wifi_osi_funcs_t)==480,"C3 OSI v9 size");
#endif
struct osi_guard {uint32_t before[4];wifi_osi_funcs_t table;uint32_t after[4];};
struct osi_guard c_rv_osi_guard;
__asm__(".global g_wifi_osi_funcs\n.set g_wifi_osi_funcs,c_rv_osi_guard+16");
volatile uint32_t c_rv_osi_timer_count,c_rv_osi_timer_bad;
uint32_t c_rv_osi_reset(void) {
    for(unsigned i=0;i<4;i++){c_rv_osi_guard.before[i]=0x13572468+i;c_rv_osi_guard.after[i]=0x24681357+i;}
    for(unsigned i=0;i<sizeof(wifi_osi_funcs_t);i++)((volatile uint8_t *)&g_wifi_osi_funcs)[i]=0xa5;
    c_rv_osi_timer_count=0;c_rv_osi_timer_bad=0;return 0;
}
uint32_t c_rv_osi_guard_check(uint32_t untouched) {
    for(unsigned i=0;i<4;i++)if(c_rv_osi_guard.before[i]!=0x13572468+i || c_rv_osi_guard.after[i]!=0x24681357+i)return 1;
    if(untouched)for(unsigned i=0;i<sizeof(wifi_osi_funcs_t);i++)if(((volatile uint8_t *)&g_wifi_osi_funcs)[i]!=0xa5)return 2;
    return 0;
}
static void timer_callback(void *p) {c_rv_osi_timer_count++;if((uintptr_t)p!=0x13572468)c_rv_osi_timer_bad++;}
uint32_t c_rv_osi_exercise(uint32_t current) {
    wifi_osi_funcs_t *t=&g_wifi_osi_funcs;
    if(c_rv_osi_guard_check(0) || t->_version!=ESP_WIFI_OS_ADAPTER_VERSION || t->_magic!=ESP_WIFI_OS_ADAPTER_MAGIC)return 1;
    for(unsigned i=1;i<sizeof(wifi_osi_funcs_t)/4-1;i++) {
        unsigned at=i*4;uint32_t value=((const uint32_t *)t)[i];
        int optional=at==offsetof(wifi_osi_funcs_t,_log_write) || at==offsetof(wifi_osi_funcs_t,_log_writev) || at==offsetof(wifi_osi_funcs_t,_coex_condition_set);
        if(optional?value!=0:value==0)return 2;
    }
    #ifdef C6
    if(t->_wifi_disable_ac_ax() || t->_wifi_bb_sleep_retention_attach()!=1 || t->_wifi_bb_sleep_retention_detach()!=1 || t->_wifi_mac_sleep_retention_attach()!=1 || t->_wifi_mac_sleep_retention_detach()!=1)return 24;
    #endif
    if(!t->_env_is_chip() || t->_is_from_isr() || (uintptr_t)t->_task_get_current_task()!=current || t->_task_get_max_priority()!=25 || t->_task_ms_to_tick(123)!=123)return 3;
    uint32_t before=t->_get_free_heap_size();uint8_t *p=t->_calloc_internal(3,7);if(!p)return 4;
    for(unsigned i=0;i<21;i++)if(p[i])return 5;
    for(unsigned i=0;i<21;i++)p[i]=(uint8_t)(i*13+7);
    uint8_t *q=t->_realloc_internal(p,37);if(!q)return 6;
    for(unsigned i=0;i<21;i++)if(q[i]!=(uint8_t)(i*13+7))return 7;
    t->_free(q);if(t->_get_free_heap_size()!=before)return 8;
    void *sem=t->_semphr_create(2,1);if(!sem || !t->_semphr_take(sem,0) || t->_semphr_take(sem,0) || !t->_semphr_give(sem))return 9;t->_semphr_delete(sem);
    void *mutex=t->_recursive_mutex_create();if(!mutex || !t->_mutex_lock(mutex) || !t->_mutex_lock(mutex) || !t->_mutex_unlock(mutex) || !t->_mutex_unlock(mutex))return 10;t->_mutex_delete(mutex);
    void *queue=t->_queue_create(2,sizeof(uint32_t));uint32_t a=0x12345678,b=0x87654321,out=0;
    if(!queue || !t->_queue_send(queue,&a,0) || !t->_queue_send_to_front(queue,&b,0) || t->_queue_msg_waiting(queue)!=2 || !t->_queue_recv(queue,&out,0) || out!=b || !t->_queue_recv(queue,&out,0) || out!=a)return 11;t->_queue_delete(queue);
    void *event=t->_event_group_create();if(!event || t->_event_group_set_bits(event,5)!=5 || t->_event_group_wait_bits(event,1,1,0,0)!=5 || t->_event_group_clear_bits(event,4)!=4)return 12;t->_event_group_delete(event);
    void *thread_sem=t->_wifi_thread_semphr_get();if(!thread_sem || t->_wifi_thread_semphr_get()!=thread_sem)return 13;
    uint8_t random[35];for(unsigned i=0;i<35;i++)random[i]=0xa5;
    if(t->_get_random(random+2,31) || random[0]!=0xa5 || random[1]!=0xa5 || random[33]!=0xa5 || random[34]!=0xa5)return 14;
    uint64_t base=(((uint64_t)*(volatile uint32_t *)EFUSE_RD_MAC_SPI_SYS_1_REG&65535)<<32)|*(volatile uint32_t *)EFUSE_RD_MAC_SPI_SYS_0_REG;
    for(unsigned kind=0;kind<3;kind++) {uint8_t mac[8];for(unsigned i=0;i<8;i++)mac[i]=0xa5;
        if(t->_read_mac(mac+1,kind) || mac[0]!=0xa5 || mac[7]!=0xa5)return 15;
        for(unsigned i=0;i<6;i++)if(mac[i+1]!=(uint8_t)((base+kind)>>(40-i*8)))return 16;
    }
    if(t->_slowclk_cal_get()!=(*(volatile uint32_t *)RTC_CNTL_STORE1_REG>>7) || t->_phy_update_country_info("FI")!=0x106)return 17;
    struct {int64_t sec;int32_t us;uint32_t guard;} stamp;stamp.sec=-1;stamp.us=-1;stamp.guard=0x13572468;
    int64_t time_before=t->_esp_timer_get_time();if(t->_get_time(&stamp))return 22;int64_t time_after=t->_esp_timer_get_time();
    int64_t stamped=stamp.sec*1000000+stamp.us;if(stamp.us<0 || stamp.us>=1000000 || stamp.guard!=0x13572468 || stamped<time_before || stamped>time_after)return 23;
    uint32_t timer_key[4];for(unsigned i=0;i<4;i++)timer_key[i]=0;
    t->_timer_setfn(timer_key,(void *)timer_callback,(void *)0x13572468);t->_timer_arm_us(timer_key,1,0);t->_task_delay(3);t->_timer_disarm(timer_key);t->_timer_done(timer_key);
    if(c_rv_osi_timer_count!=1 || c_rv_osi_timer_bad)return 18;
    uint32_t payload[2];payload[0]=0x12345678;payload[1]=0x87654321;
    if(t->_event_post((const char *)1,42,payload,sizeof(payload),0))return 19;
    void *wifi_queue=t->_wifi_create_queue(2,4);if(!wifi_queue)return 20;t->_wifi_delete_queue(wifi_queue);
    return c_rv_osi_guard_check(0)?21:0;
}
uint32_t c_rv_osi_nvs_check(void) {
    wifi_osi_funcs_t *t=&g_wifi_osi_funcs;int8_t i8=0;uint8_t u8=0;uint16_t u16=0;uint32_t handle=0;size_t size=0;
    if(t->_nvs_set_i8(1,"x",-5)!=0x1200 || t->_nvs_get_i8(1,"x",&i8)!=0x1201 || t->_nvs_set_u8(1,"x",5)!=0x1202 || t->_nvs_get_u8(1,"x",&u8)!=0x1203 || t->_nvs_set_u16(1,"x",7)!=0x1204 || t->_nvs_get_u16(1,"x",&u16)!=0x1205 || t->_nvs_open("x",0,&handle)!=0x1206 || t->_nvs_commit(1)!=0x1208 || t->_nvs_set_blob(1,"x",&u16,2)!=0x1209 || t->_nvs_get_blob(1,"x",&u16,&size)!=0x120a || t->_nvs_erase_key(1,"x")!=0x120b)return 1;
    t->_nvs_close(1);return 0;
}

uint32_t c_rv_osi_offset(uint32_t index) {static const uint32_t offsets[]={offsetof(wifi_osi_funcs_t,_version),offsetof(wifi_osi_funcs_t,_env_is_chip),offsetof(wifi_osi_funcs_t,_set_intr),offsetof(wifi_osi_funcs_t,_clear_intr),offsetof(wifi_osi_funcs_t,_set_isr),offsetof(wifi_osi_funcs_t,_ints_on),offsetof(wifi_osi_funcs_t,_ints_off),offsetof(wifi_osi_funcs_t,_is_from_isr),offsetof(wifi_osi_funcs_t,_spin_lock_create),offsetof(wifi_osi_funcs_t,_spin_lock_delete),offsetof(wifi_osi_funcs_t,_wifi_int_disable),offsetof(wifi_osi_funcs_t,_wifi_int_restore),offsetof(wifi_osi_funcs_t,_task_yield_from_isr),offsetof(wifi_osi_funcs_t,_semphr_create),offsetof(wifi_osi_funcs_t,_semphr_delete),offsetof(wifi_osi_funcs_t,_semphr_take),offsetof(wifi_osi_funcs_t,_semphr_give),offsetof(wifi_osi_funcs_t,_wifi_thread_semphr_get),offsetof(wifi_osi_funcs_t,_mutex_create),offsetof(wifi_osi_funcs_t,_recursive_mutex_create),offsetof(wifi_osi_funcs_t,_mutex_delete),offsetof(wifi_osi_funcs_t,_mutex_lock),offsetof(wifi_osi_funcs_t,_mutex_unlock),offsetof(wifi_osi_funcs_t,_queue_create),offsetof(wifi_osi_funcs_t,_queue_delete),offsetof(wifi_osi_funcs_t,_queue_send),offsetof(wifi_osi_funcs_t,_queue_send_from_isr),offsetof(wifi_osi_funcs_t,_queue_send_to_back),offsetof(wifi_osi_funcs_t,_queue_send_to_front),offsetof(wifi_osi_funcs_t,_queue_recv),offsetof(wifi_osi_funcs_t,_queue_msg_waiting),offsetof(wifi_osi_funcs_t,_event_group_create),offsetof(wifi_osi_funcs_t,_event_group_delete),offsetof(wifi_osi_funcs_t,_event_group_set_bits),offsetof(wifi_osi_funcs_t,_event_group_clear_bits),offsetof(wifi_osi_funcs_t,_event_group_wait_bits),offsetof(wifi_osi_funcs_t,_task_create_pinned_to_core),offsetof(wifi_osi_funcs_t,_task_create),offsetof(wifi_osi_funcs_t,_task_delete),offsetof(wifi_osi_funcs_t,_task_delay),offsetof(wifi_osi_funcs_t,_task_ms_to_tick),offsetof(wifi_osi_funcs_t,_task_get_current_task),offsetof(wifi_osi_funcs_t,_task_get_max_priority),offsetof(wifi_osi_funcs_t,_malloc),offsetof(wifi_osi_funcs_t,_free),offsetof(wifi_osi_funcs_t,_event_post),offsetof(wifi_osi_funcs_t,_get_free_heap_size),offsetof(wifi_osi_funcs_t,_rand),offsetof(wifi_osi_funcs_t,_dport_access_stall_other_cpu_start_wrap),offsetof(wifi_osi_funcs_t,_dport_access_stall_other_cpu_end_wrap),offsetof(wifi_osi_funcs_t,_wifi_pm_sleep_lock_acquire),offsetof(wifi_osi_funcs_t,_wifi_pm_sleep_lock_release),offsetof(wifi_osi_funcs_t,_phy_disable),offsetof(wifi_osi_funcs_t,_phy_enable),offsetof(wifi_osi_funcs_t,_phy_update_country_info),offsetof(wifi_osi_funcs_t,_read_mac),offsetof(wifi_osi_funcs_t,_timer_arm),offsetof(wifi_osi_funcs_t,_timer_disarm),offsetof(wifi_osi_funcs_t,_timer_done),offsetof(wifi_osi_funcs_t,_timer_setfn),offsetof(wifi_osi_funcs_t,_timer_arm_us),offsetof(wifi_osi_funcs_t,_wifi_reset_mac),offsetof(wifi_osi_funcs_t,_wifi_clock_enable),offsetof(wifi_osi_funcs_t,_wifi_clock_disable),offsetof(wifi_osi_funcs_t,_wifi_rtc_enable_iso),offsetof(wifi_osi_funcs_t,_wifi_rtc_disable_iso),offsetof(wifi_osi_funcs_t,_esp_timer_get_time),offsetof(wifi_osi_funcs_t,_nvs_set_i8),offsetof(wifi_osi_funcs_t,_nvs_get_i8),offsetof(wifi_osi_funcs_t,_nvs_set_u8),offsetof(wifi_osi_funcs_t,_nvs_get_u8),offsetof(wifi_osi_funcs_t,_nvs_set_u16),offsetof(wifi_osi_funcs_t,_nvs_get_u16),offsetof(wifi_osi_funcs_t,_nvs_open),offsetof(wifi_osi_funcs_t,_nvs_close),offsetof(wifi_osi_funcs_t,_nvs_commit),offsetof(wifi_osi_funcs_t,_nvs_set_blob),offsetof(wifi_osi_funcs_t,_nvs_get_blob),offsetof(wifi_osi_funcs_t,_nvs_erase_key),offsetof(wifi_osi_funcs_t,_get_random),offsetof(wifi_osi_funcs_t,_get_time),offsetof(wifi_osi_funcs_t,_random),offsetof(wifi_osi_funcs_t,_slowclk_cal_get),offsetof(wifi_osi_funcs_t,_log_write),offsetof(wifi_osi_funcs_t,_log_writev),offsetof(wifi_osi_funcs_t,_log_timestamp),offsetof(wifi_osi_funcs_t,_malloc_internal),offsetof(wifi_osi_funcs_t,_realloc_internal),offsetof(wifi_osi_funcs_t,_calloc_internal),offsetof(wifi_osi_funcs_t,_zalloc_internal),offsetof(wifi_osi_funcs_t,_wifi_malloc),offsetof(wifi_osi_funcs_t,_wifi_realloc),offsetof(wifi_osi_funcs_t,_wifi_calloc),offsetof(wifi_osi_funcs_t,_wifi_zalloc),offsetof(wifi_osi_funcs_t,_wifi_create_queue),offsetof(wifi_osi_funcs_t,_wifi_delete_queue),offsetof(wifi_osi_funcs_t,_coex_init),offsetof(wifi_osi_funcs_t,_coex_deinit),offsetof(wifi_osi_funcs_t,_coex_enable),offsetof(wifi_osi_funcs_t,_coex_disable),offsetof(wifi_osi_funcs_t,_coex_status_get),offsetof(wifi_osi_funcs_t,_coex_condition_set),offsetof(wifi_osi_funcs_t,_coex_wifi_request),offsetof(wifi_osi_funcs_t,_coex_wifi_release),offsetof(wifi_osi_funcs_t,_coex_wifi_channel_set),offsetof(wifi_osi_funcs_t,_coex_event_duration_get),offsetof(wifi_osi_funcs_t,_coex_pti_get),offsetof(wifi_osi_funcs_t,_coex_schm_status_bit_clear),offsetof(wifi_osi_funcs_t,_coex_schm_status_bit_set),offsetof(wifi_osi_funcs_t,_coex_schm_interval_set),offsetof(wifi_osi_funcs_t,_coex_schm_interval_get),offsetof(wifi_osi_funcs_t,_coex_schm_curr_period_get),offsetof(wifi_osi_funcs_t,_coex_schm_curr_phase_get),offsetof(wifi_osi_funcs_t,_coex_schm_process_restart),offsetof(wifi_osi_funcs_t,_coex_schm_register_cb),offsetof(wifi_osi_funcs_t,_coex_register_start_cb),
#ifdef C6
 offsetof(wifi_osi_funcs_t,_regdma_link_set_write_wait_content),offsetof(wifi_osi_funcs_t,_sleep_retention_find_link_by_id),
#endif
 offsetof(wifi_osi_funcs_t,_coex_schm_flexible_period_set),offsetof(wifi_osi_funcs_t,_coex_schm_flexible_period_get),offsetof(wifi_osi_funcs_t,_coex_schm_get_phase_by_idx),
#ifdef C6
 offsetof(wifi_osi_funcs_t,_wifi_disable_ac_ax),offsetof(wifi_osi_funcs_t,_wifi_bb_sleep_retention_attach),offsetof(wifi_osi_funcs_t,_wifi_bb_sleep_retention_detach),offsetof(wifi_osi_funcs_t,_wifi_mac_sleep_retention_attach),offsetof(wifi_osi_funcs_t,_wifi_mac_sleep_retention_detach),
#endif
 offsetof(wifi_osi_funcs_t,_magic)};return index<sizeof(wifi_osi_funcs_t)/4?offsets[index]:0xffffffff;}
uint32_t c_rv_osi_nvs_0(void) {return 4608;}
uint32_t c_rv_osi_nvs_1(void) {return 4609;}
uint32_t c_rv_osi_nvs_2(void) {return 4610;}
uint32_t c_rv_osi_nvs_3(void) {return 4611;}
uint32_t c_rv_osi_nvs_4(void) {return 4612;}
uint32_t c_rv_osi_nvs_5(void) {return 4613;}
uint32_t c_rv_osi_nvs_6(void) {return 4614;}
uint32_t c_rv_osi_nvs_7(void) {return 4615;}
uint32_t c_rv_osi_nvs_8(void) {return 4616;}
uint32_t c_rv_osi_nvs_9(void) {return 4617;}
uint32_t c_rv_osi_nvs_10(void) {return 4618;}
uint32_t c_rv_osi_nvs_11(void) {return 4619;}
