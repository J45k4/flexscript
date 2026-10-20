// Native host utilities shared by kernel generators and benchmark adapters.
import "../../scripts/lib/json.flex";
fn at_integer(object,key,min,max) {let p=j_need(object,key);h_assert(j_kind(p)==1 && j_value(p)>=min && j_value(p)<=max,h_cat("invalid integer: ",key));return j_value(p);}
fn at_name(name) {let size=h_len(name);if !size || size>96 {return 0;}let i=0;while i<size {let c=load8(name+i);if !((c>=48 && c<=57) || (c>=65 && c<=90) || (c>=97 && c<=122) || c==45 || c==95) {return 0;}i=i+1;}return 1;}
fn at_power(value) {return value>0 && !(value&(value-1));}
fn at_relative(directory,path) {
    directory=h_real(directory);path=h_real(path);let i=0;let common=0;while load8(directory+i) && load8(directory+i)==load8(path+i) {if load8(path+i)==47 {common=i+1;}i=i+1;}
    if !load8(directory+i) && load8(path+i)==47 {common=i+1;}
    let out=h_buffer();let start=common;while start<h_len(directory) {h_text(out,"../");while load8(directory+start) && load8(directory+start)!=47 {start=start+1;}start=start+1;}h_text(out,path+common);return h_data(out);
}
fn at_run(args,log) {let p=h_run(args);let text=h_cat(h_out(p),h_err(p));h_save(log,text);if h_status(p) {h_print(2,h_err(p));h_die(h_cat3("autotune child failed; log: ",log,h_cat("; exit ",h_int(h_status(p)))));}return h_out(p);}
fn at_stats(samples) {
    let count=j_count(samples);h_assert(count>0 && count<=100,"invalid timing count");let sorted=h_take(count*8);let sum=0;let i=0;
    while i<count {let p=j_at(samples,i);h_assert(j_kind(p)==1 && j_value(p)>0 && j_value(p)<=1000000000000,"invalid nanosecond timing");let value=j_value(p);sum=sum+value;let j=i;while j>0 && load64(sorted+(j-1)*8)>value {store64(sorted+j*8,load64(sorted+(j-1)*8));j=j-1;}store64(sorted+j*8,value);i=i+1;}
    let out=j_object();j_set(out,"mean_ns",j_int(sum/count));j_set(out,"median_ns",j_int(load64(sorted+(count/2)*8)));j_set(out,"min_ns",j_int(load64(sorted)));return out;
}
