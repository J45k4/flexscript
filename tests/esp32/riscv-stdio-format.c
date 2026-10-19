#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>
#include <sys/reent.h>
extern struct _reent *__getreent(void);
extern int _fstat_r(struct _reent*,int,struct stat*);
extern int _isatty_r(struct _reent*,int);
extern int _write_r(struct _reent*,int,const void*,int);
extern int _lseek_r(struct _reent*,int,int,int);
int stdio_smoke(void){
 struct stat s;if(sizeof(s)!=88 || sizeof(FILE)!=104 || _fstat_r(__getreent(),1,&s) || !S_ISCHR(s.st_mode) || !_isatty_r(__getreent(),1))return 1;
 char text[100];int n=snprintf(text,sizeof text,"value=%d/%llx/%.2f",-17,0x1122334455667788ULL,1.25);
 if(n!=31)return 2;
 if(printf("STDIO: %s\n",text)!=39)return 3;
 if(fflush(stdout))return 4;
 errno=0;if(_write_r(__getreent(),9,text,1)!=-1 || errno!=EBADF)return 5;
 errno=0;if(_lseek_r(__getreent(),1,0,SEEK_SET)!=-1 || errno!=ESPIPE)return 6;
 return 0;
}
