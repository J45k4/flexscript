import "../../emulator/xtensa/cpu.flex";
import "../../scripts/lib/host.flex";
global checks=0;
fn check(ok,message){h_assert(ok,message);checks=checks+1;return 0;}
fn at(c,index){store64(c+128,0x1000+index*3);return 0;}
fn step(c,index){at(c,index);check(xt_step(c)==0,"GNU instruction execution");return 0;}
fn reg(c,index,value){check(xt_reg(c,index)==(value&0xffffffff),"GNU instruction register result");return 0;}
fn fresh(code,size){let c=xt_create();check(c>0,"CPU allocation");let p=xt_map(c,0x1000,4096,5);check(p>0,"code allocation");em_copy(p,code,size);check(xt_map(c,0x2000,256,3)>0,"data allocation");store64(c+128,0x1000);return c;}
fn elf_fixture(){let p=alloc(160);em_zero(p,160);em_put32(p,0x464c457f);store8(p+4,1);store8(p+5,1);store8(p+6,1);store8(p+16,2);store8(p+18,94);em_put32(p+20,1);em_put32(p+24,0x1000);em_put32(p+28,52);store8(p+40,52);store8(p+42,32);store8(p+44,1);let h=p+52;em_put32(h,1);em_put32(h+4,128);em_put32(h+8,0x1000);em_put32(h+16,3);em_put32(h+20,8);em_put32(h+24,5);em_put32(h+28,1);store8(p+128,0xf0);store8(p+129,0x20);return p;}
fn main(argc,argv){h_environment(argc,argv);h_assert(argc==2,"CPU test requires GNU .text file");let code=h_read(load64(argv+8));check(h_file_size==102,"34 GNU 24-bit instructions");
 let c=fresh(code,102);xt_setreg(c,1,0x2000);xt_wsr(c,230,96);
 step(c,0);reg(c,2,-17);step(c,1);reg(c,3,-12);step(c,2);reg(c,4,-29);step(c,3);reg(c,5,-5);
 step(c,4);reg(c,6,0xffffffe4);step(c,5);reg(c,7,0xffffffff);step(c,6);reg(c,8,27);step(c,7);reg(c,9,17);
 step(c,8);reg(c,10,204);step(c,9);reg(c,11,0xffffffe3);step(c,10);reg(c,6,0xffffef00);step(c,11);reg(c,7,0xffffff);step(c,12);reg(c,8,0xffffffff);
 step(c,13);check(xt_sr(c,3)==17,"SSL SAR");step(c,14);reg(c,9,0xfffa0000);step(c,15);check(xt_sr(c,3)==20,"SSR SAR");step(c,16);reg(c,10,4095);step(c,17);reg(c,11,-1);step(c,18);reg(c,12,4095);
 step(c,19);reg(c,2,19);step(c,20);check(xt_sr(c,228)==19,"INTENABLE write");step(c,21);reg(c,2,96);check(xt_sr(c,230)==111,"RSIL preserves PS");step(c,22);step(c,23);
 xt_write(c,0x2008,4,0x1234abcd);step(c,24);reg(c,4,0x1234abcd);xt_setreg(c,5,0x88776655);step(c,25);check(xt_read(c,0x200c,4)==0x88776655,"S32I");xt_write(c,0x2001,1,254);step(c,26);reg(c,6,254);xt_setreg(c,7,0x12345678);step(c,27);check(xt_read(c,0x2002,1)==120,"S8I low byte");
 xt_setreg(c,8,0x12345678);step(c,28);check(load64(c+128)==0x12345678 && xt_reg(c,0)==0x1057,"CALLX0");xt_setreg(c,9,0x76543210);step(c,29);check(load64(c+128)==0x76543210,"JX");step(c,30);check(load64(c+128)==0x1057,"RET");step(c,31);at(c,32);check(xt_step(c)==5 && !(xt_sr(c,230)&15),"WAITI unmasks and exits");xt_wsr(c,177,0xabcdef);xt_wsr(c,230,16);step(c,33);check(load64(c+128)==0xabcdef && !(xt_sr(c,230)&16),"RFE");xt_close(c);
 // Independent host word arithmetic exercises decode at boundary values.
 let seeds=alloc(48);store64(seeds,0);store64(seeds+8,1);store64(seeds+16,0x7fffffff);store64(seeds+24,0x80000000);store64(seeds+32,0xffffffff);store64(seeds+40,0x12345678);c=fresh(code,102);let i=0;while i<6{let j=0;while j<6{let a=load64(seeds+i*8);let b=load64(seeds+j*8);xt_setreg(c,2,a);xt_setreg(c,3,b);step(c,2);reg(c,4,a+b);step(c,3);reg(c,5,a-b);step(c,8);reg(c,10,a*b);step(c,9);reg(c,11,(a*b)>>32);j=j+1;}i=i+1;}
 // A read MMIO exit retires exactly once, after the caller supplies its value.
 let run=alloc(4096);em_zero(run,4096);xt_setreg(c,1,0x60000000);at(c,24);let before=load64(c+176);check(xt_run_slice(c,run,10000,before+1)==6,"MMIO read exit");check(load64(c+176)==before && load64(run+32)==0x60000008 && em_u32(run+48)==4 && !load8(run+52),"MMIO read fields and suspension");em_put32(run+40,0xfedcba98);check(xt_run_slice(c,run,10000,before+1)==10,"MMIO read resume");reg(c,4,0xfedcba98);check(load64(c+176)==before+1,"MMIO read single retirement");at(c,25);before=load64(c+176);check(xt_run_slice(c,run,10000,before+1)==6 && load8(run+52)==1 && load64(c+176)==before+1,"MMIO write retires once");
 xt_wsr(c,234,0xffffffff);check(xt_sr(c,234)==0xffffffff,"CCOUNT offset");step(c,31);check(xt_sr(c,234)==0,"CCOUNT wrap");xt_interrupt(c,2);xt_wsr(c,227,2);check(xt_sr(c,226)&2,"hardware line survives INTCLEAR");xt_interrupt(c,0);check(!(xt_sr(c,226)&2),"hardware line deassertion");xt_close(c);
 c=fresh(code,102);xt_setreg(c,1,0x1000);at(c,25);check(xt_run(c,run,10)== -1 && load64(c+160)== -13 && load64(c+176)==0,"execute region write permission");xt_close(c);
 c=fresh(code,102);xt_setreg(c,1,0x2001);at(c,24);check(xt_run(c,run,10)== -1 && load64(c+160)== -14,"unaligned load fault");xt_close(c);
 c=fresh(code,102);at(c,31);check(xt_run(c,run,1)== -1 && load64(c+160)== -110 && load64(c+176)==1,"bounded instruction fuel");xt_close(c);
 c=fresh(code,102);check(xt_map(c,0x1080,8,3)== -22 && xt_map(c,0xffffffff,2,3)== -22,"overlap and address overflow");let image=elf_fixture();em_put32(image+52+20,4097);check(xt_load_elf(c,image,160)== -22 && xt_read(c,0x1000,1)==load8(code),"invalid ELF atomic rejection");em_put32(image+52+20,8);check(xt_load_elf(c,image,130)== -22,"truncated ELF");check(xt_load_elf(c,image,160)==0 && xt_read(c,0x1000,3)==0x20f0 && xt_read(c,0x1003,4)==0,"ELF load and zero-fill");xt_close(c);
 c=fresh(code,102);let raw=xt_load_region(c,0x1000,3);let host=load64(raw+16);store8(host,255);store8(host+1,255);store8(host+2,255);check(xt_run(c,run,10)== -1 && load64(c+160)== -95 && load64(c+168)==0x1000,"unsupported opcode precise fault");xt_close(c);
 h_print(1,h_cat3("Xtensa CPU: ",h_int(checks)," checks passed\n"));return 0;
}
