import "../parser.flex";
global pgt_checks=0;
fn pgt_assert(ok) {if !ok {pg_error("Pup reference test failed");}pgt_checks=pgt_checks+1;return 0;}
fn pgt_parse(text) {return pup_parse(text,pg_len(text),"reference.pup");}
fn pgt_memory() {
    let memory=alloc(pg_words*8);let p=0;
    while p<pg_param_count {let v=load64(pg_params+p*8);let i=0;
        while i<pg_size(v) {store64(memory+(load64(v+64)+i)*8,gpu_f32_from_i64(i+1));i=i+1;}p=p+1;
    }return memory;
}
fn pgt_at(memory,output,i) {let v=load64(pg_outputs+output*8);return load64(memory+(load64(v+64)+i)*8);}
fn pgt_int(memory,output,i,value) {return pgt_assert(pgt_at(memory,output,i)==gpu_f32_from_i64(value));}
fn pgt_suite() {
    pgt_checks=0;
    pgt_parse("# primitive tensor graph\na=input(\"a\",[2,3])\nb=input(\"b\",[3])\nx=a+b*10\nt=permute(a,[1,0])\noutput x,reduce(x,add,1),t,reduce(t,add,1),reduce(a,add,2)\n");
    let memory=pgt_memory();pg_execute(memory);let i=0;
    while i<6 {pgt_int(memory,0,i,i+1+(i%3+1)*10);i=i+1;}
    pgt_int(memory,1,0,25);pgt_int(memory,1,1,47);pgt_int(memory,1,2,69);
    pgt_int(memory,2,1,4);pgt_int(memory,2,4,3);pgt_int(memory,3,0,6);pgt_int(memory,3,1,15);pgt_int(memory,4,0,21);
    // Output x is also consumed by a reduction: it must execute first.
    pgt_assert(load64(pg_stages)==load64(pg_outputs));
    pgt_parse("a=input(\"a\",[2,3])\nb=input(\"b\",[3,2])\nm=matmul(a,b)\noutput m,m+m,reduce(m,add,2)\n");
    memory=pgt_memory();pg_execute(memory);pgt_int(memory,0,0,22);pgt_int(memory,0,1,28);pgt_int(memory,0,2,49);pgt_int(memory,0,3,64);pgt_int(memory,1,2,98);pgt_int(memory,2,0,163);
    let node=0;while node<pg_count {pgt_assert(load64(load64(pg_nodes+node*8))!=12);node=node+1;}
    pgt_parse("a=input(\"a\",[2,1,3])\nb=input(\"b\",[1,4,1])\noutput a+b\n");
    memory=pgt_memory();pg_execute(memory);i=0;while i<24 {pgt_int(memory,0,i,(i/12)*3+i%3+1+(i/3)%4+1);i=i+1;}
    pgt_parse("a=reshape(param(7,f32,6),stack(2,3))\noutput reshape(a,[3,2]),dim(a,1),cast(reduce(a,max,1),f32)\n");
    memory=pgt_memory();pg_execute(memory);pgt_int(memory,0,4,5);pgt_int(memory,1,0,3);pgt_int(memory,2,0,4);pgt_int(memory,2,2,6);
    pgt_parse("output -1.25e1 / 2 + .5,max(-0.0,0.0),--3,2*3+4,2*(3+4)\n");
    memory=pgt_memory();pg_execute(memory);pgt_assert(pgt_at(memory,0,0)==gpu_f32_div(gpu_f32_from_i64(-23),gpu_f32_from_i64(4)));pgt_assert(pgt_at(memory,1,0)==0);pgt_int(memory,2,0,3);pgt_int(memory,3,0,10);pgt_int(memory,4,0,14);
    pgt_assert(pg_max(0x7fa00001,0)==0x7fc00000);pgt_assert(pg_max(0x80000000,0)==0);pgt_assert(pg_max(0x80000000,0x80000000)==0x80000000);
    pgt_parse("a=input(\"a\",[2,3])\nw=input(\"w\",[2,3])\nb=input(\"b\",[2])\noutput linear(a,w,b)\n");
    memory=pgt_memory();pg_execute(memory);pgt_int(memory,0,0,15);pgt_int(memory,0,1,34);pgt_int(memory,0,2,33);pgt_int(memory,0,3,79);
    return pgt_checks;
}
