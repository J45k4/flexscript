import "../../apps/collie/lib/json.flex";
import "../../lib/bytes.flex";
global jc_source=0;global jc_destination=0;global jc_pointers=0;
fn jc_contains(blocks,p){while blocks{if p>=blocks && p<blocks+load64(blocks+8){return 1;}blocks=load64(blocks);}return 0;}
fn jc_pointer(p){h_assert(p && !jc_contains(jc_source,p) && jc_contains(jc_destination,p),"JSON copy retained source or foreign storage");jc_pointers=jc_pointers+1;return 0;}
fn jc_owned(node){
    jc_pointer(node);let kind=j_kind(node);let value=j_value(node);if kind==2 || kind==6{jc_pointer(value);}if kind==3 || kind==4{jc_pointer(value-8);let i=0;while i<h_count(value){let item=h_at(value,i);if kind==4{jc_pointer(item);jc_pointer(load64(item));item=load64(item+8);}jc_owned(item);i=i+1;}}return 0;
}
fn jc_scrub(node){let kind=j_kind(node);let value=j_value(node);if kind==2 || kind==6{bytes_fill(value,90,h_len(value));}if kind==1 || kind==5{store64(node+8,0);}if kind==3 || kind==4{let i=0;while i<h_count(value){let item=h_at(value,i);if kind==4{let key=load64(item);bytes_fill(key,88,h_len(key));item=load64(item+8);}jc_scrub(item);i=i+1;}}return 0;}
fn jc_bad(mode){
    let source=j_int(1);
    if h_equal(mode,"depth"){let i=0;while i<64{let array=j_array();j_push(array,source);source=array;i=i+1;}}
    else if h_equal(mode,"cycle"){source=j_array();j_push(source,source);}
    else if h_equal(mode,"kind"){source=j_node(9,0);}
    else if h_equal(mode,"number"){source=j_node(6,"1,\"extra\":true");}
    else if h_equal(mode,"size"){let values=h_vec_sized(65537);store64(values,65537);source=j_node(3,values);}
    else if h_equal(mode,"object-size"){let values=h_vec_sized(4097);store64(values,4097);source=j_node(4,values);}
    else if h_equal(mode,"duplicate"){source=j_object();j_set(source,"same",j_node(0,0));let pair=h_take(16);store64(pair,"same");store64(pair+8,j_bool(0));h_add_sized(j_value(source),pair);}
    else{h_die("Unknown negative JSON copy fixture");}
    j_copy(source);h_die("Invalid JSON copy unexpectedly succeeded");return 0;
}
fn main(argc,argv){
    h_environment(argc,argv);if argc==3 && h_equal(load64(argv+8),"--bad"){return jc_bad(load64(argv+16));}h_assert(argc==3,"input.json output.json OR --bad mode");
    h_blocks=0;h_used=0;h_capacity=0;let source=c_json(h_read(load64(argv+8)));jc_source=h_blocks;let text=j_dump(source);let expected_bytes=h_len(text);let expected=alloc(expected_bytes+1);bytes_copy(expected,text,expected_bytes+1);jc_source=h_blocks;let parser_source=j_source;let parser_offset=j_offset;let parser_depth=j_depth;
    h_blocks=0;h_used=0;h_capacity=0;let copy=j_copy(source);jc_destination=h_blocks;h_assert(j_source==parser_source && j_offset==parser_offset && j_depth==parser_depth,"JSON copy changed parser state");jc_owned(copy);h_assert(h_equal(expected,j_dump(copy)),"JSON copy changed canonical serialized values/order");
    jc_scrub(source);h_assert(h_equal(expected,j_dump(copy)),"Mutating the original JSON changed its copy");let old=jc_source;while old{let next=load64(old);syscall(11,old,load64(old+8),0,0,0,0);old=next;}jc_source=0;h_assert(h_equal(expected,j_dump(copy)),"Freeing the source arena changed the JSON copy");h_save(load64(argv+16),j_dump(copy));
    // Collections must remain mutable with ordinary power-of-two growth.
    let array=j_array();let i=0;while i<19{j_push(array,j_int(i));i=i+1;}let grown=j_copy(array);i=19;while i<80{j_push(grown,j_int(i));i=i+1;}h_assert(j_count(array)==19 && j_count(grown)==80 && j_value(j_at(grown,79))==79,"Copied array growth changed source or lost values");let object=j_object();i=0;while i<19{j_set(object,h_int(i),j_int(i));i=i+1;}grown=j_copy(object);i=19;while i<80{j_set(grown,h_int(i),j_int(i));i=i+1;}h_assert(j_count(object)==19 && j_count(grown)==80 && j_n(grown,"79")==79,"Copied object growth changed source or lost fields");
    let smallest=j_copy(j_int((-9223372036854775807-1)));let largest=j_copy(j_int(9223372036854775807));h_assert(j_kind(smallest)==1 && j_value(smallest)== (-9223372036854775807-1) && j_kind(largest)==1 && j_value(largest)==9223372036854775807,"Signed integer copy changed kind/value");h_assert(j_value(j_copy(j_node(5,99)))==1 && !j_value(j_copy(j_node(0,99))),"JSON boolean/null copy is not canonical");
    h_print(1,h_cat3("PASS owned JSON copy, parser independence, source mutation/free, collection growth; checked ",h_int(jc_pointers)," owned pointers\n"));syscall(11,expected,expected_bytes+1,0,0,0,0);h_reset(0);return 0;
}
