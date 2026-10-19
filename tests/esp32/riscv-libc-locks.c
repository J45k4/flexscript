// Compile against unmodified newlib and pinned ESP-IDF sys/lock.h declarations.
#include <sys/lock.h>
_Static_assert(sizeof(_LOCK_T)==4 && sizeof(_lock_t)==4,"ILP32 handle ABI");
struct guarded_slot { unsigned before; _LOCK_T lock; unsigned after; };
static struct guarded_slot slots[4] = {
 {0x12345678,0,0x87654321},{0x12345678,0,0x87654321},
 {0x12345678,0,0x87654321},{0x12345678,0,0x87654321}};
unsigned libc_lock_call(unsigned op,unsigned index) {
 if(index>3)return 0xeeee;
 _LOCK_T *slot=&slots[index].lock;_LOCK_T handle=*slot;
 if(op==0){
  if(index==0)_lock_init(slot);else if(index==1)_lock_init_recursive(slot);
  else if(index==2)__lock_init(*slot);else __lock_init_recursive(*slot);
 }else if(op==1){
  if(index==0)return _lock_try_acquire(slot);if(index==1)return _lock_try_acquire_recursive(slot);
  if(index==2)return __lock_try_acquire(handle);return __lock_try_acquire_recursive(handle);
 }else if(op==2){
  if(index==0)_lock_acquire(slot);else if(index==1)_lock_acquire_recursive(slot);
  else if(index==2)__lock_acquire(handle);else __lock_acquire_recursive(handle);
 }else if(op==3){
  if(index==0)_lock_release(slot);else if(index==1)_lock_release_recursive(slot);
  else if(index==2)__lock_release(handle);else __lock_release_recursive(handle);
 }else if(op==4){
  if(index==0)_lock_close(slot);else if(index==1)_lock_close_recursive(slot);
  else if(index==2)__lock_close(handle);else __lock_close_recursive(handle);
 }else if(op==5)return (unsigned)*slot;
 else if(op==6)return slots[index].before==0x12345678 && slots[index].after==0x87654321;
 else if(op==7)*slot=0;
 else if(op==8)*slot=(_LOCK_T)0xa5a5a5a5;
 return 0;
}
extern unsigned libc_probe(unsigned,unsigned,unsigned,unsigned,unsigned,unsigned,unsigned,unsigned);
unsigned libc_lock_worker(unsigned index) {
 volatile unsigned guard[4]={0x13572468,0x24681357,0xdeadbeef,0x76543210};
 if(libc_lock_call(1,index)!=0xffffffffu)return 1;
 libc_probe(1,0,0,0,0,0,0,0);
 libc_lock_call(2,index);libc_probe(2,0,0,0,0,0,0,0);
 if(index&1){if(libc_lock_call(1,index))return 2;libc_lock_call(3,index);}
 libc_lock_call(3,index);
 if(guard[0]!=0x13572468 || guard[1]!=0x24681357 || guard[2]!=0xdeadbeef || guard[3]!=0x76543210)return 3;
 return 0;
}
unsigned libc_lock_bad(unsigned which,unsigned address) {
 _LOCK_T *slot=&slots[0].lock;
 if(which==0)_lock_acquire(0);
 else if(which==1)_lock_init((_lock_t *)((char *)slot+1));
 else if(which==2)_lock_init((_lock_t *)address);
 else if(which==3)__retarget_lock_try_acquire(0);
 else if(which==4){__retarget_lock_init(slot);__retarget_lock_close(*slot);__retarget_lock_acquire(*slot);}
 else if(which==5){_lock_init(slot);_lock_acquire_recursive(slot);}
 else if(which==6)_lock_release(slot);
 else if(which==7){_lock_init(slot);_lock_release(slot);}
 else if(which==8){_lock_init(slot);_lock_acquire(slot);_lock_close(slot);}
 else if(which==9){_lock_init(slot);_lock_acquire(slot);_lock_acquire(slot);}
 else if(which==10)_lock_init(slot);
 else if(which==11)__retarget_lock_acquire((_LOCK_T)address);
 else if(which==12){__retarget_lock_init_recursive(slot);__retarget_lock_close(*slot);}
 else if(which==13)__retarget_lock_release(*slot);
 else if(which==14)__retarget_lock_init((_LOCK_T *)address);
 else if(which==15)_lock_try_acquire(slot);
 return 99;
}
static volatile unsigned protected_counter;
unsigned libc_lock_count(void){return protected_counter;}
unsigned libc_lock_stress(unsigned index,unsigned rounds){
 volatile unsigned guard[3]={0x13572468,0xdeadbeef,0x76543210};
 for(unsigned i=0;i<rounds;i++){
  libc_lock_call(2,index);unsigned before=protected_counter;
  if(libc_lock_call(1,index))return 1;
  libc_probe(3,0,0,0,0,0,0,0);
  if(protected_counter!=before)return 2;
  protected_counter=before+1;libc_lock_call(3,index);libc_lock_call(3,index);
  if(guard[0]!=0x13572468 || guard[1]!=0xdeadbeef || guard[2]!=0x76543210)return 3;
 }
 return 0;
}
