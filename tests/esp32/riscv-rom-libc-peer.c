#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/reent.h>
#include "rom-probe-config.h"
#include "rom/libc_stubs.h"
extern struct _reent *__getreent(void);
unsigned rom_peer(void){
 struct _reent *r=__getreent();struct syscall_stub_table *t=syscall_table_ptr;unsigned long long words[2];unsigned char *p=(void*)words;unsigned count=0;
 if(t->_write_r(r,1,"FLEXIO01",8)!=8)return 1;
 while(count<16){int n=t->_read_r(r,0,p+count,16-count);if(n<0){if(r->_errno!=EAGAIN)return 2;}else count+=n;}
 words[0]+=9;words[1]^=0xffffffffffffffffULL;if(t->_write_r(r,1,words,16)!=16)return 3;return 0;
}
