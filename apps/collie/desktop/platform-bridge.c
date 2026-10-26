/* One private socket per engine operation. Payloads never enter shell commands
 * or stdout; the desktop platform service supplies TLS/images/device adapters. */
static int cd_transfer(int fd,void *bytes,long n,int writing) {
    char *p=bytes;
    while(n>0){long r=writing?write(fd,p,n):read(fd,p,n);
        if(r<0 && errno==EINTR)continue;
        if(r<=0)return 0;
        p+=r;n-=r;}
    return 1;
}
static long java_bytes(const char *method_name,long data,long size) {
    java_result_n=-1;
    const char *setting=getenv("COLLIE_PLATFORM_FD");
    if(!setting || size<0 || size>2097152)
        return (long)"{\"error\":\"Desktop platform service is unavailable.\"}";
    int fd=atoi(setting);long header[2]={length(method_name),size};long n;
    long started=now();
    if(!cd_transfer(fd,header,16,1) || !cd_transfer(fd,(void*)method_name,header[0],1) ||
       !cd_transfer(fd,(void*)data,size,1) || !cd_transfer(fd,&n,8,0) || n<0 || n>2097152)
        return (long)"{\"error\":\"Desktop platform bridge failed.\"}";
    char *result=(char*)small_allocate(n+1);
    if(!cd_transfer(fd,result,n,0))return (long)"{\"error\":\"Desktop platform bridge closed.\"}";
    result[n]=0;java_result_n=n;deadline+=now()-started;tick();return (long)result;
}
