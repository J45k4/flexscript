// Pinned official-tokenizer goldens; no Python dependency during this test.
import "../libs/ml/llm/tokenizer.flex";
import "lib/build.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let path=b_option(argc,argv,"--tokenizer",0);h_assert(path,"provide --tokenizer tokenizer.json");
    let fixture=j_parse(h_read("libs/ml/llm/tests/tokenizer.json"));h_assert(h_equal(h_sha(path),j_s(fixture,"tokenizer_sha256")),"goldens require the pinned Qwen3 tokenizer");
    qt_open(path);let cases=j_need(fixture,"cases");let i=0;let checks=0;
    while i<j_count(cases) {let item=j_at(cases,i);let actual=qt_encode(j_s(item,"text"));let expected=j_need(item,"ids");h_assert(h_count(actual)==j_count(expected),"tokenizer length differs from official oracle");
        let decoded=h_buffer();let j=0;while j<h_count(actual) {h_assert(h_at(actual,j)==j_value(j_at(expected,j)),"tokenizer ID differs from official oracle");let piece=qt_decode(h_at(actual,j));h_append(decoded,h_data(piece),h_size(piece));checks=checks+1;j=j+1;}
        h_assert(h_equal(h_data(decoded),j_s(item,"decoded")),"decoded bytes differ from official oracle");checks=checks+1;i=i+1;}
    h_print(1,h_cat3("Tokenizer checks: ",h_int(checks),"\n"));return 0;
}
