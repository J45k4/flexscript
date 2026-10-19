#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/reent.h>
#include <sys/lock.h>
_Static_assert(ENOSYS==88 && ETIMEDOUT==116 && EAGAIN==11 && ENOMEM==12 && EBADF==9 && EFAULT==14 && EINVAL==22 && ESPIPE==29,"pinned newlib errno ABI");
_Static_assert(offsetof(FILE,_lock)==88 && offsetof(FILE,_flags)==12 && sizeof(((FILE*)0)->_flags)==2,"pinned FILE lock ABI");
_Static_assert(sizeof(FILE)==104 && sizeof(struct _reent)==240 && sizeof(struct __lock)==84,"pinned stdio ABI");
_Static_assert(sizeof(struct stat)==88 && _Alignof(struct stat)==8 && offsetof(struct stat,st_mode)==4 && offsetof(struct stat,st_blksize)==72,"pinned stat ABI");
extern struct _reent *__getreent(void);
extern struct _reent *_global_impure_ptr;
extern unsigned stdio_pause(unsigned,unsigned,unsigned,unsigned,unsigned,unsigned,unsigned,unsigned);
static char private_buffers[2][64];
static unsigned error;
unsigned stdio_prepare(void){
 if(__getreent()!=&_impure_data || _global_impure_ptr!=&_impure_data || !stdin || !stdout || !stderr)return 1;
 FILE *a=fmemopen(private_buffers[0],64,"w"),*b=fmemopen(private_buffers[1],64,"w");if(!a||!b)return 2;if(fclose(a)||fclose(b))return 3;
 if(fputs("STREAMS-BEGIN\n",stdout)<0 || fflush(stdout))return 4;
 return 0;
}
unsigned stdio_worker(unsigned tag){
 struct _reent *r=__getreent();if(r==&_impure_data || r->_stdin!=_global_impure_ptr->_stdin || r->_stdout!=_global_impure_ptr->_stdout || r->_stderr!=_global_impure_ptr->_stderr){error=1;return 0;}
 char prefix[4]={'W','0'+tag,':',0};
 for(unsigned i=0;i<4;i++){
  flockfile(stdout);if(fputs(prefix,stdout)<0)error=2;stdio_pause(tag,i,0,0,0,0,0,0);if(fputs("done\n",stdout)<0)error=3;funlockfile(stdout);
 }
 FILE *file=fmemopen(private_buffers[tag-1],64,"w");if(!file){error=4;return 0;}
 if(setvbuf(file,NULL,_IOFBF,32) || fputs(tag==1?"PRIVATE1":"PRIVATE2",file)<0){error=5;return 0;}
 // The reaper must close this once, flushing the private stream and freeing
 // its buffer/cookie/lock. Its two references deliberately alias.
 r->_stdout=file;r->_stderr=file;return 0;
}
unsigned stdio_check(unsigned final){
 if(error)return 10+error;
 if(final){if(strcmp(private_buffers[0],"PRIVATE1") || strcmp(private_buffers[1],"PRIVATE2"))return 20;
  if(fputs("STREAMS-END\n",stderr)<0 || fflush(stderr))return 21;}
 return 0;
}
unsigned stdio_errors(void){
 struct stat s;char c=0;errno=41;if(fstat(1,&s)||!S_ISCHR(s.st_mode)||s.st_blksize!=128||errno!=41)return 1;
 if(!isatty(0)||!isatty(1)||!isatty(2))return 2;
 errno=0;if(write(9,&c,1)!=-1||errno!=EBADF)return 3;
 errno=0;if(write(0,&c,1)!=-1||errno!=EBADF)return 4;
 errno=0;if(read(1,&c,1)!=-1||errno!=EBADF)return 5;
 errno=0;if(read(0,&c,1)!=-1||errno!=EAGAIN)return 6;
 errno=0;if(lseek(1,0,SEEK_SET)!=-1||errno!=ESPIPE)return 7;
 errno=0;if(isatty(99)!=0||errno!=EBADF)return 8;
 errno=0;if(open("/unsupported",0)!=-1||errno!=ENOSYS)return 9;
 errno=0;if(write(1,NULL,1)!=-1||errno!=EFAULT)return 10;
 errno=0;if(read(0,NULL,1)!=-1||errno!=EFAULT)return 11;
 errno=51;if(write(1,NULL,0)||read(0,NULL,0)||errno!=51)return 12;
 errno=0;if(write(1,&c,0xffffffffu)!=-1||errno!=EINVAL)return 13;
 if(close(0))return 14;errno=0;if(read(0,&c,1)!=-1||errno!=EBADF)return 15;
 errno=0;if(close(0)!=-1||errno!=EBADF)return 16;
 return 0;
}
unsigned stdio_redirect_global(unsigned unused){
 struct _reent *r=__getreent();r->_stdout=_global_impure_ptr->_stderr;return 0;
}
unsigned stdio_static_locks(void){
 extern struct __lock __lock___sinit_recursive_mutex,__lock___malloc_recursive_mutex,__lock___env_recursive_mutex,__lock___sfp_recursive_mutex,__lock___atexit_recursive_mutex;
 extern struct __lock __lock___at_quick_exit_mutex,__lock___tz_mutex,__lock___dd_hash_mutex,__lock___arc4random_mutex;
 struct __lock *locks[]={&__lock___sinit_recursive_mutex,&__lock___malloc_recursive_mutex,&__lock___env_recursive_mutex,&__lock___sfp_recursive_mutex,&__lock___atexit_recursive_mutex,&__lock___at_quick_exit_mutex,&__lock___tz_mutex,&__lock___dd_hash_mutex,&__lock___arc4random_mutex};
 for(unsigned i=0;i<9;i++){
  if(i<5){if(__retarget_lock_try_acquire_recursive(locks[i]) || __retarget_lock_try_acquire_recursive(locks[i]))return 1;__retarget_lock_release_recursive(locks[i]);__retarget_lock_release_recursive(locks[i]);}
  else{if(__retarget_lock_try_acquire(locks[i]) || __retarget_lock_try_acquire(locks[i])!=-1)return 2;__retarget_lock_release(locks[i]);}
  for(unsigned j=0;j<84;j++)if(((unsigned char*)locks[i])[j])return 3;
 }
 return 0;
}
unsigned stdio_peer(void){
 unsigned long long words[2];unsigned char *p=(void*)words;unsigned count=0;fwrite("FLEXIO01",1,8,stdout);fflush(stdout);
 while(count<16){unsigned n=fread(p+count,1,16-count,stdin);count+=n;if(ferror(stdin)){if(errno!=EAGAIN)return 1;clearerr(stdin);}}
 words[0]+=9;words[1]^=0xffffffffffffffffULL;
 if(fwrite(words,1,16,stdout)!=16 || fflush(stdout))return 2;return 0;
}
unsigned stdio_budget_probe(unsigned mode){
 char bytes[64];memset(bytes,'x',sizeof bytes);errno=37;int result=write(1,bytes,sizeof bytes);
 if(mode==0)return result==-1 && errno==ETIMEDOUT?0:1;
 if(result>0 && result<sizeof bytes && errno==37)return 1;
 if(result==sizeof bytes && errno==37)return 2;
 if(result==-1 && errno==ETIMEDOUT)return 0;
 return 3;
}
unsigned stdio_bad(unsigned mode,unsigned pointer){
 extern struct __lock __lock___sfp_recursive_mutex;
 if(mode==0)__retarget_lock_close_recursive(&__lock___sfp_recursive_mutex);
 else if(mode==1)__retarget_lock_acquire(&__lock___sfp_recursive_mutex);
 else if(mode==2)flockfile((FILE*)pointer);
 else if(mode==3)ftrylockfile(stdout);
 else if(mode==4)fputs("bad",stdout);
 else if(mode==5)write(1,"bad",3);
 else if(mode==6)abort();
 return 99;
}
