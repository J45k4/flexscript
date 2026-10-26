/* Linux adapter for the shared bounded broker. Its raw() arguments use the
 * Android AArch64 syscall numbers; Flexscript's host ABI remains x86-64. */
#define _GNU_SOURCE
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <setjmp.h>
#include <stdint.h>
#include <sys/stat.h>
#include <string.h>
#include <fcntl.h>
static jmp_buf checkpoint;
#define ca_checkpoint(p) setjmp(p)
#define ca_abort(p) longjmp(p, 1)
typedef long (*engine_fn)(long,long,long,long,long,long);
static engine_fn entry_fn, frame_fn, wire_fn, cleanup_fn;
#define collie_android_entry(a,b,c,d) entry_fn(a,b,c,d,0,0)
#define collie_android_db_frame(a,b) frame_fn(a,b,0,0,0,0)
#define collie_android_db_wire() wire_fn(0,0,0,0,0,0)
#define collie_android_cleanup() cleanup_fn(0,0,0,0,0,0)
long cd_bind(long entry,long frame,long wire,long cleanup,long unused1,long unused2) {
    (void)unused1;(void)unused2;
    entry_fn=(engine_fn)entry;frame_fn=(engine_fn)frame;
    wire_fn=(engine_fn)wire;cleanup_fn=(engine_fn)cleanup;return 0;
}
static long raw(long n,long a,long b,long c,long d,long e,long f) {
    long number;
    if(n==80){
        struct stat st;if(fstat((int)a,&st)<0)return -errno;
        unsigned char *p=(void*)b;memset(p,0,128);
        *(uint64_t*)(p+0)=st.st_dev;*(uint64_t*)(p+8)=st.st_ino;
        *(uint32_t*)(p+16)=st.st_mode;*(uint32_t*)(p+20)=st.st_nlink;
        *(uint32_t*)(p+24)=st.st_uid;*(uint32_t*)(p+28)=st.st_gid;
        *(uint64_t*)(p+32)=st.st_rdev;*(int64_t*)(p+48)=st.st_size;
        *(int32_t*)(p+56)=st.st_blksize;*(int64_t*)(p+64)=st.st_blocks;
        *(int64_t*)(p+72)=st.st_atim.tv_sec;*(int64_t*)(p+80)=st.st_atim.tv_nsec;
        *(int64_t*)(p+88)=st.st_mtim.tv_sec;*(int64_t*)(p+96)=st.st_mtim.tv_nsec;
        *(int64_t*)(p+104)=st.st_ctim.tv_sec;*(int64_t*)(p+112)=st.st_ctim.tv_nsec;
        return 0;
    }
    if(n==56)c=(c&~0x3c000L)|((c&0x4000)?0x10000:0)|((c&0x8000)?0x20000:0)|((c&0x10000)?0x4000:0)|((c&0x20000)?0x8000:0);
    switch(n) {
    case 25:number=SYS_fcntl;break;case 32:number=SYS_flock;break;
    case 34:number=SYS_mkdirat;break;case 35:number=SYS_unlinkat;break;
    case 38:number=SYS_renameat;break;case 46:number=SYS_ftruncate;break;
    case 52:number=SYS_fchmod;break;case 56:number=SYS_openat;break;
    case 57:number=SYS_close;break;case 61:number=SYS_getdents64;break;
    case 62:number=SYS_lseek;break;case 63:number=SYS_read;break;
    case 64:number=SYS_write;break;case 67:number=SYS_pread64;break;
    case 68:number=SYS_pwrite64;break;case 80:number=SYS_fstat;break;
    case 82:number=SYS_fsync;break;case 113:number=SYS_clock_gettime;break;
    case 172:number=SYS_getpid;break;case 215:number=SYS_munmap;break;
    case 222:number=SYS_mmap;break;case 278:number=SYS_getrandom;break;
    case 437:number=SYS_openat2;break;
    default:return -ENOSYS;
    }
    long r=syscall(number,a,b,c,d,e,f);return r==-1?-errno:r;
}
static long cd_workspace_root(const char *fallback) {
    const char *setting = getenv("COLLIE_WORKSPACE_FD");
    if (!setting) return raw(56, -100, (long)fallback, 0x4000 | 0x8000, 0, 0, 0);
    int fd = fcntl(atoi(setting), F_DUPFD_CLOEXEC, 3);
    return fd < 0 ? -errno : fd;
}
