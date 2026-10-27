// UAX #29, Unicode 17.0.0 extended grapheme clusters (GB1..GB999).
// Length-delimited, strict UTF-8. No locale, allocation or external call in scan.
import "utf8.flex";
import "properties.flex";
fn unicode__unpack(p,digits){let value=0;let i=0;while i<digits{value=(value<<6)|(load8(p+i)-63);i=i+1;}return value;}
fn unicode_grapheme_property(cp){
    if cp<128{if cp==13{return 1;}if cp==10{return 2;}if cp<32 || cp==127{return 3;}return 0;}
    if cp>=0xac00 && cp<=0xd7a3{if (cp-0xac00)%28==0{return 12;}return 13;}
    let data=unicode_property_data();let low=0;let high=unicode_property_count();while low<high{let mid=(low+high)/2;let p=data+mid*10;let start=unicode__unpack(p,4);if cp<start{high=mid;}else{let end=unicode__unpack(p+4,4);if cp>end{low=mid+1;}else{return unicode__unpack(p+8,2);}}}return 0;
}
// Writes byte offsets including start/end, or counts them if out==0. Returns
// count, or 0 on invalid input/short output. n is bounded to 1 MiB for GUI use.
fn unicode_grapheme_scan(text,n,out,capacity){
    if !text || n<0 || n>1048576 || (out && capacity<1){return unicode_fail("Invalid grapheme input/output size");}let count=1;if out{store64(out,0);}let at=0;let previous=-1;let ri=0;let ep=0;let zwj=0;let incb=0;
    while at<n{let read=unicode_utf8_read(text,n,at);if read<0{return unicode_fail("Invalid UTF-8 grapheme input");}let flags=unicode_grapheme_property(read>>3);let current=flags&15;let pictographic=(flags&16)!=0;let indic=flags&96;let boundary=at>0;
        if at>0{
            if previous==1 && current==2{boundary=0;}
            else if previous==1 || previous==2 || previous==3 || current==1 || current==2 || current==3{boundary=1;}
            else if previous==9 && (current==9 || current==10 || current==12 || current==13){boundary=0;}
            else if (previous==12 || previous==10) && (current==10 || current==11){boundary=0;}
            else if (previous==13 || previous==11) && current==11{boundary=0;}
            else if current==4 || current==5 || current==8 || previous==7{boundary=0;}
            else if incb==2 && indic==96{boundary=0;}
            else if previous==5 && zwj && pictographic{boundary=0;}
            else if previous==6 && current==6 && ri%2==1{boundary=0;}
        }
        if boundary{if out{if count>=capacity{return unicode_fail("Grapheme output capacity exceeded");}store64(out+count*8,at);}count=count+1;}
        zwj=current==5 && ep;if pictographic{ep=1;}else if current!=4{ep=0;}
        if indic==96{incb=1;}else if indic==64{if incb{incb=2;}}else if indic!=32{incb=0;}
        if current==6{ri=ri+1;}else{ri=0;}previous=current;at=at+(read&7);
    }
    if n{if out{if count>=capacity{return unicode_fail("Grapheme output capacity exceeded");}store64(out+count*8,n);}count=count+1;}return count;
}
// Owned map: count0, UTF-8 bytes8, allocation bytes16, then offsets32.
fn unicode_graphemes(text,n){let count=unicode_grapheme_scan(text,n,0,0);if !count{return 0;}let bytes=32+count*8;let p=alloc(bytes);if p<0{return unicode_fail("Cannot allocate grapheme map");}store64(p,count);store64(p+8,n);store64(p+16,bytes);store64(p+24,0);if !unicode_grapheme_scan(text,n,p+32,count){syscall(11,p,bytes,0,0,0,0);return 0;}return p;}
fn unicode_graphemes_free(p){if p{syscall(11,p,load64(p+16),0,0,0,0);}return 0;}
fn unicode_boundary_lower(offsets,count,offset){let low=0;let high=count;while low<high{let mid=(low+high)/2;if load64(offsets+mid*8)<offset{low=mid+1;}else{high=mid;}}return low;}
fn unicode_grapheme_lower(p,offset){return unicode_boundary_lower(p+32,load64(p),offset);}
fn unicode_grapheme_next(p,offset){let i=unicode_grapheme_lower(p,offset+1);if i>=load64(p){return load64(p+8);}return load64(p+32+i*8);}
fn unicode_grapheme_previous(p,offset){let i=unicode_grapheme_lower(p,offset);if i<=0{return 0;}return load64(p+32+(i-1)*8);}
