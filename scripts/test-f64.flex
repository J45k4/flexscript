// Exact binary64 fixture comparisons performed by the guest on four routes.
import "lib/harness.flex";
import "lib/build.flex";
fn suite(compiler) {
	t_init(compiler);h_timeout=90000;
	let proof=j_parse(h_read("tests/tooling/f64-goldens.json"));let sources=j_need(proof,"sources");let k=0;
	while k<j_count(sources) {let key=load64(h_at(j_value(sources),k));t_assert(h_equal(h_sha(key),j_value(j_get(sources,key))),"binary64 oracle source provenance");k=k+1;}
	t_assert(j_n(proof,"records")==64498 && j_n(proof,"recordWords")==4,"complete binary64 fixture shape");
	let fixture=h_real("tests/tooling/f64-goldens.words");t_assert(h_equal(h_sha(fixture),j_s(proof,"fixtureSha256")),"binary64 fixture checksum");
	let data=h_read(fixture);t_assert(h_file_size==64498*32,"complete binary64 fixture bytes");
	let text=h_cat3("import \"",h_real("lib/f64.flex"),"\";\n");
	text=h_cat(text,"fn execute(op,a,b){if op==0{return f64_add(a,b);}if op==1{return f64_sub(a,b);}if op==2{return f64_mul(a,b);}if op==3{return f64_div(a,b);}if op==4{return f64_lt(a,b);}if op==5{return f64_eq(a,b);}if op==6{return f64_le(a,b);}if op==7{return f64_from_i64(a);}if op==8{return f64_to_i64_trunc(a);}if op==9{return f64_to_i64_nearest(a);}if op==10{return f64_to_i64_round(a);}if op==11{return f64_gt(a,b);}if op==12{return f64_ge(a,b);}if op==13{return f64_ne(a,b);}if op==14{return f64_sqrt(a);}return -1;}\n");
	text=h_cat3(text,"fn main(){let fd=syscall(2,\"",h_cat(fixture,"\",0,0,0,0,0);if fd<0{return 1;}let p=alloc(32);let count=0;let active=1;while active{let n=0;while n<32{let k=syscall(0,fd,p+n,32-n,0,0,0);if k<0{return 2;}if k==0{if n!=0{return 3;}active=0;n=32;}else{n=n+k;}}if active{if execute(load64(p),load64(p+8),load64(p+16))!=load64(p+24){return 4;}count=count+1;}}syscall(3,fd,0,0,0,0,0);if count==64498{return 0;}return 5;}\n"));
	t_program(text);t_compile();h_check(h_run(h_args(t_binary,0,0,0,0,0)),0,"");t_checks=t_checks+64498;
	let args=h_args(t_compiler,"run","--restricted","--interpret","--fuel=1000000000","--timeout-ms=60000");h_add(args,h_cat("--allow-read=",h_dir(fixture)));h_add(args,t_fixture);h_check(h_run(args),0,"");t_checks=t_checks+64498;
	args=h_args(t_compiler,"run","--restricted","--jit","--fuel=1000000000","--timeout-ms=60000");h_add(args,h_cat("--allow-read=",h_dir(fixture)));h_add(args,t_fixture);h_check(h_run(args),0,"");t_checks=t_checks+64498;
	let wasm=h_join(t_work,"f64.wasm");h_ok(h_args(t_compiler,"--target","wasm32",t_fixture,"-o",wasm));
	let process=h_ok(h_args(h_executable("bun"),"scripts/f64-wasm.js",wasm,fixture,0,0));let result=j_parse(h_out(process));t_assert(j_n(result,"valid") && h_equal(j_s(result,"result"),"0"),"Wasm exact binary64 fixture trace");t_checks=t_checks+64498;
	return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
