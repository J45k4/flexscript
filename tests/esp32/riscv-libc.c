#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reent.h>
_Static_assert(sizeof(struct _reent)==240 && _Alignof(struct _reent)==4,"pinned RV32 reent size/alignment");
_Static_assert(offsetof(struct _reent,_errno)==0 && offsetof(struct _reent,_stdin)==4 && offsetof(struct _reent,__cleanup)==40 && offsetof(struct _reent,_misc)==232,"pinned RV32 reent fields");
extern struct _reent *__getreent(void);
extern struct _reent *_global_impure_ptr;
extern unsigned libc_pause(unsigned,unsigned,unsigned,unsigned,unsigned,unsigned,unsigned,unsigned);
static volatile unsigned failures;
static volatile unsigned completed;
static _Thread_local unsigned user_tls=0x13579bdf;
unsigned libc_identity(void){return user_tls==0x13579bdf?(unsigned)__getreent():0;}
unsigned libc_status(void){return failures?failures:completed;}
unsigned libc_memory(void){
 errno=77;unsigned char *a=malloc(33);if(!a || ((unsigned)a&15))return 1;
 for(unsigned i=0;i<33;i++)a[i]=i+7;
 unsigned char *b=realloc(a,16384);if(!b)return 2;
 for(unsigned i=0;i<33;i++)if(b[i]!=i+7)return 3;
 void *c=realloc(b,0xffffffffu);if(c || errno!=ENOMEM || b[0]!=7)return 4;
 free(b);errno=91;free(NULL);if(errno!=91)return 5;
 c=calloc(0xffffffffu,0xffffffffu);if(c || errno!=ENOMEM)return 6;
 unsigned *d=calloc(3,sizeof(*d));if(!d || d[0] || d[1] || d[2])return 7;
 if(realloc(d,0))return 8;
 errno=91;struct _reent local={0};local._errno=17;
 if(_malloc_r(&local,0xffffffffu) || local._errno!=ENOMEM)return 9;
 if(errno!=91)return 10;
 unsigned char *e=_calloc_r(&local,2,7);if(!e || e[0] || e[13])return 11;e[0]=39;
 e=_realloc_r(&local,e,27);if(!e || e[0]!=39)return 12;_free_r(&local,e);
 return 0;
}
unsigned libc_worker(unsigned tag,unsigned rounds){
 struct _reent *mine=__getreent();if(!mine || mine==_global_impure_ptr || _REENT!=mine || _impure_ptr!=mine || user_tls!=0x13579bdf || mine->_errno || mine->_r48 || mine->_misc){failures=101;return 0;}
 char text[16]={'a'+tag,',','x'+tag,',','0'+tag,0};
 for(unsigned i=0;i<rounds;i++){
  if(__getreent()!=mine || _REENT!=mine || _impure_ptr!=mine){failures=102;return 0;}
  char *end;errno=0;if(strtol("999999999999999999999999999",&end,10)!=2147483647L || errno!=ERANGE || *end){failures=103;return 0;}
  errno=tag+100;user_tls=(tag<<16)+i;char *first=strtok(text,",");if(!first || *first!='a'+tag){failures=104;return 0;}
  srand(tag+1);unsigned expected=rand();srand(tag+1);
  libc_pause(tag,i,0,0,0,0,0,0);
  if(errno!=tag+100 || __getreent()!=mine || _REENT!=mine || _impure_ptr!=mine || rand()!=expected || user_tls!=(tag<<16)+i){failures=105;return 0;}
  char *next=strtok(NULL,",");if(!next || *next!='x'+tag){failures=106;return 0;}
  next=strtok(NULL,",");if(!next || *next!='0'+tag || strtok(NULL,",")){failures=107;return 0;}
  text[1]=',';text[3]=',';
 }
 completed++;return 0;
}
unsigned libc_preempt_worker(unsigned tag){return libc_worker(tag,12);}
unsigned libc_bad(unsigned which,unsigned address){
 if(which==0)malloc(1);
 else if(which==1)__getreent();
 else if(which==2)free((void *)address);
 else if(which==3)_malloc_r(NULL,1);
 else if(which==4)_malloc_r((struct _reent *)address,1);
 else if(which==5)realloc((void *)address,16);
 else if(which==6)_free_r(__getreent(),(void *)address);
 else if(which==7){errno=39;}
 else if(which==8)rand();
 else if(which==9){char text[]="a,b";strtok(text,",");}
 return 99;
}
