#include "spi-metadata.h"
int main(void){describe();
 const unsigned lens[]={1,7,8,9,31,32,63,64,255,256,257,511,512};
 uint64_t header[4]={UINT64_C(0x5350495245460001),nm,2*4*4*13,1344};
 if(fwrite(header,sizeof header,1,stdout)!=1 || fwrite(meta,8,nm,stdout)!=nm)return 1;
 for(unsigned bus=2;bus<=3;bus++)for(unsigned mode=0;mode<4;mode++)for(unsigned order=0;order<4;order++)for(unsigned k=0;k<13;k++){
  unsigned bits=lens[k],seed=k*17+bus*29+mode*7+order*3;
  unsigned pre=1+seed%7,n=4+seed%5,h=1+seed%(n-1),ratio=S3 && (seed&1)?2:1;
  uint64_t f[16]={bus,mode,order&1,(order>>1)&1,bits,bits<=256 && (seed&2),bits<=256 && (seed&4),((pre-1)<<18)|((n-1)<<12)|((h-1)<<6)|(n-1),ratio==2?3:7,pre*h*ratio,pre*(n-h)*ratio,seed,S3?0:6,0,0,0};
  uint8_t tx[64],mi[64],rx[64],edges[1024]={0};
  for(unsigned i=0;i<64;i++){tx[i]=(i*37+seed)^0x96;mi[i]=(i*53+seed*3)^0x69;}
  /* RX retains every untouched bit in the selected buffer half. */
  for(unsigned i=0;i<64;i++)rx[i]=tx[(i+(f[6]?32:0))%64];
  if(!S3)memset(rx,0,(bits+7)/8); /*272 silicon captures show byte-granular overwrite, including final padding.*/
  for(unsigned b=0;b<bits;b++){
   unsigned shift=f[3]?b%8:7-b%8,mask=1u<<shift,level=(mi[b/8]>>shift)&1;
   rx[b/8]=(rx[b/8]&~mask)|(level<<shift);
   for(unsigned trail=0;trail<2;trail++){
    unsigned m=(tx[(b/8)+(f[5]?32:0)]>>(f[2]?b%8:7-b%8))&1;
    edges[b*2+trail]=((mode>>1)^!trail)|(m<<1)|((trail==(mode&1))<<2);
   }
  }
  if(fwrite(f,sizeof f,1,stdout)!=1 || fwrite(tx,64,1,stdout)!=1 || fwrite(mi,64,1,stdout)!=1 || fwrite(rx,64,1,stdout)!=1 || fwrite(edges,1024,1,stdout)!=1)return 1;
 }
 return 0;
}
