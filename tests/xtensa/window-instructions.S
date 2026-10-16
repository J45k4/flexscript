.section .windowmeta,"a"
.long 0x4f500001,0x57535457
.long (wm_end-wm_entries)/40,1
wm_entries:
.text
.begin no-transform
.global _start
_start:
.macro OP name,code:vararg
.global w_\name
w_\name:
 \code
w_\name\()_end:
 .pushsection .windowmeta
 .long w_\name-_start,w_\name\()_end-w_\name
 wm_name_\name:
 .asciz "\name"
 .zero 32-(.-wm_name_\name)
 .popsection
.endm
OP call0,call0 target
.balign 4
OP call4,call4 target
.balign 4
OP call8,call8 target
.balign 4
OP call12,call12 target
OP callx0,callx0 a8
OP callx4,callx4 a8
OP callx8,callx8 a8
OP callx12,callx12 a8
OP entry1,entry a1,32
OP entry0,entry a0,0
OP entry2,entry a2,4096
OP entry3,entry a3,32760
OP retw,retw
OP retwn,retw.n
OP rotwneg8,rotw -8
OP rotwneg1,rotw -1
OP rotw0,rotw 0
OP rotw1,rotw 1
OP rotw4,rotw 4
OP rotw7,rotw 7
OP movsp,movsp a1,a5
OP rfwo,rfwo
OP rfwu,rfwu
OP l32e,l32e a3,a5,-16
OP s32e,s32e a2,a9,-64
OP xsrwb,xsr a5,windowbase
OP xsrws,xsr a5,windowstart
OP wsrwb,wsr a5,windowbase
OP wsrws,wsr a5,windowstart
OP rsrwb,rsr a5,windowbase
OP rsrws,rsr a5,windowstart
OP movinneg32,movi.n a8,-32
OP movinneg1,movi.n a8,-1
OP movin0,movi.n a8,0
OP movin31,movi.n a8,31
OP movin63,movi.n a8,63
OP movin95,movi.n a8,95
OP addn,add.n a2,a3,a4
OP addinneg1,addi.n a2,a3,-1
OP addin1,addi.n a2,a3,1
OP addin15,addi.n a2,a3,15
OP l32in,l32i.n a4,a5,60
OP s32in,s32i.n a6,a7,4
OP movn,mov.n a11,a3
OP retn,ret.n
OP nopn,nop.n
OP illn,ill.n
OP beqzn,beqz.n a6,.+32
OP bnezn,bnez.n a7,.+64
OP l32r,l32r a8,_start
OP mov15,mov a15,a15
OP mov11,mov a11,a11
OP mov7,mov a7,a7
OP ret,ret
OP memw,memw
OP addx2g1,addx2 a3,a7,a2
OP addx2g2,addx2 a7,a11,a3
OP addx2g3,addx2 a15,a7,a11
OP addx4g1,addx4 a3,a7,a2
OP addx4g2,addx4 a7,a11,a3
OP addx4g3,addx4 a15,a7,a11
OP addx8g1,addx8 a3,a7,a2
OP addx8g2,addx8 a7,a11,a3
OP addx8g3,addx8 a15,a7,a11
OP subx2g1,subx2 a3,a7,a2
OP subx2g2,subx2 a7,a11,a3
OP subx2g3,subx2 a15,a7,a11
OP subx4g1,subx4 a3,a7,a2
OP subx4g2,subx4 a7,a11,a3
OP subx4g3,subx4 a15,a7,a11
OP subx8g1,subx8 a3,a7,a2
OP subx8g2,subx8 a7,a11,a3
OP subx8g3,subx8 a15,a7,a11
.balign 4
.byte 0
OP loop,loop a8,.+32
.balign 4
.byte 0
OP loopnez,loopnez a8,.+32
.balign 4
.byte 0
OP loopgtz,loopgtz a8,.+32
OP beqi0,beqi a8,-1,.+32
OP beqi1,beqi a8,1,.+32
OP beqi2,beqi a8,2,.+32
OP beqi3,beqi a8,3,.+32
OP beqi4,beqi a8,4,.+32
OP beqi5,beqi a8,5,.+32
OP beqi6,beqi a8,6,.+32
OP beqi7,beqi a8,7,.+32
OP beqi8,beqi a8,8,.+32
OP beqi9,beqi a8,10,.+32
OP beqi10,beqi a8,12,.+32
OP beqi11,beqi a8,16,.+32
OP beqi12,beqi a8,32,.+32
OP beqi13,beqi a8,64,.+32
OP beqi14,beqi a8,128,.+32
OP beqi15,beqi a8,256,.+32
OP bnei0,bnei a8,-1,.+32
OP bnei1,bnei a8,1,.+32
OP bnei2,bnei a8,2,.+32
OP bnei3,bnei a8,3,.+32
OP bnei4,bnei a8,4,.+32
OP bnei5,bnei a8,5,.+32
OP bnei6,bnei a8,6,.+32
OP bnei7,bnei a8,7,.+32
OP bnei8,bnei a8,8,.+32
OP bnei9,bnei a8,10,.+32
OP bnei10,bnei a8,12,.+32
OP bnei11,bnei a8,16,.+32
OP bnei12,bnei a8,32,.+32
OP bnei13,bnei a8,64,.+32
OP bnei14,bnei a8,128,.+32
OP bnei15,bnei a8,256,.+32
OP blti0,blti a8,-1,.+32
OP blti1,blti a8,1,.+32
OP blti2,blti a8,2,.+32
OP blti3,blti a8,3,.+32
OP blti4,blti a8,4,.+32
OP blti5,blti a8,5,.+32
OP blti6,blti a8,6,.+32
OP blti7,blti a8,7,.+32
OP blti8,blti a8,8,.+32
OP blti9,blti a8,10,.+32
OP blti10,blti a8,12,.+32
OP blti11,blti a8,16,.+32
OP blti12,blti a8,32,.+32
OP blti13,blti a8,64,.+32
OP blti14,blti a8,128,.+32
OP blti15,blti a8,256,.+32
OP bgei0,bgei a8,-1,.+32
OP bgei1,bgei a8,1,.+32
OP bgei2,bgei a8,2,.+32
OP bgei3,bgei a8,3,.+32
OP bgei4,bgei a8,4,.+32
OP bgei5,bgei a8,5,.+32
OP bgei6,bgei a8,6,.+32
OP bgei7,bgei a8,7,.+32
OP bgei8,bgei a8,8,.+32
OP bgei9,bgei a8,10,.+32
OP bgei10,bgei a8,12,.+32
OP bgei11,bgei a8,16,.+32
OP bgei12,bgei a8,32,.+32
OP bgei13,bgei a8,64,.+32
OP bgei14,bgei a8,128,.+32
OP bgei15,bgei a8,256,.+32
OP bltui0,bltui a8,32768,.+32
OP bltui1,bltui a8,65536,.+32
OP bltui2,bltui a8,2,.+32
OP bltui3,bltui a8,3,.+32
OP bltui4,bltui a8,4,.+32
OP bltui5,bltui a8,5,.+32
OP bltui6,bltui a8,6,.+32
OP bltui7,bltui a8,7,.+32
OP bltui8,bltui a8,8,.+32
OP bltui9,bltui a8,10,.+32
OP bltui10,bltui a8,12,.+32
OP bltui11,bltui a8,16,.+32
OP bltui12,bltui a8,32,.+32
OP bltui13,bltui a8,64,.+32
OP bltui14,bltui a8,128,.+32
OP bltui15,bltui a8,256,.+32
OP bgeui0,bgeui a8,32768,.+32
OP bgeui1,bgeui a8,65536,.+32
OP bgeui2,bgeui a8,2,.+32
OP bgeui3,bgeui a8,3,.+32
OP bgeui4,bgeui a8,4,.+32
OP bgeui5,bgeui a8,5,.+32
OP bgeui6,bgeui a8,6,.+32
OP bgeui7,bgeui a8,7,.+32
OP bgeui8,bgeui a8,8,.+32
OP bgeui9,bgeui a8,10,.+32
OP bgeui10,bgeui a8,12,.+32
OP bgeui11,bgeui a8,16,.+32
OP bgeui12,bgeui a8,32,.+32
OP bgeui13,bgeui a8,64,.+32
OP bgeui14,bgeui a8,128,.+32
OP bgeui15,bgeui a8,256,.+32
OP beqz,beqz a8,.+128
OP bnez,bnez a8,.+128
OP bltz,bltz a8,.+128
OP bgez,bgez a8,.+128
OP bnone,bnone a8,a11,.+32
OP bany,bany a8,a11,.+32
OP ball,ball a8,a11,.+32
OP bnall,bnall a8,a11,.+32
OP bbc,bbc a8,a11,.+32
OP bbs,bbs a8,a11,.+32
OP bbci0,bbci a3,0,.+32
OP bbci1,bbci a3,1,.+32
OP bbci2,bbci a3,2,.+32
OP bbci3,bbci a3,3,.+32
OP bbci4,bbci a3,4,.+32
OP bbci5,bbci a3,5,.+32
OP bbci6,bbci a3,6,.+32
OP bbci7,bbci a3,7,.+32
OP bbci8,bbci a3,8,.+32
OP bbci9,bbci a3,9,.+32
OP bbci10,bbci a3,10,.+32
OP bbci11,bbci a3,11,.+32
OP bbci12,bbci a3,12,.+32
OP bbci13,bbci a3,13,.+32
OP bbci14,bbci a3,14,.+32
OP bbci15,bbci a3,15,.+32
OP bbci16,bbci a3,16,.+32
OP bbci17,bbci a3,17,.+32
OP bbci18,bbci a3,18,.+32
OP bbci19,bbci a3,19,.+32
OP bbci20,bbci a3,20,.+32
OP bbci21,bbci a3,21,.+32
OP bbci22,bbci a3,22,.+32
OP bbci23,bbci a3,23,.+32
OP bbci24,bbci a3,24,.+32
OP bbci25,bbci a3,25,.+32
OP bbci26,bbci a3,26,.+32
OP bbci27,bbci a3,27,.+32
OP bbci28,bbci a3,28,.+32
OP bbci29,bbci a3,29,.+32
OP bbci30,bbci a3,30,.+32
OP bbci31,bbci a3,31,.+32
OP bbsi0,bbsi a3,0,.+32
OP bbsi1,bbsi a3,1,.+32
OP bbsi2,bbsi a3,2,.+32
OP bbsi3,bbsi a3,3,.+32
OP bbsi4,bbsi a3,4,.+32
OP bbsi5,bbsi a3,5,.+32
OP bbsi6,bbsi a3,6,.+32
OP bbsi7,bbsi a3,7,.+32
OP bbsi8,bbsi a3,8,.+32
OP bbsi9,bbsi a3,9,.+32
OP bbsi10,bbsi a3,10,.+32
OP bbsi11,bbsi a3,11,.+32
OP bbsi12,bbsi a3,12,.+32
OP bbsi13,bbsi a3,13,.+32
OP bbsi14,bbsi a3,14,.+32
OP bbsi15,bbsi a3,15,.+32
OP bbsi16,bbsi a3,16,.+32
OP bbsi17,bbsi a3,17,.+32
OP bbsi18,bbsi a3,18,.+32
OP bbsi19,bbsi a3,19,.+32
OP bbsi20,bbsi a3,20,.+32
OP bbsi21,bbsi a3,21,.+32
OP bbsi22,bbsi a3,22,.+32
OP bbsi23,bbsi a3,23,.+32
OP bbsi24,bbsi a3,24,.+32
OP bbsi25,bbsi a3,25,.+32
OP bbsi26,bbsi a3,26,.+32
OP bbsi27,bbsi a3,27,.+32
OP bbsi28,bbsi a3,28,.+32
OP bbsi29,bbsi a3,29,.+32
OP bbsi30,bbsi a3,30,.+32
OP bbsi31,bbsi a3,31,.+32
OP beqineg,beqi a8,1,.-124
OP beqipos,beqi a8,1,.+131
OP beqzneg,beqz a8,.-2044
OP beqzpos,beqz a8,.+2051
.org 0x400
.global target
target:
 entry a1,32
 retw.n
.end no-transform
.pushsection .windowmeta
wm_end:
.popsection
