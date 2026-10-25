// The Android public HardwareBuffer CPU bridge. No guest pointers or FFI.
#include <stddef.h>
#include <jni.h>
#include <android/hardware_buffer.h>
#include <android/hardware_buffer_jni.h>

static void fail(JNIEnv *env,const char *message) {
    jclass type=(*env)->FindClass(env,"java/io/IOException");
    if(type)(*env)->ThrowNew(env,type,message);
}

JNIEXPORT jbyteArray JNICALL
Java_org_flexscript_collie_HardwareSensorDirect_00024Native_read(
    JNIEnv *env,jclass type,jobject object,jint offset,jint bytes) {
    (void)type;
    if(!object||offset<0||bytes<0||bytes>32768){fail(env,"Invalid hardware-buffer copy bounds.");return NULL;}
    AHardwareBuffer *buffer=AHardwareBuffer_fromHardwareBuffer(env,object);
    if(!buffer){fail(env,"HardwareBuffer is closed or unavailable.");return NULL;}
    AHardwareBuffer_Desc description;
    AHardwareBuffer_describe(buffer,&description);
    if(description.format!=AHARDWAREBUFFER_FORMAT_BLOB||description.height!=1||description.layers!=1||
       (uint32_t)offset>description.width||(uint32_t)bytes>description.width-(uint32_t)offset) {
        fail(env,"HardwareBuffer is not a bounded one-layer sensor blob.");return NULL;
    }
    jbyteArray result=(*env)->NewByteArray(env,bytes);
    if(!result)return NULL;
    void *address=NULL;
    if(AHardwareBuffer_lock(buffer,AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN,-1,NULL,&address)!=0){fail(env,"Android could not lock the sensor HardwareBuffer for CPU reading.");return NULL;}
    if(!address){AHardwareBuffer_unlock(buffer,NULL);fail(env,"Android returned no CPU address for the sensor HardwareBuffer.");return NULL;}
    (*env)->SetByteArrayRegion(env,result,0,bytes,(const jbyte *)address+offset);
    int unlocked=AHardwareBuffer_unlock(buffer,NULL);
    if((*env)->ExceptionCheck(env))return NULL;
    if(unlocked!=0){fail(env,"Android could not unlock the sensor HardwareBuffer.");return NULL;}
    return result;
}
