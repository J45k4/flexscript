#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include <stdint.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/reent.h>
#include <reent.h>
#include "rom-probe-config.h"
#include "rom/libc_stubs.h"
_Static_assert(sizeof(struct syscall_stub_table)==156,"39 ILP32 callbacks");
_Static_assert(offsetof(struct syscall_stub_table,_gettimeofday_r)==36 && offsetof(struct syscall_stub_table,_fstat_r)==56 && offsetof(struct syscall_stub_table,_retarget_lock_init)==96 && offsetof(struct syscall_stub_table,__assert_func)==144 && offsetof(struct syscall_stub_table,_cleanup_r)==152,"ROM table offsets");
extern struct _reent *__getreent(void);
extern char *rom_strdup(const char*);
extern long rom_strtol(const char*,char**,int);
extern int rom_printf(const char*,...);
extern unsigned rom_pause(unsigned,unsigned,unsigned,unsigned,unsigned,unsigned,unsigned,unsigned);
static unsigned error,completed;
static struct _reent *main_record;
unsigned rom_table_check(void){
 if(ferror(stdin)||ferror(stdout)||ferror(stderr))return 10;
 struct syscall_stub_table *t=syscall_table_ptr;main_record=__getreent();if(!t || t->__getreent()!=main_record || *(volatile unsigned*)ROM_GLOBAL_SLOT!=(unsigned)main_record)return 1;
 if(t->_malloc_r!=_malloc_r || t->_free_r!=_free_r || t->_realloc_r!=_realloc_r || t->_calloc_r!=_calloc_r || t->_printf_float || t->_scanf_float)return 2;
 if((uintptr_t)t->_write_r!=(uintptr_t)_write_r || (uintptr_t)t->_read_r!=(uintptr_t)_read_r || (uintptr_t)t->_close_r!=(uintptr_t)_close_r || (uintptr_t)t->_lseek_r!=(uintptr_t)_lseek_r || (uintptr_t)t->_open_r!=(uintptr_t)_open_r || (uintptr_t)t->_sbrk_r!=(uintptr_t)_sbrk_r)return 11;
 unsigned *p=(unsigned*)t;for(unsigned i=0;i<39;i++){if(i==34||i==35){if(p[i])return 3;}else if(p[i]<CODE_BEGIN || p[i]>=CODE_BEGIN+131072 || (p[i]&1))return 4;}
 struct _reent local={0};unsigned char *buf=t->_calloc_r(&local,3,7);if(!buf||buf[0]||buf[20])return 5;buf[0]=71;buf=t->_realloc_r(&local,buf,37);if(!buf||buf[0]!=71)return 6;t->_free_r(&local,buf);
 volatile unsigned guard[8];for(unsigned i=0;i<8;i++)guard[i]=0x13572468;
 local._errno=0;if(t->_gettimeofday_r(&local,(void*)guard,0)!=-1||local._errno!=ENOSYS)return 7;
 if(t->_system_r(&local,"none")!=-1 || t->_rename_r(&local,"a","b")!=-1 || t->_times_r(&local,0)!=-1 || t->_unlink_r(&local,"a")!=-1 || t->_link_r(&local,"a","b")!=-1 || t->_stat_r(&local,"a",(void*)guard)!=-1 || t->_getpid_r(&local)!=-1 || t->_kill_r(&local,1,0)!=-1 || local._errno!=ENOSYS)return 8;
 for(unsigned i=0;i<8;i++)if(guard[i]!=0x13572468)return 9;
 return 0;
}
unsigned rom_worker(unsigned tag){
 struct _reent *mine=__getreent();if(mine==&_impure_data || mine->_errno){error=1;return 0;}
 for(unsigned i=0;i<4;i++){
  char *s=rom_strdup(tag==1?"A":"B");if(!s){error=2;return 0;}errno=0;char *end;if(rom_strtol("999999999999999999999999",&end,10)!=2147483647L || errno!=ERANGE || *end){error=3;return 0;}
  errno=100+tag;if(rom_printf("ROMW%d:%s\n",tag,s)!=8){error=4;return 0;}free(s);rom_pause(tag,0,0,0,0,0,0,0);
  if(__getreent()!=mine || errno!=100+tag){error=5;return 0;}
 }
 completed++;return 0;
}
unsigned rom_result(void){return error?100+error:completed;}
unsigned rom_common_check(void){
#if ROM_HAS_COMMON_FIXTURE
 _LOCK_T cells[]={(_LOCK_T)ROM_COMMON_0,(_LOCK_T)ROM_COMMON_1};
 for(unsigned i=0;i<2;i++){
  if(*(volatile unsigned*)cells[i]!=0xbb10c433)return 1;
  if(syscall_table_ptr->_retarget_lock_try_acquire(cells[i]) || syscall_table_ptr->_retarget_lock_try_acquire(cells[i])!=-1)return 2;
  syscall_table_ptr->_retarget_lock_release(cells[i]);
  if(syscall_table_ptr->_retarget_lock_try_acquire_recursive(cells[i]) || syscall_table_ptr->_retarget_lock_try_acquire_recursive(cells[i]))return 3;
  syscall_table_ptr->_retarget_lock_release_recursive(cells[i]);syscall_table_ptr->_retarget_lock_release_recursive(cells[i]);
 }
#endif
 return 0;
}
unsigned rom_bad(unsigned which){
 struct syscall_stub_table *t=syscall_table_ptr;
 if(which==0)t->_retarget_lock_close_recursive((_LOCK_T)ROM_COMMON_0);
 else if(which==1)t->__sinit(__getreent());
 else if(which==2)t->_raise_r(__getreent());
 else if(which==3)t->_exit_r(__getreent(),0);
 else if(which==4)t->__assert_func("file",1,"function","assert");
 else if(which==5){char *s=rom_strdup("ISR");if(s)t->_free_r(__getreent(),s);}
 else if(which==6)rom_printf("ISR\n");
 return 99;
}
