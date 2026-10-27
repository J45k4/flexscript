import "../../libs/unicode.flex";
import "../../scripts/lib/json.flex";
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==3,"grapheme requests.json property-output.bin");let requests=j_parse(h_read(load64(argv+8)));let result=j_array();let i=0;
    while i<j_count(requests){let hex=j_value(j_at(requests,i));let n=h_len(hex)/2;let text=h_unhex(hex);let map=unicode_graphemes(text,n);h_assert(map,unicode_error);let offsets=j_array();let k=0;while k<load64(map){j_push(offsets,j_int(load64(map+32+k*8)));k=k+1;}j_push(result,offsets);unicode_graphemes_free(map);i=i+1;}
    let invalid=j_parse("[\"80\",\"c0af\",\"c220\",\"e282\",\"eda080\",\"f09080\",\"f4908080\",\"f5808080\",\"ff\"]");i=0;while i<j_count(invalid){let hex=j_value(j_at(invalid,i));h_assert(!unicode_graphemes(h_unhex(hex),h_len(hex)/2),"Invalid UTF-8 was accepted");i=i+1;}
    let guard=alloc(32);store64(guard+8,0x1234);h_assert(!unicode_grapheme_scan("a",1,guard,1) && load64(guard+8)==0x1234,"Grapheme scan wrote beyond capacity");h_assert(unicode_grapheme_scan("",0,guard,1)==1 && !load64(guard),"Empty grapheme scan");syscall(11,guard,32,0,0,0,0);
    let text="á👨‍👩‍👧‍👦x";let map=unicode_graphemes(text,h_len(text));h_assert(map && load64(map)==4 && unicode_grapheme_next(map,0)==3 && unicode_grapheme_next(map,3)==28 && unicode_grapheme_previous(map,28)==3 && unicode_grapheme_previous(map,3)==0 && unicode_grapheme_next(map,29)==29,"Grapheme navigation split an accent or emoji sequence");unicode_graphemes_free(map);
    let properties=alloc(1114112);h_assert(properties>0,"Property output allocation");i=0;while i<1114112{store8(properties+i,unicode_grapheme_property(i));i=i+1;}h_save_bytes(load64(argv+16),properties,1114112,420);syscall(11,properties,1114112,0,0,0,0);h_print(1,h_cat(j_dump(result),"\n"));return 0;
}
