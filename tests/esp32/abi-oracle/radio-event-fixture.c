/* Independent windowed C event producer/observer, never production code. */
#include <stdint.h>
typedef uint32_t (*callback_t)(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
volatile uint32_t radio_event_peer[32];
volatile uint32_t radio_event_log[256];
uint32_t radio_event_emit(uint32_t adapter,uint32_t id,uint32_t marker,uint32_t size,uint32_t null_data) {
 volatile uint32_t packet[4]={marker,id,0x13572468,0x24681357};
 radio_event_peer[3]++;uint32_t result=((callback_t)(uintptr_t)radio_event_peer[adapter?1:0])(0,id,null_data?0:(uint32_t)(uintptr_t)packet,size,0,0,0,0);
 if(packet[0]!=marker || packet[1]!=id || packet[2]!=0x13572468 || packet[3]!=0x24681357)radio_event_peer[2]|=2;
 return result;
}
uint32_t radio_event_observe(uint32_t id,const uint8_t *data,uint32_t size) {
 uint32_t ps;__asm__ volatile("rsr.ps %0":"=a"(ps));if(!(ps&15))radio_event_peer[2]|=1;
 uint32_t at=radio_event_peer[4]++,marker=0;if(at>=64){radio_event_peer[2]|=4;return 1;}
 if(data && size>=4)for(unsigned i=0;i<4;i++)marker|=(uint32_t)data[i]<<(i*8);
 if(data && size>=8){uint32_t tag=0;for(unsigned i=0;i<4;i++)tag|=(uint32_t)data[i+4]<<(i*8);if(tag!=id)radio_event_peer[2]|=8;}
 radio_event_log[at*4]=id;radio_event_log[at*4+1]=marker;radio_event_log[at*4+2]=size;radio_event_log[at*4+3]=ps&15;return 0;
}
