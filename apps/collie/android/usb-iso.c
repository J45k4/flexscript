// Trusted USBFS ISO transport for a consented SDK connection. No guest fd/pointer ABI.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/usbdevice_fs.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>
#ifndef COLLIE_USB_ISO_TEST
#include <jni.h>
#endif

#define ISO_SLOTS 8
#define ISO_PACKETS 128
#define ISO_BYTES 24576
#ifndef ISO_IOCTL
#define ISO_IOCTL ioctl
#endif
#ifndef ISO_POLL
#define ISO_POLL poll
#endif

typedef struct Iso {
    uint64_t id, elapsed;
    int fd,wake[2],count,total,endpoint;
    int active,finished,closing,cancelled,timedout,submitted,reaped,cleanup,io_error,invalid;
    unsigned lengths[ISO_PACKETS];
    struct usbdevfs_urb *urb;
    unsigned char *data;
} Iso;
static pthread_mutex_t iso_mutex=PTHREAD_MUTEX_INITIALIZER;
static Iso *iso_slots[ISO_SLOTS];
static uint64_t iso_sequence;

static uint64_t iso_now(void){struct timespec t;if(clock_gettime(CLOCK_BOOTTIME,&t)!=0)return 0;return (uint64_t)t.tv_sec*1000000000ULL+(uint64_t)t.tv_nsec;}
static Iso *iso_find(uint64_t id){for(int i=0;i<ISO_SLOTS;i++)if(iso_slots[i]&&iso_slots[i]->id==id)return iso_slots[i];return NULL;}
static int iso_cancel(uint64_t id){int result=0;pthread_mutex_lock(&iso_mutex);Iso *s=iso_find(id);if(s&&!s->finished&&!s->closing){s->cancelled=1;unsigned char byte=1;if(s->wake[1]>=0)(void)write(s->wake[1],&byte,1);result=1;}pthread_mutex_unlock(&iso_mutex);return result;}
static int iso_cancelled(Iso *s){pthread_mutex_lock(&iso_mutex);int result=s->cancelled;pthread_mutex_unlock(&iso_mutex);return result;}
static void iso_forget(Iso *s){pthread_mutex_lock(&iso_mutex);for(int i=0;i<ISO_SLOTS;i++)if(iso_slots[i]==s)iso_slots[i]=NULL;pthread_mutex_unlock(&iso_mutex);}
static void iso_free(Iso *s){if(s->fd>=0)close(s->fd);if(s->wake[0]>=0)close(s->wake[0]);if(s->wake[1]>=0)close(s->wake[1]);iso_forget(s);free(s->urb);free(s->data);free(s);}

static uint64_t iso_create(int fd,int endpoint,const int *lengths,int count,const unsigned char *data,int bytes,int *error){
    *error=EINVAL;if(fd<0||endpoint<1||endpoint>255||(endpoint&0x70)||(endpoint&15)==0||count<1||count>ISO_PACKETS)return 0;
    int total=0;for(int i=0;i<count;i++){if(lengths[i]<1||lengths[i]>16384||lengths[i]>ISO_BYTES-total)return 0;total+=lengths[i];}
    if((endpoint&128)?bytes!=0:bytes!=total)return 0;
    Iso *s=calloc(1,sizeof(*s));if(!s){*error=ENOMEM;return 0;}s->fd=s->wake[0]=s->wake[1]=-1;
    pthread_mutex_lock(&iso_mutex);int slot=-1;for(int i=0;i<ISO_SLOTS;i++)if(!iso_slots[i]){slot=i;break;}
    if(slot<0||iso_sequence>=INT64_MAX){pthread_mutex_unlock(&iso_mutex);free(s);*error=slot<0?EBUSY:EOVERFLOW;return 0;}s->id=++iso_sequence;iso_slots[slot]=s;pthread_mutex_unlock(&iso_mutex);
    s->count=count;s->total=total;s->endpoint=endpoint;s->urb=calloc(1,sizeof(*s->urb)+(size_t)count*sizeof(s->urb->iso_frame_desc[0]));s->data=calloc(1,(size_t)total);
    if(!s->urb||!s->data){*error=ENOMEM;iso_free(s);return 0;}
    s->fd=fcntl(fd,F_DUPFD_CLOEXEC,0);if(s->fd<0){*error=errno;iso_free(s);return 0;}
    if(pipe2(s->wake,O_CLOEXEC|O_NONBLOCK)<0){*error=errno;iso_free(s);return 0;}
    if(bytes)memcpy(s->data,data,(size_t)bytes);
    s->urb->type=USBDEVFS_URB_TYPE_ISO;s->urb->endpoint=(unsigned char)endpoint;s->urb->flags=USBDEVFS_URB_ISO_ASAP;s->urb->buffer=s->data;s->urb->buffer_length=total;s->urb->number_of_packets=count;s->urb->status=-EINPROGRESS;
    for(int i=0;i<count;i++){s->lengths[i]=(unsigned)lengths[i];s->urb->iso_frame_desc[i].length=(unsigned)lengths[i];s->urb->iso_frame_desc[i].status=(unsigned)-EINPROGRESS;}
    *error=0;return s->id;
}

static int iso_run(uint64_t id,uint64_t deadline){
    pthread_mutex_lock(&iso_mutex);Iso *s=iso_find(id);if(!s||s->active||s->finished||s->closing){pthread_mutex_unlock(&iso_mutex);return EINVAL;}s->active=1;pthread_mutex_unlock(&iso_mutex);
    uint64_t began=iso_now(),grace=0;int discarded=0;
    if(!began){s->io_error=EIO;goto done;}
    if(began>=deadline){s->timedout=1;goto done;}
    if(iso_cancelled(s))goto done;
    if(ISO_IOCTL(s->fd,USBDEVFS_SUBMITURB,s->urb)<0){s->io_error=errno;goto done;}s->submitted=1;
    while(!s->reaped){
        uint64_t now=iso_now();if(!now){s->io_error=EIO;s->cleanup=1;break;}if(now>=deadline)s->timedout=1;
        if((s->timedout||iso_cancelled(s))&&!discarded){
            discarded=1;grace=now+1000000000ULL;
            if(ISO_IOCTL(s->fd,USBDEVFS_DISCARDURB,s->urb)<0&&errno!=EINVAL&&errno!=ENODEV&&!s->io_error)s->io_error=errno;
        }
        void *completed=NULL;
        if(ISO_IOCTL(s->fd,USBDEVFS_REAPURBNDELAY,&completed)==0){if(completed!=s->urb){s->io_error=EPROTO;s->cleanup=1;break;}s->reaped=1;break;}
        if(errno!=EAGAIN&&errno!=EINTR){if(!s->io_error)s->io_error=errno;s->cleanup=1;break;}
        if(grace&&now>=grace){s->cleanup=1;break;}
        uint64_t until=grace?grace:deadline;int wait=until>now?(int)((until-now+999999ULL)/1000000ULL):0;if(wait>100)wait=100;
        struct pollfd p[2]={{s->fd,POLLOUT|POLLERR|POLLHUP,0},{s->wake[0],POLLIN,0}};
        if(ISO_POLL(p,2,wait)<0&&errno!=EINTR){if(!s->io_error)s->io_error=errno;s->cleanup=1;break;}
        if(p[1].revents&POLLIN){unsigned char buffer[64];while(read(s->wake[0],buffer,sizeof(buffer))>0){}}
    }
done:
    {uint64_t end=iso_now();s->elapsed=end>=began?end-began:0;if(!end&&!s->io_error)s->io_error=EIO;if(end&&end>=deadline)s->timedout=1;}
    if(s->submitted&&!s->reaped)s->cleanup=1;
    if(s->reaped){
        if(s->urb->number_of_packets!=s->count||s->urb->buffer_length!=s->total||s->urb->error_count<0||s->urb->error_count>s->count)s->invalid=1;
        for(int i=0;i<s->count;i++)if(s->urb->iso_frame_desc[i].actual_length>s->lengths[i])s->invalid=1;
    }
    pthread_mutex_lock(&iso_mutex);s->active=0;s->finished=1;pthread_mutex_unlock(&iso_mutex);return 0;
}

static int iso_retire_required(uint64_t id){pthread_mutex_lock(&iso_mutex);Iso *s=iso_find(id);int result=s&&(s->cleanup||s->active);pthread_mutex_unlock(&iso_mutex);return result;}
static int iso_finished(uint64_t id){pthread_mutex_lock(&iso_mutex);Iso *s=iso_find(id);int result=!s||s->finished;pthread_mutex_unlock(&iso_mutex);return result;}
// The caller must first close the SDK connection if any submitted URB is unreaped.
// Closing the last duplicate synchronously tears down usbfs URBs before buffers are freed.
static int iso_destroy(uint64_t id,int sdk_closed){
    pthread_mutex_lock(&iso_mutex);Iso *s=iso_find(id);if(!s){pthread_mutex_unlock(&iso_mutex);return 0;}
    if(s->active||s->closing||(s->submitted&&!s->reaped&&!sdk_closed)){pthread_mutex_unlock(&iso_mutex);return EBUSY;}s->closing=1;pthread_mutex_unlock(&iso_mutex);iso_free(s);return 0;
}
static void iso_put32(unsigned char *p,uint32_t n){for(int i=0;i<4;i++)p[i]=(unsigned char)(n>>(i*8));}
static int iso_frame(uint64_t id,unsigned char *out,int capacity){
    pthread_mutex_lock(&iso_mutex);Iso *s=iso_find(id);if(!s||!s->finished||s->active||s->closing||s->invalid){pthread_mutex_unlock(&iso_mutex);return -EINVAL;}
    int size=64+s->count*16+s->total;if(capacity<size){pthread_mutex_unlock(&iso_mutex);return -ENOSPC;}memset(out,0,(size_t)size);memcpy(out,"COLLISO1",8);iso_put32(out+8,1);
    iso_put32(out+12,(s->submitted?1:0)|(s->reaped?2:0)|(s->cancelled?4:0)|(s->timedout?8:0)|((s->endpoint&128)?16:0));
    iso_put32(out+16,(uint32_t)s->io_error);iso_put32(out+20,(uint32_t)s->urb->status);iso_put32(out+24,0); /* ISO_ASAP input; usbfs reap does not copy the actual start frame. */iso_put32(out+28,s->reaped?(uint32_t)s->urb->error_count:0);iso_put32(out+32,(uint32_t)s->count);iso_put32(out+36,(uint32_t)s->total);iso_put32(out+44,(uint32_t)s->total);iso_put32(out+48,(uint32_t)s->elapsed);iso_put32(out+52,(uint32_t)(s->elapsed>>32));iso_put32(out+56,1);iso_put32(out+60,(uint32_t)s->cleanup);
    unsigned offset=0,total=0;
    for(int i=0;i<s->count;i++){unsigned char *p=out+64+i*16;unsigned actual=s->reaped?s->urb->iso_frame_desc[i].actual_length:0;iso_put32(p,s->lengths[i]);iso_put32(p+4,actual);iso_put32(p+8,s->reaped?s->urb->iso_frame_desc[i].status:(uint32_t)-EINPROGRESS);iso_put32(p+12,offset);if(actual)memcpy(out+64+s->count*16+offset,s->data+offset,actual);offset+=s->lengths[i];total+=actual;}
    iso_put32(out+40,total);pthread_mutex_unlock(&iso_mutex);return size;
}

#ifndef COLLIE_USB_ISO_TEST
static void iso_throw(JNIEnv *env,int error){jclass cls=(*env)->FindClass(env,"java/io/IOException");if(cls){char text[96];const char *prefix="USB ISO native error ";size_t n=strlen(prefix);memcpy(text,prefix,n);unsigned value=(unsigned)(error<0?-error:error);char digits[16];int count=0;do{digits[count++]=(char)('0'+value%10);value/=10;}while(value);while(count)text[n++]=digits[--count];text[n]=0;(*env)->ThrowNew(env,cls,text);}}
JNIEXPORT jlong JNICALL Java_org_flexscript_collie_HardwareUsbIso_00024Native_create(JNIEnv *env,jclass cls,jint fd,jint endpoint,jintArray packets,jbyteArray data){
    (void)cls;if(!packets||!data){iso_throw(env,EINVAL);return 0;}int n=(*env)->GetArrayLength(env,packets),bytes=(*env)->GetArrayLength(env,data);if(n<1||n>ISO_PACKETS||bytes>ISO_BYTES){iso_throw(env,EINVAL);return 0;}int lengths[ISO_PACKETS];unsigned char buffer[ISO_BYTES];(*env)->GetIntArrayRegion(env,packets,0,n,lengths);if(bytes)(*env)->GetByteArrayRegion(env,data,0,bytes,(jbyte *)buffer);if((*env)->ExceptionCheck(env))return 0;int error;uint64_t id=iso_create(fd,endpoint,lengths,n,buffer,bytes,&error);if(!id)iso_throw(env,error);return (jlong)id;
}
JNIEXPORT jbyteArray JNICALL Java_org_flexscript_collie_HardwareUsbIso_00024Native_run(JNIEnv *env,jclass cls,jlong id,jlong deadline){
    (void)cls;int error=iso_run((uint64_t)id,(uint64_t)deadline);if(error){iso_throw(env,error);return NULL;}unsigned char buffer[64+ISO_PACKETS*16+ISO_BYTES];int n=iso_frame((uint64_t)id,buffer,sizeof(buffer));if(n<0){iso_throw(env,n);return NULL;}jbyteArray out=(*env)->NewByteArray(env,n);if(out)(*env)->SetByteArrayRegion(env,out,0,n,(const jbyte *)buffer);return out;
}
JNIEXPORT void JNICALL Java_org_flexscript_collie_HardwareUsbIso_00024Native_cancel(JNIEnv *env,jclass cls,jlong id){(void)env;(void)cls;(void)iso_cancel((uint64_t)id);}
JNIEXPORT jboolean JNICALL Java_org_flexscript_collie_HardwareUsbIso_00024Native_retireRequired(JNIEnv *env,jclass cls,jlong id){(void)env;(void)cls;return iso_retire_required((uint64_t)id)?JNI_TRUE:JNI_FALSE;}
JNIEXPORT jboolean JNICALL Java_org_flexscript_collie_HardwareUsbIso_00024Native_runFinished(JNIEnv *env,jclass cls,jlong id){(void)env;(void)cls;return iso_finished((uint64_t)id)?JNI_TRUE:JNI_FALSE;}
JNIEXPORT void JNICALL Java_org_flexscript_collie_HardwareUsbIso_00024Native_destroy(JNIEnv *env,jclass cls,jlong id,jboolean sdk_closed){(void)cls;int error=iso_destroy((uint64_t)id,sdk_closed);if(error)iso_throw(env,error);}
#endif
