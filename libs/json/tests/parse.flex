import "json/tree.flex";

fn main() {
    // Objects, nesting, numbers, booleans and null.
    let v=j_parse("{\"name\":\"puppy\",\"count\":42,\"ok\":true,\"gap\":null,\"list\":[1,-2,3.5,\"two\"]}");
    m_assert(j_kind(v)==4,"object kind");
    let name=j_string(v,"name");
    m_assert(m_eq(name,"puppy"),"string member");
    m_assert(j_integer(v,"count")==42,"integer member");
    let ok=j_get(v,"ok");
    m_assert(j_kind(ok)==5 && j_value(ok)==1,"boolean member");
    let gap=j_get(v,"gap");
    m_assert(j_kind(gap)==0,"null member");
    let list=j_get(v,"list");
    m_assert(j_kind(list)==3,"array kind");
    let first=load64(list+16);
    m_assert(j_kind(first)==1 && j_value(first)==1,"first array element");
    let second=load64(first+24);
    m_assert(j_kind(second)==1 && j_value(second)==-2,"negative array element");
    let third=load64(second+24);
    m_assert(j_kind(third)==6,"float stays raw text");
    let raw=j_value(third);
    m_assert(m_eq(raw,"3.5"),"raw float text");
    let fourth=load64(third+24);
    let item=j_value(fourth);
    m_assert(j_kind(fourth)==2 && m_eq(item,"two"),"string array element");
    // Round trip through the writer.
    let text=j_encode(v);
    m_assert(m_eq(text,"{\"name\":\"puppy\",\"count\":42,\"ok\":true,\"gap\":null,\"list\":[1,-2,3.5,\"two\"]}"),"encode round trip");
    // String escapes and surrogate pairs.
    let e=j_parse("\"\\u0041\\n\\t\\\\\"");
    let evalue=j_value(e);
    m_assert(j_kind(e)==2 && m_eq(evalue,"A\n\t\\"),"escape decoding");
    let s=j_parse("\"\\ud83d\\udc36\"");
    let svalue=j_value(s);
    m_assert(j_kind(s)==2 && m_len(svalue)==4,"surrogate pair becomes four UTF-8 bytes");
    m_assert(j_parse("\"\\ud83d\"")==0,"lone surrogate rejected");
    m_assert(j_parse("\"\\u0000\"")==0,"embedded NUL rejected");
    // Well-formedness rejections.
    m_assert(j_parse("{\"a\":1,\"a\":2}")==0,"duplicate key rejected");
    m_assert(j_parse("[1,2")==0,"unterminated array rejected");
    m_assert(j_parse("{\"a\":1}}")==0,"trailing garbage rejected");
    m_assert(j_parse("01")==0,"leading zero rejected");
    m_assert(j_parse("{")==0,"unterminated object rejected");
    m_assert(j_parse("{\"a\"}")==0,"missing colon rejected");
    m_assert(j_parse("[,]")==0,"leading comma rejected");
    m_assert(j_parse("tru")==0,"truncated literal rejected");
    // Nesting bound: twenty levels parse, forty do not.
    let deep="";
    let i=0;
    while i<20 {deep=m_cat(deep,"[");i=i+1;}
    i=0;
    while i<20 {deep=m_cat(deep,"]");i=i+1;}
    let shallow=j_parse(deep);
    m_assert(j_kind(shallow)==3,"twenty levels parse");
    deep="";
    i=0;
    while i<40 {deep=m_cat(deep,"[");i=i+1;}
    i=0;
    while i<40 {deep=m_cat(deep,"]");i=i+1;}
    m_assert(j_parse(deep)==0,"forty levels exceed the depth bound");
    // Missing members read as empty without dying.
    let missing=j_string(v,"missing");
    m_assert(m_eq(missing,""),"missing string reads empty");
    m_assert(j_integer(v,"missing")==0,"missing integer reads zero");
    m_print(1,"json parse tests passed\n");
    return 0;
}
