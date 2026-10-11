// Small native tokenizer CLI, also used by the independent tokenizer verifier.
import "../libs/ml/llm/tokenizer.flex";
import "lib/build.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let path=b_option(argc,argv,"--tokenizer",0);h_assert(path,"provide --tokenizer tokenizer.json");qt_open(path);
    let text=b_option(argc,argv,"--text","");let ids=qt_encode(text);let tokens=j_array();let decoded=h_buffer();let i=0;
    while i<h_count(ids) {let id=h_at(ids,i);j_push(tokens,j_int(id));let piece=qt_decode(id);h_append(decoded,h_data(piece),h_size(piece));i=i+1;}
    let report=j_object();j_set(report,"ids",tokens);j_set(report,"decoded",j_string(h_data(decoded)));h_print(1,j_dump(report));h_print(1,"\n");return 0;
}
