// Unicode 17 UAX #14 revision 55, default LB1..LB31. No dictionary tailoring.
import "utf8.flex";
import "line-properties.flex";
// Classes AI0 AK1 AL2 AP3 AS4 B2=5 BA6 BB7 BK8 CB9 CJ10 CL11 CM12 CP13
// CR14 EB15 EM16 EX17 GL18 H2=19 H3=20 HH21 HL22 HY23 ID24 IN25 IS26
// JL27 JT28 JV29 LF30 NL31 NS32 NU33 OP34 PO35 PR36 QU37 RI38 SA39 SG40
// SP41 SY42 VF43 VI44 WJ45 XX46 ZW47 ZWJ48.
fn ul_unpack(p,n){let v=0;let i=0;while i<n{v=(v<<6)|(load8(p+i)-63);i=i+1;}return v;}
fn unicode_line_property(cp){
    if cp<0 || cp>1114111{return 1070;}if cp>=0xac00 && cp<=0xd7a3{if (cp-0xac00)%28==0{return 83;}return 84;}
    let data=unicode_line_property_data();let low=0;let high=unicode_line_property_count();while low<high{let mid=(low+high)/2;let p=data+mid*10;if cp<ul_unpack(p,4){high=mid;}else if cp>ul_unpack(p+4,4){low=mid+1;}else{return ul_unpack(p+8,2);}}return 1070;
}
fn ul_class(records,i){if i<0{return -1;}return load64(records+i*32+16)&63;}
fn ul_hard(t){return t==8 || t==14 || t==30 || t==31;}
fn ul_alpha(t){return t==2 || t==22;}
fn ul_korean(t){return t==19 || t==20 || t==27 || t==28 || t==29;}
fn ul_aksara(records,i){let t=ul_class(records,i);return t==1 || t==4 || (i>=0 && load64(records+i*32)==0x25cc);}
fn ul_aksara_after_virama(records,i){return ul_class(records,i)==1 || (i>=0 && load64(records+i*32)==0x25cc);}
fn ul_initial_context(t){return t<0 || ul_hard(t) || t==34 || t==37 || t==18 || t==41 || t==47;}
fn ul_final_context(t){return t<0 || ul_hard(t) || t==41 || t==18 || t==45 || t==11 || t==37 || t==13 || t==17 || t==26 || t==42 || t==47;}
fn ul_hyphen_context(t){return t<0 || ul_hard(t) || t==41 || t==47 || t==9 || t==18;}
// Boundary before active record i. LB9-attached CM/ZWJ have no active record;
// the preceding record retains the last original class for the earlier LB8a.
fn ul_boundary(records,count,i,ri){
    let left=ul_class(records,i-1);let right=ul_class(records,i);let lp=load64(records+(i-1)*32+16);let rp=load64(records+i*32+16);let before=ul_class(records,i-2);let after=-1;if i+1<count{after=ul_class(records,i+1);}
    // LB4..LB8a.
    if left==8{return 2;}if left==14 && right==30{return 0;}if left==14 || left==30 || left==31{return 2;}if ul_hard(right){return 0;}if right==41 || right==47{return 0;}
    let nonspace=i-1;while nonspace>=0 && ul_class(records,nonspace)==41{nonspace=nonspace-1;}let preceding=ul_class(records,nonspace);if preceding==47{return 1;}if load64(records+(i-1)*32+24)==48{return 0;}
    // LB9/LB10 are applied while building records. LB11..LB14.
    if left==45 || right==45 || left==18{return 0;}if right==18 && left!=41 && left!=6 && left!=23 && left!=21{return 0;}if right==11 || right==13 || right==17 || right==42{return 0;}if preceding==34{return 0;}
    // LB15a/b: Pi/Pf are properties of the unresolved QU, including attached
    // combining marks. The lookarounds operate on LB9's filtered sequence.
    if preceding==37 && (load64(records+nonspace*32+16)&256) && ul_initial_context(ul_class(records,nonspace-1)){return 0;}
    if right==37 && (rp&512) && ul_final_context(after){return 0;}
    if left==41 && right==26 && after==33{return 1;}if right==26{return 0;}
    if (preceding==11 || preceding==13) && right==32{return 0;}if preceding==5 && right==5{return 0;}if left==41{return 1;}
    // LB19/19a.
    if (right==37 && !(rp&256)) || (left==37 && !(lp&512)){return 0;}
    if right==37{if !(lp&64) || i+1==count || !(load64(records+(i+1)*32+16)&64){return 0;}}
    if left==37{if !(rp&64) || i<2 || !(load64(records+(i-2)*32+16)&64){return 0;}}
    // LB20..LB24.
    if left==9 || right==9{return 1;}if (left==23 || left==21) && ul_alpha(right) && ul_hyphen_context(before){return 0;}
    if right==6 || right==21 || right==23 || right==32 || left==7{return 0;}if before==22 && (left==23 || left==21) && right!=22{return 0;}if left==42 && right==22{return 0;}if right==25{return 0;}
    if (ul_alpha(left) && right==33) || (left==33 && ul_alpha(right)){return 0;}
    if (left==36 && (right==24 || right==15 || right==16)) || ((left==24 || left==15 || left==16) && right==35){return 0;}
    if ((left==36 || left==35) && ul_alpha(right)) || (ul_alpha(left) && (right==36 || right==35)){return 0;}
    // LB25. Numeric SY/IS suffixes are scanned at a terminating prefix/postfix
    // or digit boundary; earlier LB13/LB15d handle their internal boundaries.
    if right==35 || right==36{let at=i-1;if left==11 || left==13{at=at-1;}while at>=0 && (ul_class(records,at)==42 || ul_class(records,at)==26){at=at-1;}if ul_class(records,at)==33{return 0;}}
    if (left==35 || left==36) && right==34{if after==33{return 0;}if after==26 && i+2<count && ul_class(records,i+2)==33{return 0;}}
    if right==33{if left==35 || left==36 || left==23 || left==26{return 0;}let at=i-1;while at>=0 && (ul_class(records,at)==42 || ul_class(records,at)==26){at=at-1;}if ul_class(records,at)==33{return 0;}}
    // LB26..LB28a.
    if left==27 && (right==27 || right==29 || right==19 || right==20){return 0;}if (left==29 || left==19) && (right==29 || right==28){return 0;}if (left==28 || left==20) && right==28{return 0;}
    if (ul_korean(left) && right==35) || (left==36 && ul_korean(right)){return 0;}if ul_alpha(left) && ul_alpha(right){return 0;}
    if left==3 && ul_aksara(records,i){return 0;}if ul_aksara(records,i-1) && (right==43 || right==44){return 0;}if left==44 && ul_aksara(records,i-2) && ul_aksara_after_virama(records,i){return 0;}
    if ul_aksara(records,i-1) && ul_aksara(records,i) && after==43{return 0;}
    // LB29..LB31.
    if left==26 && ul_alpha(right){return 0;}if (ul_alpha(left) || left==33) && right==34 && !(rp&64){return 0;}if left==13 && !(lp&64) && (ul_alpha(right) || right==33){return 0;}
    if left==38 && right==38 && ri%2==1{return 0;}if right==16 && (left==15 || (lp&3072)==3072){return 0;}return 1;
}
// Owned byte-addressable break map: byte length0, allocation bytes8, opportunity
// count16; masks at32: 0 prohibited/interior UTF-8 byte, 1 soft, 2 mandatory.
// End of text is mandatory, including empty input. LB1 uses recommended default
// class resolution (SA Mn/Mc -> CM, other SA -> AL); no locale dictionaries.
fn unicode_linebreaks(text,n){
    if !text || n<0 || n>1048576{return unicode_fail("Invalid line-break input size");}let at=0;let scalars=0;while at<n{let value=unicode_utf8_read(text,n,at);if value<0{return unicode_fail("Invalid line-break UTF-8");}at=at+(value&7);scalars=scalars+1;if scalars>262144{return unicode_fail("Line-break scalar limit exceeded");}}
    let bytes=33+n;let map=alloc(bytes);if map<=0{return unicode_fail("Cannot allocate line-break result");}store64(map,n);store64(map+8,bytes);store64(map+16,1);store64(map+24,0);let i=0;while i<=n{store8(map+32+i,0);i=i+1;}store8(map+32+n,2);
    let temporary=32+scalars*32;let records=alloc(temporary);if records<=0{syscall(11,map,bytes,0,0,0,0);return unicode_fail("Cannot allocate line-break scratch");}let count=0;at=0;while at<n{let value=unicode_utf8_read(text,n,at);let cp=value>>3;let flags=unicode_line_property(cp);let original=flags&63;let t=original;if t==0 || t==40 || t==46{t=2;}else if t==39{t=2;if flags&128{t=12;}}else if t==10{t=32;}
        let attached=0;if t==12 || t==48{let previous=ul_class(records,count-1);if previous>=0 && !ul_hard(previous) && previous!=41 && previous!=47{store64(records+(count-1)*32+24,original);attached=1;}else{t=2;cp=65;flags=2;}}
        if !attached{let p=records+count*32;store64(p,cp);store64(p+8,at);store64(p+16,(flags&~63)|t);store64(p+24,original);count=count+1;}at=at+(value&7);
    }
    let ri=0;i=1;let opportunities=1;while i<count{if ul_class(records,i-1)==38{ri=ri+1;}else{ri=0;}let mask=ul_boundary(records,count,i,ri);if mask{store8(map+32+load64(records+i*32+8),mask);opportunities=opportunities+1;}i=i+1;}store64(map+16,opportunities);syscall(11,records,temporary,0,0,0,0);return map;
}
fn unicode_linebreaks_free(map){if map{syscall(11,map,load64(map+8),0,0,0,0);}return 0;}
fn unicode_line_break(map,byte){if !map || byte<0 || byte>load64(map){return -1;}return load8(map+32+byte);}
