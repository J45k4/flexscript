#include <stdint.h>
extern unsigned atom_pause(unsigned,unsigned,unsigned,unsigned,unsigned,unsigned,unsigned,unsigned);
static unsigned counter,protected_sum,marker,error,completed,irq_count;
static unsigned char lock;
extern void Cache_Disable_ICache(void);
extern void Cache_Enable_ICache(unsigned);
static unsigned ps(void){unsigned value;__asm__ volatile("csrr %0,mstatus":"=r"(value));return value;}
unsigned atomic_basic(void){
 unsigned values[]={0,1,0x7fffffff,0x80000000,0xffffffff,0x12345678};
 for(unsigned order=0;order<6;order++)for(unsigned i=0;i<6;i++)for(unsigned j=0;j<6;j++){
  unsigned before=ps(),v=values[i];unsigned old=__atomic_fetch_add(&v,values[j],order);if(old!=values[i]||v!=(values[i]+values[j])||ps()!=before)return 1;
  old=__atomic_fetch_sub(&v,values[j],order);if(old!=(values[i]+values[j])||v!=values[i]||ps()!=before)return 2;
  old=__atomic_exchange_n(&v,values[j],order);if(old!=values[i]||v!=values[j]||ps()!=before)return 3;
 }
 for(unsigned success=0;success<6;success++)for(unsigned failure=0;failure<6;failure++){
  if(failure==3||failure==4)continue;
  if((success==0&&failure)||(success==1&&failure>1)||(success==2&&failure>2)||(success==3&&failure)||(success==4&&failure>2))continue;
  for(unsigned seed=0;seed<256;seed++){
   unsigned char bytes[8];for(unsigned i=0;i<8;i++)bytes[i]=0xa5;bytes[2]=seed;bytes[5]=seed;
   unsigned before=ps();if(!__atomic_compare_exchange_n(&bytes[2],&bytes[5],255-seed,0,success,failure)||bytes[2]!=255-seed||bytes[5]!=seed||ps()!=before)return 4;
   bytes[5]=seed^1;if(__atomic_compare_exchange_n(&bytes[2],&bytes[5],seed,1,success,failure)){if((seed^1)!=(255-seed))return 5;}else if(bytes[5]!=255-seed||bytes[2]!=255-seed)return 6;
   for(unsigned i=0;i<8;i++)if(i!=2&&i!=5&&bytes[i]!=0xa5)return 7;
  }
 }
 return 0;
}
__attribute__((section(".iram1"),noinline)) unsigned atomic_cache_probe(void){
 Cache_Disable_ICache();unsigned bad=0;
 if(__atomic_exchange_n(&counter,0xfedcba98,5)!=0)bad|=1;
 if(__atomic_fetch_add(&counter,1,0)!=0xfedcba98)bad|=2;
 if(__atomic_fetch_sub(&counter,1,2)!=0xfedcba99)bad|=4;
 unsigned char value=6,expected=6;
 if(!__atomic_compare_exchange_n(&value,&expected,7,0,5,5)||value!=7)bad|=8;
 counter=0;Cache_Enable_ICache(0);return bad;
}
unsigned atomic_worker(unsigned tag){
 for(unsigned i=0;i<500;i++){
  unsigned char expected;
  do{expected=0;if(__atomic_compare_exchange_n(&lock,&expected,1,1,2,0))break;atom_pause(1,0,0,0,0,0,0,0);}while(1);
  unsigned before=protected_sum;protected_sum=before+tag;
  if(__atomic_exchange_n(&marker,protected_sum,5)!=before){error=1;return 0;}
  if(!(i&15))atom_pause(2,0,0,0,0,0,0,0);
  expected=1;if(!__atomic_compare_exchange_n(&lock,&expected,0,0,3,0)){error=2;return 0;}
  __atomic_fetch_add(&counter,1,i%6);__atomic_fetch_add(&counter,0x10000000,0);__atomic_fetch_sub(&counter,0x10000000,0);
  if(!(i&31))atom_pause(3,0,0,0,0,0,0,0);
 }
 __atomic_fetch_add(&completed,1,0);return 0;
}
unsigned atomic_interrupt(void){
 if(ps()&8){error=3;return 0;}
 unsigned before=ps();__atomic_fetch_add(&counter,1,5);irq_count++;if(ps()!=before){error=4;return 0;}
 unsigned char value=0,expected=0;if(!__atomic_compare_exchange_n(&value,&expected,0xa5,0,5,5)||value!=0xa5){error=5;return 0;}return 0;
}
unsigned atomic_result(void){if(error)return 100+error;if(completed!=2||protected_sum!=1500||marker!=1500||lock||!irq_count||counter!=1000+irq_count)return 1;return 0;}
unsigned atomic_directed_reset(void){counter=0;irq_count=0;error=0;return (unsigned)(uintptr_t)&counter;}
unsigned atomic_directed_add(void){return __atomic_fetch_add(&counter,1,0);}
unsigned atomic_directed_check(void){return error||counter!=2||irq_count!=1;}
unsigned atomic_bad(unsigned which,unsigned pointer){
 if(which==0)return __atomic_exchange_n((unsigned*)pointer,0x12345678,5);
 unsigned char expected=0;
 if(which==1)return __atomic_compare_exchange_n((unsigned char*)pointer,&expected,1,0,5,5);
 if(which==2)return __atomic_compare_exchange_n(&lock,(unsigned char*)pointer,1,0,5,5);
 return 99;
}
