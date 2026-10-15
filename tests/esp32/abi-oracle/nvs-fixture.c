/* Independent windowed-C OSI-v9 NVS oracle, not production firmware. */
#include <stdint.h>
#include <stddef.h>
struct nvs_slots {
 int (*set_i8)(uint32_t,const char*,int8_t);
 int (*get_i8)(uint32_t,const char*,int8_t*);
 int (*set_u8)(uint32_t,const char*,uint8_t);
 int (*get_u8)(uint32_t,const char*,uint8_t*);
 int (*set_u16)(uint32_t,const char*,uint16_t);
 int (*get_u16)(uint32_t,const char*,uint16_t*);
 int (*open)(const char*,unsigned,uint32_t*);
 void (*close)(uint32_t);
 int (*commit)(uint32_t);
 int (*set_blob)(uint32_t,const char*,const void*,size_t);
 int (*get_blob)(uint32_t,const char*,void*,size_t*);
 int (*erase)(uint32_t,const char*);
};
struct osi_fixture {uint32_t prefix[69];struct nvs_slots nvs;uint32_t tail[40];};
struct osi_fixture nvs_osi_fixture;
_Static_assert(sizeof(size_t)==4,"Xtensa size_t ABI");
_Static_assert(offsetof(struct osi_fixture,nvs)==276,"pinned NVS offset");
_Static_assert(sizeof(struct nvs_slots)==48,"twelve pointers");
static uint32_t old_handle;
static int same(const uint8_t *a,const uint8_t *b,size_t n){for(size_t i=0;i<n;i++)if(a[i]!=b[i])return 0;return 1;}
int nvs_fixture_run(unsigned phase) {
 struct nvs_slots *n=&nvs_osi_fixture.nvs;
 uint32_t h=0,ro=0,b=0;uint8_t bytes[608],expected[600];
 for(unsigned i=0;i<600;i++)expected[i]=(uint8_t)(i*37+11);
 if(nvs_osi_fixture.prefix[0]!=9 || nvs_osi_fixture.prefix[68]!=0x12345678 || nvs_osi_fixture.tail[0]!=0xabcdefff) return 1;
 for(unsigned i=0;i<12;i++)if(!((uint32_t*)n)[i])return 2;
 if(phase==3){uint8_t x=0xa5;if(n->get_u8(old_handle,"unsigned",&x)!=0x1101 || x!=0xa5)return 3;n->close(old_handle);return 0;}
 if(phase==0){
  struct {uint32_t left,value,right;} handle={0x11223344,0x77777777,0xaabbccdd};
  if(n->open("wifi",1,&handle.value) || handle.left!=0x11223344 || handle.right!=0xaabbccdd || !handle.value)return 4;h=handle.value;old_handle=h;
  if(n->open("wifi",1,0)!=0x102 || n->open("0123456789abcdef",1,&b)!=0x1106 || n->set_u8(h,"0123456789abcdef",7)!=0x1109)return 5;
  if(n->set_i8(h,"signed",(int8_t)-128) || n->set_u8(h,"unsigned",255) || n->set_u16(h,"half",0xbeef))return 6;
  uint8_t canary[6]={1,2,3,4,5,6};
  if(n->get_i8(h,"signed",(int8_t*)&canary[2]) || canary[2]!=128 || canary[1]!=2 || canary[3]!=4)return 7;
  if(n->get_u8(h,"unsigned",&canary[2]) || canary[2]!=255 || canary[1]!=2 || canary[3]!=4)return 8;
  if(n->get_u16(h,"half",(uint16_t*)&canary[2]) || canary[2]!=0xef || canary[3]!=0xbe || canary[1]!=2 || canary[4]!=5)return 9;
  canary[2]=123;if(n->get_u8(h,"signed",&canary[2])!=0x1103 || canary[2]!=123)return 10;
  if(n->set_blob(h,"blob",expected,600) || n->set_blob(h,"empty",0,0))return 11;
  struct {size_t value;uint32_t guard;} length={0,0x13572468};
  if(n->get_blob(h,"blob",0,&length.value) || length.value!=600 || length.guard!=0x13572468)return 12;
  for(unsigned i=0;i<608;i++)bytes[i]=0xcc;length.value=8;
  if(n->get_blob(h,"blob",bytes,&length.value)!=0x110c || length.value!=600 || length.guard!=0x13572468)return 13;
  for(unsigned i=0;i<608;i++)if(bytes[i]!=0xcc)return 14;
  length.value=608;if(n->get_blob(h,"blob",bytes,&length.value) || length.value!=600 || !same(bytes,expected,600) || bytes[600]!=0xcc || bytes[607]!=0xcc)return 15;
  if(n->get_blob(h,"blob",bytes,0)!=0x110c)return 16;
  length.value=42;if(n->get_blob(h,"missing",0,&length.value)!=0x1102 || length.value!=42 || n->get_blob(h,"unsigned",0,&length.value)!=0x1103 || length.value!=42)return 17;
  if(n->get_blob(h,"empty",0,&length.value) || length.value)return 18;
  if(n->open("wifi",0,&ro) || n->set_u8(ro,"unsigned",2)!=0x1104 || n->erase(ro,"unsigned")!=0x1104 || n->commit(ro))return 19;
  if(n->open("ble",1,&b) || n->get_u8(b,"unsigned",bytes)!=0x1102 || n->set_blob(b,"blob","abc",3))return 20;
  if(n->commit(h) || n->set_u8(h,"volatile",1))return 21;n->close(h);n->close(ro);n->close(b);return 0;
 }
 if(n->get_u8(old_handle,"unsigned",bytes)!=0x1107)return 22;
 if(n->open("wifi",0,&ro) || n->get_u8(ro,"unsigned",bytes) || bytes[0]!=255)return 23;
 size_t length=608;if(n->get_blob(ro,"blob",bytes,&length) || length!=600 || !same(bytes,expected,600) || n->get_u8(ro,"volatile",bytes)!=0x1102)return 24;
 if(phase==1){if(n->open("wifi",1,&h) || n->erase(h,"signed") || n->erase(h,"signed")!=0x1102 || n->commit(h))return 25;n->close(h);}
 else if(n->get_i8(ro,"signed",(int8_t*)bytes)!=0x1102)return 26;
 if(n->open("ble",0,&b))return 27;length=608;if(n->get_blob(b,"blob",bytes,&length) || length!=3 || !same(bytes,(const uint8_t*)"abc",3))return 28;
 n->close(ro);n->close(b);return 0;
}
