// Debug-only SDK-constructed memory canary. Never packaged in a normal APK.
#include <stddef.h>
#include <jni.h>
#include <android/hardware_buffer.h>
#include <android/hardware_buffer_jni.h>
JNIEXPORT jint JNICALL Java_org_flexscript_collie_HardwareSensorDirectChecks_fill(
    JNIEnv *env,jclass type,jobject object) {
    (void)type;
    AHardwareBuffer *buffer=AHardwareBuffer_fromHardwareBuffer(env,object);
    if(!buffer)return -1;
    AHardwareBuffer_Desc description;AHardwareBuffer_describe(buffer,&description);
    if(description.format!=AHARDWAREBUFFER_FORMAT_BLOB||description.width>425984||description.height!=1||description.layers!=1)return -2;
    void *address=NULL;
    if(AHardwareBuffer_lock(buffer,AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN,-1,NULL,&address)!=0)return -3;
    if(!address){AHardwareBuffer_unlock(buffer,NULL);return -4;}
    for(uint32_t i=0;i<description.width;i++)((volatile unsigned char *)address)[i]=(unsigned char)(i*17+128);
    return AHardwareBuffer_unlock(buffer,NULL);
}
