// Alternating native/HIP GPU OS comparison through the same standalone host.
// Each sample reloads the model; reported decode excludes prefill/first token.
import "build-lib.flex";
fn gbm_run(binary,compiler,image,checkpoint,prompt,tokens,context,path) {
 let args=h_args(binary,"--compiler",compiler,"--image",image,"--checkpoint");h_add(args,checkpoint);h_add(args,"--context");h_add(args,context);h_add(args,"--max-tokens");h_add(args,tokens);h_add(args,"--prompt");h_add(args,prompt);h_add(args,"--report");h_add(args,path);
 h_ok(args);let report=j_parse(h_read(path));let elapsed=j_n(report,"decode_us")-j_n(report,"first_token_us");let calls=j_n(report,"decode_calls");h_assert(calls>0 && elapsed>0,"benchmark needs at least two generated tokens");
 j_set(report,"decode_steps_per_second_x1000",j_int(calls*1000000000/elapsed));return report;
}
fn gbm_median(values) {
 let i=1;while i<h_count(values) {let value=h_at(values,i);let j=i;while j>0 && h_at(values,j-1)>value {store64(values+8+j*8,h_at(values,j-1));j=j-1;}store64(values+8+j*8,value);i=i+1;}
 let n=h_count(values);if n&1 {return h_at(values,n/2);}return (h_at(values,n/2-1)+h_at(values,n/2))/2;
}
fn main(argc,argv) {
 h_environment(argc,argv);h_timeout=300000;
 let compiler=h_real(b_option(argc,argv,"--compiler","build/flex"));let binary=h_real(b_option(argc,argv,"--binary","build/gpu-os/qwen"));let checkpoint=h_real(b_option(argc,argv,"--checkpoint","build/llm/models/qwen3-1.7b"));
 let directory=b_option(argc,argv,"--output","build/gpu-os/native-benchmark");h_mkdir(directory);directory=h_real(directory);let rounds=h_number(b_option(argc,argv,"--rounds","3"));h_assert(rounds>0 && rounds<=100,"invalid rounds");
 let tokens=b_option(argc,argv,"--tokens","128");let context=b_option(argc,argv,"--context","1024");let images=h_vec();let names=h_vec();let baseline=b_option(argc,argv,"--baseline",0);
 if baseline {h_add(images,h_real(baseline));h_add(names,"baseline-rdna");}
 h_add(images,gb_build(compiler,h_join(directory,"native"),"rdna",0,"hip","none"));h_add(names,"native-rdna");
 h_add(images,gb_build(compiler,h_join(directory,"hip"),"hip",0,"hip","none"));h_add(names,"hip");
 let prompts=h_vec();let short="Write a long, detailed adventure story about a little robot exploring a forest. Include scenery, dialogue, and several events. Keep telling the story.";
 h_add(prompts,short);let background=h_buffer();let i=0;while i<8 {h_text(background,"The forest has tall trees, a river, old stone bridges, hidden caves, friendly animals, and an abandoned observatory. The robot carries a map and wants to learn how the forest changes through the seasons. ");i=i+1;}h_text(background,"\n");h_text(background,short);h_add(prompts,h_data(background));
 let result=j_object();j_set(result,"timing",j_string("Profiling off; each run reloads weights. Decode steps/s excludes prefill and first token; includes GPU sampling, mailbox publication and host polling."));j_set(result,"compiler_sha256",j_string(h_sha(compiler)));j_set(result,"context",j_int(h_number(context)));j_set(result,"max_tokens",j_int(h_number(tokens)));j_set(result,"rounds",j_int(rounds));
 let samples=j_array();let summaries=j_array();j_set(result,"samples",samples);j_set(result,"summaries",summaries);let workload=0;
 while workload<h_count(prompts) {let gold=0;let reference_tokens=0;let round=0;while round<=rounds {let turn=0;while turn<h_count(images) {let index=(turn+round)%h_count(images);if round&1 {index=h_count(images)-index-1;}
   let name=h_at(names,index);let path=h_join(directory,h_cat3(h_cat3("prompt-",h_int(workload),"-"),h_cat3(h_int(round),"-",name),".json"));let sample=gbm_run(binary,compiler,h_at(images,index),checkpoint,h_at(prompts,workload),tokens,context,path);
   let ids=j_dump(j_get(sample,"generated_ids"));if !gold {gold=ids;reference_tokens=j_n(sample,"tokens");}h_assert(h_equal(ids,gold) && j_n(sample,"tokens")==reference_tokens,"benchmark token mismatch across runtimes");
   j_set(sample,"regime",j_string(name));j_set(sample,"workload",j_int(workload));j_set(sample,"round",j_int(round));j_push(samples,sample);j_save(h_join(directory,"results.json"),result);
   let rate=j_n(sample,"decode_steps_per_second_x1000");h_print(1,h_cat3(h_cat3("Prompt ",h_int(workload),h_cat3(" round ",h_int(round)," ")),name,h_cat3(": ",h_int(rate)," /1000 decode steps/s\n")));turn=turn+1;
  }round=round+1;}
  i=0;while i<h_count(images) {let rates=h_vec();let j=0;while j<j_count(samples) {let sample=j_at(samples,j);if j_n(sample,"workload")==workload && j_n(sample,"round")>0 && h_equal(j_s(sample,"regime"),h_at(names,i)) {h_add(rates,j_n(sample,"decode_steps_per_second_x1000"));}j=j+1;}
   let summary=j_object();j_set(summary,"regime",j_string(h_at(names,i)));j_set(summary,"workload",j_int(workload));j_set(summary,"median_x1000",j_int(gbm_median(rates)));j_set(summary,"min_x1000",j_int(h_at(rates,0)));j_set(summary,"max_x1000",j_int(h_at(rates,h_count(rates)-1)));j_push(summaries,summary);i=i+1;}
  workload=workload+1;
 }
 j_save(h_join(directory,"results.json"),result);h_print(1,h_cat3("Matching tokens in all runs; results: ",directory,"/results.json\n"));return 0;
}
