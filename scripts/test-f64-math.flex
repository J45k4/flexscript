// Exact libm binary64 fixture comparisons performed by the guest on four routes.
import "lib/harness.flex";
import "lib/build.flex";
fn suite(compiler) {
	t_init(compiler);h_timeout=90000;
	let proof=j_parse(h_read("tests/tooling/f64-math-goldens.json"));let sources=j_need(proof,"sources");let k=0;
	while k<j_count(sources) {let key=load64(h_at(j_value(sources),k));t_assert(h_equal(h_sha(key),j_value(j_get(sources,key))),"libm binary64 oracle source provenance");k=k+1;}
	t_assert(j_n(proof,"records")==82506 && j_n(proof,"recordWords")==4,"complete libm binary64 fixture shape");
	let original=h_real("tests/tooling/f64-math-goldens.words");let fixtures=j_need(proof,"fixtures");k=0;
	while k<j_count(fixtures) {let key=load64(h_at(j_value(fixtures),k));t_assert(h_equal(h_sha(key),j_value(j_get(fixtures,key))),"libm fixture checksum");k=k+1;}
	let fixture=h_join(t_work,"batch.words");
	let data=h_read(original);t_assert(h_file_size==82506*32,"complete libm binary64 fixture bytes");
	let text=h_cat3("import \"",h_real("lib/f64-math.flex"),"\";\n");
	text=h_cat(text,"fn execute(op,a,b){if op==0{return f64_hypot(a,b);}if op==1{return f64_atan(a);}if op==2{return f64_atan2(a,b);}if op==3{return f64_exp(a);}if op==4{return f64_scalbn(a,b);}if op==5{return f64_sin(a);}if op==6{return f64_cos(a);}return -1;}\n");
	text=h_cat3(text,"fn main(){let fd=syscall(2,\"",h_cat(fixture,"\",0,0,0,0,0);if fd<0{return 1;}let p=alloc(32);let count=0;let active=1;while active{let n=0;while n<32{let k=syscall(0,fd,p+n,32-n,0,0,0);if k<0{return 2;}if k==0{if n!=0{return 3;}active=0;n=32;}else{n=n+k;}}if active{if execute(load64(p),load64(p+8),load64(p+16))!=load64(p+24){return 4;}count=count+1;}}syscall(3,fd,0,0,0,0,0);if count>0{return 0;}return 5;}\n"));
	t_program(text);t_compile();
	let wasm=h_join(t_work,"f64-math.wasm");h_ok(h_args(t_compiler,"--target","wasm32",t_fixture,"-o",wasm));
	let start=0;while start<82506 {let count=82506-start;if count>10000 {count=10000;}
		h_save_bytes(fixture,data+start*32,count*32,384);
		h_check(h_run(h_args(t_binary,0,0,0,0,0)),0,"");t_checks=t_checks+count;
		let args=h_args(t_compiler,"run","--restricted","--interpret","--fuel=1000000000","--timeout-ms=60000");h_add(args,h_cat("--allow-read=",t_work));h_add(args,t_fixture);h_check(h_run(args),0,"");t_checks=t_checks+count;
		args=h_args(t_compiler,"run","--restricted","--jit","--fuel=1000000000","--timeout-ms=60000");h_add(args,h_cat("--allow-read=",t_work));h_add(args,t_fixture);h_check(h_run(args),0,"");t_checks=t_checks+count;
		let process=h_ok(h_args(h_executable("bun"),"scripts/f64-wasm.js",wasm,fixture,0,0));let result=j_parse(h_out(process));t_assert(j_n(result,"valid") && h_equal(j_s(result,"result"),"0"),"Wasm exact libm bit trace");t_checks=t_checks+count;
		start=start+count;
	}

	return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
