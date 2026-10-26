// Native state-machine fixtures, never a USB driver/device or physical-I/O oracle.
#define _GNU_SOURCE
#include <assert.h>
#include <dirent.h>
#include <stdio.h>
#include <sys/types.h>
#include <poll.h>
#include <sched.h>
#include <stdatomic.h>
static int fixture_ioctl(int,unsigned long,void *);
static int fixture_poll(struct pollfd *,nfds_t,int);
#define COLLIE_USB_ISO_TEST
#define ISO_IOCTL fixture_ioctl
#define ISO_POLL fixture_poll
#include "../../android/usb-iso.c"

enum {SUCCESS,PARTIAL,PENDING,SUBMIT_ERROR,SPURIOUS,DISCONNECT,MALFORMED,NO_COMPLETION,LATE_COMPLETE};
static int mode,reaps,discards,checks;
static _Atomic int submits;
static struct usbdevfs_urb *submitted;
static int fixture_ioctl(int fd,unsigned long op,void *arg){
    (void)fd;
    if(op==USBDEVFS_SUBMITURB){submits++;if(mode==SUBMIT_ERROR){errno=EPIPE;return -1;}submitted=arg;return 0;}
    if(op==USBDEVFS_DISCARDURB){discards++;return 0;}
    assert(op==USBDEVFS_REAPURBNDELAY);reaps++;
    if(mode==LATE_COMPLETE){struct timespec pause={0,200000000};nanosleep(&pause,NULL);}
    if(mode==DISCONNECT){errno=ENODEV;return -1;}
    if(mode==SPURIOUS){*(void **)arg=&mode;return 0;}
    if(mode==NO_COMPLETION||(mode==PENDING&&!discards)){errno=EAGAIN;return -1;}
    assert(submitted);struct usbdevfs_urb *u=submitted;u->start_frame=2147483646;u->status=discards?-ENOENT:0;u->error_count=mode==PARTIAL?1:0;
    unsigned offset=0;for(int i=0;i<u->number_of_packets;i++){unsigned size=u->iso_frame_desc[i].length;u->iso_frame_desc[i].actual_length=discards?0:mode==PARTIAL?(i==0?3:i==1?0:1):size;u->iso_frame_desc[i].status=discards?(unsigned)-ECONNRESET:mode==PARTIAL&&i==1?(unsigned)-EXDEV:0;if(u->endpoint&128)for(unsigned j=0;j<size;j++)((unsigned char *)u->buffer)[offset+j]=(unsigned char)(offset+j+128);offset+=size;}
    if(mode==MALFORMED)u->iso_frame_desc[0].actual_length=u->iso_frame_desc[0].length+1;
    *(void **)arg=u;return 0;
}
static int fixture_poll(struct pollfd *p,nfds_t count,int timeout){assert(count==2);(void)timeout;struct timespec t={0,1000000};nanosleep(&t,NULL);p[0].revents=0;p[1].revents=0;return poll(p+1,1,0);}
static void reset(int m){mode=m;submits=reaps=discards=0;submitted=NULL;}
static uint32_t word(const unsigned char *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void pass(const char *text){printf("PASS %s\n",text);checks++;}
static int fd_count(void){DIR *d=opendir("/proc/self/fd");assert(d);int n=0;while(readdir(d))n++;closedir(d);return n;}
static uint64_t make(int fd,int ep,const int *sizes,int n,const unsigned char *data,int bytes){int error=0;uint64_t id=iso_create(fd,ep,sizes,n,data,bytes,&error);assert(id&&error==0);return id;}
static void *run_pending(void *arg){assert(iso_run(*(uint64_t *)arg,iso_now()+3000000000ULL)==0);return NULL;}
int main(void){
    int before=fd_count(),fd=open("/dev/null",O_RDWR|O_CLOEXEC);assert(fd>=0);int sizes[3]={3,5,4};unsigned char frame[26688],out[12];for(int i=0;i<12;i++)out[i]=(unsigned char)i;
    reset(PARTIAL);uint64_t id=make(fd,129,sizes,3,NULL,0);assert(iso_run(id,iso_now()+1000000000ULL)==0);int n=iso_frame(id,frame,sizeof(frame));assert(n==124&&submits==1&&reaps==1&&discards==0);assert(word(frame+12)==19&&word(frame+24)==0&&word(frame+28)==1&&word(frame+40)==4);assert(word(frame+64+4)==3&&word(frame+80+8)==(uint32_t)-EXDEV&&word(frame+96+4)==1);assert(frame[112]==128&&frame[114]==130&&frame[115]==0&&frame[120]==136&&frame[121]==0);assert(iso_finished(id)&&!iso_retire_required(id));assert(iso_destroy(id,0)==0);assert(iso_frame(id,frame,sizeof(frame))==-EINVAL);pass("partial input preserves actual packet statuses, holes and exact lengths without exposing untransferred native buffer bytes");
    reset(SUCCESS);id=make(fd,1,sizes,3,out,12);out[0]=99;assert(iso_run(id,iso_now()+1000000000ULL)==0);assert(((unsigned char *)submitted->buffer)[0]==0);assert(iso_frame(id,frame,sizeof(frame))==124&&word(frame+40)==12&&frame[112]==0);assert(iso_destroy(id,0)==0);pass("output is an owned snapshot; completion is distinct from caller-side buffer mutation");
    reset(SUBMIT_ERROR);id=make(fd,129,sizes,3,NULL,0);assert(iso_run(id,iso_now()+1000000000ULL)==0);assert(iso_frame(id,frame,sizeof(frame))==124&&word(frame+16)==EPIPE&&!(word(frame+12)&3)&&word(frame+40)==0&&submits==1&&!reaps&&!discards);assert(iso_destroy(id,0)==0);pass("actual submission error is not replayed and never creates a reaped/successful packet result");
    reset(SUCCESS);id=make(fd,129,sizes,3,NULL,0);assert(iso_cancel(id));assert(iso_run(id,iso_now()+1000000000ULL)==0);assert(iso_frame(id,frame,sizeof(frame))==124&&(word(frame+12)&7)==4&&!submits);assert(iso_destroy(id,0)==0);pass("cancel-before-start suppresses submission and still settles the reserved native request");
    reset(SUCCESS);id=make(fd,129,sizes,3,NULL,0);assert(iso_run(id,iso_now()-1)==0);assert(iso_frame(id,frame,sizeof(frame))==124&&(word(frame+12)&11)==8&&!submits);assert(iso_destroy(id,0)==0);pass("expired queued work performs no USB ioctl mutation");
    reset(LATE_COMPLETE);id=make(fd,129,sizes,3,NULL,0);assert(iso_run(id,iso_now()+100000000ULL)==0);assert(iso_frame(id,frame,sizeof(frame))==124&&(word(frame+12)&11)==11&&word(frame+40)==12&&word(frame+20)==0&&!discards);assert(iso_destroy(id,0)==0);pass("a reap returning after its wall deadline preserves real successful data and expiry without inventing a cancellation");
    reset(PENDING);id=make(fd,129,sizes,3,NULL,0);assert(iso_run(id,iso_now()+5000000ULL)==0);assert(iso_frame(id,frame,sizeof(frame))==124&&(word(frame+12)&11)==11&&submits==1&&discards==1&&word(frame+40)==0);assert(iso_destroy(id,0)==0);pass("wall timeout discards once and reaps the actual cancelled URB before freeing its buffers");
    reset(PENDING);id=make(fd,129,sizes,3,NULL,0);pthread_t thread;assert(pthread_create(&thread,NULL,run_pending,&id)==0);uint64_t ready=iso_now()+1000000000ULL;while(!atomic_load(&submits)&&iso_now()<ready)sched_yield();assert(atomic_load(&submits)==1);assert(iso_destroy(id,1)==EBUSY);assert(iso_cancel(id));assert(pthread_join(thread,NULL)==0);assert(iso_frame(id,frame,sizeof(frame))==124&&(word(frame+12)&7)==7&&discards==1);assert(iso_destroy(id,0)==0);pass("concurrent cancellation wakes a running worker while early destroy cannot free active URB memory");
    reset(NO_COMPLETION);id=make(fd,129,sizes,3,NULL,0);assert(iso_run(id,iso_now()+2000000ULL)==0);assert(iso_frame(id,frame,sizeof(frame))==124&&word(frame+60)==1&&(word(frame+12)&11)==9&&discards==1);assert(iso_destroy(id,0)==EBUSY);assert(iso_destroy(id,1)==0);pass("a missing cancellation completion keeps cleanup required until the SDK connection is retired; it is never a fabricated reap");
    for(int m=SPURIOUS;m<=DISCONNECT;m++){reset(m);id=make(fd,129,sizes,3,NULL,0);assert(iso_run(id,iso_now()+1000000000ULL)==0);assert(iso_retire_required(id)&&iso_destroy(id,0)==EBUSY);assert(iso_frame(id,frame,sizeof(frame))==124&&word(frame+60)==1&&!(word(frame+12)&2)&&word(frame+40)==0);assert(iso_destroy(id,1)==0);}pass("foreign completion and disconnect require SDK connection retirement before native duplicate teardown");
    reset(MALFORMED);id=make(fd,129,sizes,3,NULL,0);assert(iso_run(id,iso_now()+1000000000ULL)==0);assert(iso_frame(id,frame,sizeof(frame))==-EINVAL);assert(iso_destroy(id,0)==0);pass("an impossible kernel packet length fails before any out-of-bounds copy or fabricated result frame");
    int maximum[128];for(int i=0;i<128;i++)maximum[i]=192;reset(SUCCESS);id=make(fd,129,maximum,128,NULL,0);assert(iso_run(id,iso_now()+1000000000ULL)==0);assert(iso_frame(id,frame,sizeof(frame))==26688&&word(frame+40)==24576);assert(iso_frame(id,frame,26687)==-ENOSPC);assert(iso_destroy(id,0)==0);pass("all128 packets and24576 payload bytes fit the declared result bound, with no truncation");
    uint64_t ids[8];for(int i=0;i<8;i++)ids[i]=make(fd,129,sizes,3,NULL,0);int error;assert(!iso_create(fd,129,sizes,3,NULL,0,&error)&&error==EBUSY);for(int i=0;i<8;i++)assert(iso_destroy(ids[i],0)==0);assert(iso_run(ids[0],iso_now())==EINVAL);pass("native capacity counts pending contexts, releases exactly once and rejects stale opaque identities");
    int bad[1]={24577};assert(!iso_create(fd,129,bad,1,NULL,0,&error)&&error==EINVAL);assert(!iso_create(fd,0,sizes,3,NULL,0,&error)&&error==EINVAL);assert(!iso_create(fd,129,sizes,0,NULL,0,&error)&&error==EINVAL);assert(!iso_create(fd,129,sizes,3,out,1,&error)&&error==EINVAL);assert(!iso_create(fd,1,sizes,3,out,11,&error)&&error==EINVAL);pass("endpoint, count, input/output and payload bounds fail before fd duplication or USB submission");
    close(fd);assert(fd_count()==before);pass("all native owned duplicates and cancellation pipes return to the independent descriptor baseline");printf("%d native USB ISO fixture checks passed; no physical USB I/O asserted\n",checks);return 0;
}
