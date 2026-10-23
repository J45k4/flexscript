/* Emulator-only kernel input fixture. No APK code or physical-device access. */
#include <errno.h>
#include <fcntl.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static void check(int okay,const char *operation){if(!okay){perror(operation);exit(1);}}
static void emit(int fd,int type,int code,int value){struct input_event e={0};e.type=type;e.code=code;e.value=value;check(write(fd,&e,sizeof(e))==(ssize_t)sizeof(e),"write input event");}
int main(int argc,char **argv){
    const char prefix[]="collie-input-fixture-";
    if(argc!=2||strncmp(argv[1],prefix,sizeof(prefix)-1)||strlen(argv[1])>=UINPUT_MAX_NAME_SIZE){fputs("Expected the unique Collie input fixture name\n",stderr);return 2;}
    alarm(120); /* EOF, process death or this deadline closes the kernel device. */
    int fd=open("/dev/uinput",O_WRONLY|O_NONBLOCK|O_CLOEXEC);check(fd>=0,"open emulator uinput");
    check(ioctl(fd,UI_SET_EVBIT,EV_KEY)==0,"enable keys");
    for(int key=KEY_A;key<=KEY_Z;key++)check(ioctl(fd,UI_SET_KEYBIT,key)==0,"enable keyboard key");
    check(ioctl(fd,UI_SET_KEYBIT,KEY_Q)==0,"enable alphabetic keyboard");check(ioctl(fd,UI_SET_KEYBIT,KEY_SPACE)==0,"enable keyboard space");
    check(ioctl(fd,UI_SET_KEYBIT,KEY_F1)==0,"enable F1");
    struct uinput_setup setup={0};setup.id.bustype=BUS_VIRTUAL;setup.id.vendor=0x1234;setup.id.product=0xc011;setup.id.version=1;strcpy(setup.name,argv[1]);
    check(ioctl(fd,UI_DEV_SETUP,&setup)==0,"setup input fixture");check(ioctl(fd,UI_DEV_CREATE)==0,"create input fixture");puts("created");fflush(stdout);
    char command[32];
    while(fgets(command,sizeof(command),stdin)){
        if(!strcmp(command,"key\n")){emit(fd,EV_KEY,KEY_F1,1);emit(fd,EV_SYN,SYN_REPORT,0);emit(fd,EV_KEY,KEY_F1,0);emit(fd,EV_SYN,SYN_REPORT,0);puts("key sent");fflush(stdout);}
        else if(!strcmp(command,"quit\n"))break;
        else{fputs("Unknown fixture command\n",stderr);close(fd);return 2;}
    }
    check(ioctl(fd,UI_DEV_DESTROY)==0,"remove input fixture");close(fd);puts("removed");return 0;
}
