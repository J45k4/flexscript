// Copyright 2023 The Go Authors. All rights reserved.
// Decoder algorithms adapted from Go internal/zstd (Go 1.25.3).
// BSD-3-Clause; see licenses/Go-BSD.txt.
// Entries pack symbol:8, state-bit count:8, next-state base:16.
fn fz_fse_core(c,p,n,off,maxsym,maxbits,table,bases) {
 if load64(c+1792) {store64(c+1952,p);store64(c+1960,n);store64(c+1968,off);store64(c+1976,maxsym);store64(c+1984,maxbits);store64(c+1992,table);store64(c+2000,bases);let result=native_call1(load64(c+1792),c);if result<0 {return fz_fail(c,"invalid native FSE table");}return result;}

 let cursor=off;let reservoir=0;let available=0;
 while available<16 {if cursor>=n {return fz_fail(c,"truncated FSE header");}reservoir=reservoir|(load8(p+cursor)<<available);cursor=cursor+1;available=available+8;}
 let log=(reservoir&15)+5;reservoir=reservoir>>4;available=available-4;
 if log>maxbits {return fz_fail(c,"FSE accuracy exceeds limit");}
 let remaining=(1<<log)+1;let threshold=1<<log;let needed=log+1;let sym=0;let prev=0;let norm=c+18432;fz_fill(norm,0,(maxsym+1)*8);
 while remaining>1 && sym<=maxsym {
  while available<16 {if cursor>=n {return fz_fail(c,"truncated FSE probabilities");}reservoir=reservoir|(load8(p+cursor)<<available);cursor=cursor+1;available=available+8;}
  if prev {
   let end=sym;
   while (reservoir&4095)==4095 {end=end+18;reservoir=reservoir>>12;available=available-12;while available<16 {if cursor>=n {return fz_fail(c,"truncated FSE zeros");}reservoir=reservoir|(load8(p+cursor)<<available);cursor=cursor+1;available=available+8;}}
   while (reservoir&3)==3 {end=end+3;reservoir=reservoir>>2;available=available-2;while available<16 {if cursor>=n {return fz_fail(c,"truncated FSE zeros");}reservoir=reservoir|(load8(p+cursor)<<available);cursor=cursor+1;available=available+8;}}
   end=end+(reservoir&3);reservoir=reservoir>>2;available=available-2;if end>maxsym {return fz_fail(c,"FSE zero run exceeds alphabet");}sym=end;prev=0;
  }else {
   let max=2*threshold-1-remaining;let count=0;let bits=needed;
   if (reservoir&(threshold-1))<max {bits=needed-1;count=reservoir&((1<<bits)-1);}else {count=reservoir&((1<<bits)-1);if count>=threshold {count=count-max;}}
   reservoir=reservoir>>bits;available=available-bits;
   count=count-1;store64(norm+sym*8,count);sym=sym+1;if count<0 {remaining=remaining-1;}else {remaining=remaining-count;}prev=count==0;
   while remaining<threshold && threshold>0 {needed=needed-1;threshold=threshold>>1;}
  }
 }
 if remaining!=1 {return fz_fail(c,"invalid FSE probability sum");}
 cursor=cursor-available/8;store64(c+304,cursor);

 let size=1<<log;let high=size-1;let next=c+20480;let i=0;
 while i<=maxsym {let count=load64(norm+i*8);if count<0 {store64(table+high*8,i);high=high-1;store64(next+i*8,1);}else {store64(next+i*8,count);}i=i+1;}
 let step=(size>>1)+(size>>3)+3;let pos=0;i=0;
 while i<=maxsym {let j=0;while j<load64(norm+i*8) {store64(table+pos*8,i);pos=(pos+step)&(size-1);while pos>high {pos=(pos+step)&(size-1);}j=j+1;}i=i+1;}
 if pos {return fz_fail(c,"invalid FSE spread");}i=0;
 while i<size {let symbol=load64(table+i*8);let t=load64(next+symbol*8);if !t {return fz_fail(c,"empty FSE state");}store64(next+symbol*8,t+1);let bits=log-fz_log(t);if bases {store64(table+i*8,load64(bases+symbol*8)|(bits<<37)|(((t<<bits)-size)<<45));}else {store64(table+i*8,symbol|(bits<<8)|(((t<<bits)-size)<<16));}i=i+1;}
 return log;
}
fn fz_fse(c,p,n,off,maxsym,maxbits,table) {return fz_fse_core(c,p,n,off,maxsym,maxbits,table,0);}
fn fz_ll_base(sym) {
 if sym==0 {return 0|(0<<32);}
 if sym==1 {return 1|(0<<32);}
 if sym==2 {return 2|(0<<32);}
 if sym==3 {return 3|(0<<32);}
 if sym==4 {return 4|(0<<32);}
 if sym==5 {return 5|(0<<32);}
 if sym==6 {return 6|(0<<32);}
 if sym==7 {return 7|(0<<32);}
 if sym==8 {return 8|(0<<32);}
 if sym==9 {return 9|(0<<32);}
 if sym==10 {return 10|(0<<32);}
 if sym==11 {return 11|(0<<32);}
 if sym==12 {return 12|(0<<32);}
 if sym==13 {return 13|(0<<32);}
 if sym==14 {return 14|(0<<32);}
 if sym==15 {return 15|(0<<32);}
 if sym==16 {return 16|(1<<32);}
 if sym==17 {return 18|(1<<32);}
 if sym==18 {return 20|(1<<32);}
 if sym==19 {return 22|(1<<32);}
 if sym==20 {return 24|(2<<32);}
 if sym==21 {return 28|(2<<32);}
 if sym==22 {return 32|(3<<32);}
 if sym==23 {return 40|(3<<32);}
 if sym==24 {return 48|(4<<32);}
 if sym==25 {return 64|(6<<32);}
 if sym==26 {return 128|(7<<32);}
 if sym==27 {return 256|(8<<32);}
 if sym==28 {return 512|(9<<32);}
 if sym==29 {return 1024|(10<<32);}
 if sym==30 {return 2048|(11<<32);}
 if sym==31 {return 4096|(12<<32);}
 if sym==32 {return 8192|(13<<32);}
 if sym==33 {return 16384|(14<<32);}
 if sym==34 {return 32768|(15<<32);}
 if sym==35 {return 65536|(16<<32);}
 return -1;
}
fn fz_of_base(sym) {
 if sym==0 {return 1|(0<<32);}
 if sym==1 {return 2|(1<<32);}
 if sym==2 {return 1|(2<<32);}
 if sym==3 {return 5|(3<<32);}
 if sym==4 {return 13|(4<<32);}
 if sym==5 {return 29|(5<<32);}
 if sym==6 {return 61|(6<<32);}
 if sym==7 {return 125|(7<<32);}
 if sym==8 {return 253|(8<<32);}
 if sym==9 {return 509|(9<<32);}
 if sym==10 {return 1021|(10<<32);}
 if sym==11 {return 2045|(11<<32);}
 if sym==12 {return 4093|(12<<32);}
 if sym==13 {return 8189|(13<<32);}
 if sym==14 {return 16381|(14<<32);}
 if sym==15 {return 32765|(15<<32);}
 if sym==16 {return 65533|(16<<32);}
 if sym==17 {return 131069|(17<<32);}
 if sym==18 {return 262141|(18<<32);}
 if sym==19 {return 524285|(19<<32);}
 if sym==20 {return 1048573|(20<<32);}
 if sym==21 {return 2097149|(21<<32);}
 if sym==22 {return 4194301|(22<<32);}
 if sym==23 {return 8388605|(23<<32);}
 if sym==24 {return 16777213|(24<<32);}
 if sym==25 {return 33554429|(25<<32);}
 if sym==26 {return 67108861|(26<<32);}
 if sym==27 {return 134217725|(27<<32);}
 if sym==28 {return 268435453|(28<<32);}
 if sym==29 {return 536870909|(29<<32);}
 if sym==30 {return 1073741821|(30<<32);}
 if sym==31 {return 2147483645|(31<<32);}
 return -1;
}
fn fz_ml_base(sym) {
 if sym==0 {return 3|(0<<32);}
 if sym==1 {return 4|(0<<32);}
 if sym==2 {return 5|(0<<32);}
 if sym==3 {return 6|(0<<32);}
 if sym==4 {return 7|(0<<32);}
 if sym==5 {return 8|(0<<32);}
 if sym==6 {return 9|(0<<32);}
 if sym==7 {return 10|(0<<32);}
 if sym==8 {return 11|(0<<32);}
 if sym==9 {return 12|(0<<32);}
 if sym==10 {return 13|(0<<32);}
 if sym==11 {return 14|(0<<32);}
 if sym==12 {return 15|(0<<32);}
 if sym==13 {return 16|(0<<32);}
 if sym==14 {return 17|(0<<32);}
 if sym==15 {return 18|(0<<32);}
 if sym==16 {return 19|(0<<32);}
 if sym==17 {return 20|(0<<32);}
 if sym==18 {return 21|(0<<32);}
 if sym==19 {return 22|(0<<32);}
 if sym==20 {return 23|(0<<32);}
 if sym==21 {return 24|(0<<32);}
 if sym==22 {return 25|(0<<32);}
 if sym==23 {return 26|(0<<32);}
 if sym==24 {return 27|(0<<32);}
 if sym==25 {return 28|(0<<32);}
 if sym==26 {return 29|(0<<32);}
 if sym==27 {return 30|(0<<32);}
 if sym==28 {return 31|(0<<32);}
 if sym==29 {return 32|(0<<32);}
 if sym==30 {return 33|(0<<32);}
 if sym==31 {return 34|(0<<32);}
 if sym==32 {return 35|(1<<32);}
 if sym==33 {return 37|(1<<32);}
 if sym==34 {return 39|(1<<32);}
 if sym==35 {return 41|(1<<32);}
 if sym==36 {return 43|(2<<32);}
 if sym==37 {return 47|(2<<32);}
 if sym==38 {return 51|(3<<32);}
 if sym==39 {return 59|(3<<32);}
 if sym==40 {return 67|(4<<32);}
 if sym==41 {return 83|(4<<32);}
 if sym==42 {return 99|(5<<32);}
 if sym==43 {return 131|(7<<32);}
 if sym==44 {return 259|(8<<32);}
 if sym==45 {return 515|(9<<32);}
 if sym==46 {return 1027|(10<<32);}
 if sym==47 {return 2051|(11<<32);}
 if sym==48 {return 4099|(12<<32);}
 if sym==49 {return 8195|(13<<32);}
 if sym==50 {return 16387|(14<<32);}
 if sym==51 {return 32771|(15<<32);}
 if sym==52 {return 65539|(16<<32);}
 return -1;
}
fn fz_ll_default(t) {
 store64(t+0,1024);
 store64(t+8,1049600);
 store64(t+16,2098433);
 store64(t+24,1283);
 store64(t+32,1284);
 store64(t+40,1286);
 store64(t+48,1287);
 store64(t+56,1289);
 store64(t+64,1290);
 store64(t+72,1292);
 store64(t+80,1550);
 store64(t+88,1296);
 store64(t+96,1298);
 store64(t+104,1299);
 store64(t+112,1301);
 store64(t+120,1302);
 store64(t+128,1304);
 store64(t+136,2098457);
 store64(t+144,1306);
 store64(t+152,1563);
 store64(t+160,1565);
 store64(t+168,1567);
 store64(t+176,2098176);
 store64(t+184,1025);
 store64(t+192,1282);
 store64(t+200,2098436);
 store64(t+208,1285);
 store64(t+216,2098439);
 store64(t+224,1288);
 store64(t+232,2098442);
 store64(t+240,1291);
 store64(t+248,1549);
 store64(t+256,2098448);
 store64(t+264,1297);
 store64(t+272,2098451);
 store64(t+280,1300);
 store64(t+288,2098454);
 store64(t+296,1303);
 store64(t+304,1049);
 store64(t+312,1049625);
 store64(t+320,2098458);
 store64(t+328,1564);
 store64(t+336,1566);
 store64(t+344,3146752);
 store64(t+352,1049601);
 store64(t+360,2098434);
 store64(t+368,2098435);
 store64(t+376,2098437);
 store64(t+384,2098438);
 store64(t+392,2098440);
 store64(t+400,2098441);
 store64(t+408,2098443);
 store64(t+416,2098444);
 store64(t+424,1551);
 store64(t+432,2098449);
 store64(t+440,2098450);
 store64(t+448,2098452);
 store64(t+456,2098453);
 store64(t+464,2098455);
 store64(t+472,2098456);
 store64(t+480,1571);
 store64(t+488,1570);
 store64(t+496,1569);
 store64(t+504,1568);
 return 1;
}
fn fz_of_default(t) {
 store64(t+0,1280);
 store64(t+8,1030);
 store64(t+16,1289);
 store64(t+24,1295);
 store64(t+32,1301);
 store64(t+40,1283);
 store64(t+48,1031);
 store64(t+56,1292);
 store64(t+64,1298);
 store64(t+72,1303);
 store64(t+80,1285);
 store64(t+88,1032);
 store64(t+96,1294);
 store64(t+104,1300);
 store64(t+112,1282);
 store64(t+120,1049607);
 store64(t+128,1291);
 store64(t+136,1297);
 store64(t+144,1302);
 store64(t+152,1284);
 store64(t+160,1049608);
 store64(t+168,1293);
 store64(t+176,1299);
 store64(t+184,1281);
 store64(t+192,1049606);
 store64(t+200,1290);
 store64(t+208,1296);
 store64(t+216,1308);
 store64(t+224,1307);
 store64(t+232,1306);
 store64(t+240,1305);
 store64(t+248,1304);
 return 1;
}
fn fz_ml_default(t) {
 store64(t+0,1536);
 store64(t+8,1025);
 store64(t+16,2098434);
 store64(t+24,1283);
 store64(t+32,1285);
 store64(t+40,1286);
 store64(t+48,1288);
 store64(t+56,1546);
 store64(t+64,1549);
 store64(t+72,1552);
 store64(t+80,1555);
 store64(t+88,1558);
 store64(t+96,1561);
 store64(t+104,1564);
 store64(t+112,1567);
 store64(t+120,1569);
 store64(t+128,1571);
 store64(t+136,1573);
 store64(t+144,1575);
 store64(t+152,1577);
 store64(t+160,1579);
 store64(t+168,1581);
 store64(t+176,1049601);
 store64(t+184,1026);
 store64(t+192,2098435);
 store64(t+200,1284);
 store64(t+208,2098438);
 store64(t+216,1287);
 store64(t+224,1545);
 store64(t+232,1548);
 store64(t+240,1551);
 store64(t+248,1554);
 store64(t+256,1557);
 store64(t+264,1560);
 store64(t+272,1563);
 store64(t+280,1566);
 store64(t+288,1568);
 store64(t+296,1570);
 store64(t+304,1572);
 store64(t+312,1574);
 store64(t+320,1576);
 store64(t+328,1578);
 store64(t+336,1580);
 store64(t+344,2098177);
 store64(t+352,3146753);
 store64(t+360,1049602);
 store64(t+368,2098436);
 store64(t+376,2098437);
 store64(t+384,2098439);
 store64(t+392,2098440);
 store64(t+400,1547);
 store64(t+408,1550);
 store64(t+416,1553);
 store64(t+424,1556);
 store64(t+432,1559);
 store64(t+440,1562);
 store64(t+448,1565);
 store64(t+456,1588);
 store64(t+464,1587);
 store64(t+472,1586);
 store64(t+480,1585);
 store64(t+488,1584);
 store64(t+496,1583);
 store64(t+504,1582);
 return 1;
}

// Cached baseline/extra-bit pairs avoid symbol-dependent branches in decoding.
fn fz_baselines(c) {let k=0;while k<32 {store64(c+2048+k*8,(1<<k)-1);k=k+1;}let i=0;while i<36 {store64(c+512+i*8,fz_ll_base(i));i=i+1;}i=0;while i<53 {store64(c+800+i*8,fz_ml_base(i));i=i+1;}i=0;while i<32 {store64(c+1224+i*8,fz_of_base(i));i=i+1;}return 1;}

// For every supported log, cache (state-bit count | next-state base<<8)
// indexed by the normalized next counter. All five tables occupy 7936 bytes.
fn fz_state_transforms(c) {
 let log=5;while log<=9 {let size=1<<log;let table=c+434432+(size*2-64)*4;let t=1;while t<size*2 {let bits=log-fz_log(t);let q=bits|(((t<<bits)-size)<<8);bytes_store32(table+t*4,q);t=t+1;}log=log+1;}return 1;
}
