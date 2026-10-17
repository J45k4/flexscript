#include <stdint.h>
#include <stddef.h>
#include "esp_rom_lldesc.h"
struct record {uint32_t size,used,next,eof;lldesc_t descriptor;};
#define D(s,u,n,e) {s,u,n,e,{.size=s,.length=u,.eof=e,.owner=1,.buf=(const uint8_t*)0x3ffb2000,.qe={.stqe_next=(lldesc_t*)n}}}
__attribute__((section(".reference"),used)) const struct {uint32_t size,buf,next,record_size;struct record cases[12];} oracle={sizeof(lldesc_t),offsetof(lldesc_t,buf),offsetof(lldesc_t,qe),sizeof(struct record),{
 D(1,0,0,0),D(1,1,0,1),D(4,4,0,1),D(16,0,0,1),D(32,16,0,1),D(256,256,0,1),D(4092,4092,0,1),D(4092,0,0,0),D(64,64,0x3ffb1000,0),D(128,0,0x3ffdfff0,1),D(2048,1024,0,0),D(4092,2047,0x3ffb1000,1)}};
