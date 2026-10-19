#include <stddef.h>
#include <sys/stat.h>
#include <errno.h>
#include "rom-probe-config.h"
#include "rom/libc_stubs.h"
#if ROM_STAT_32
_Static_assert(sizeof(struct stat)==60 && _Alignof(struct stat)==4 && offsetof(struct stat,st_blksize)==44,"C3 ROM time_t32 stat ABI");
#else
_Static_assert(sizeof(struct stat)==88 && _Alignof(struct stat)==8 && offsetof(struct stat,st_blksize)==72,"C6 ROM time_t64 stat ABI");
#endif
extern struct _reent *__getreent(void);
unsigned rom_stat_check(void){
 struct guarded {volatile unsigned before[2];struct stat value;volatile unsigned after[2];} frame;
 for(unsigned i=0;i<2;i++){frame.before[i]=0xa5a5a5a5;frame.after[i]=0x5a5a5a5a;}
 if(syscall_table_ptr->_fstat_r(__getreent(),1,&frame.value) || !S_ISCHR(frame.value.st_mode) || frame.value.st_blksize!=128)return 1;
 for(unsigned i=0;i<2;i++)if(frame.before[i]!=0xa5a5a5a5 || frame.after[i]!=0x5a5a5a5a)return 2;
 errno=0;if(syscall_table_ptr->_fstat_r(__getreent(),99,&frame.value)!=-1 || errno!=EBADF)return 3;
 for(unsigned i=0;i<2;i++)if(frame.before[i]!=0xa5a5a5a5 || frame.after[i]!=0x5a5a5a5a)return 4;
 return 0;
}
