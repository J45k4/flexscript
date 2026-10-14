// Reproducible native comparison. Only the SQLite comparator needs C/sqlite3.
import "lib/json.flex";
fn pin() {
    let mask=h_zero(h_take(128),128);let bytes=syscall(204,0,128,mask,0,0,0);h_assert(bytes>0,"CPU affinity");let cpu=0;
    while cpu<bytes*8 && !(load8(mask+cpu/8)&(1<<(cpu%8))) {cpu=cpu+1;}h_assert(cpu<bytes*8,"allowed CPU");h_zero(mask,128);store8(mask+cpu/8,1<<(cpu%8));h_assert(syscall(203,0,128,mask,0,0,0)==0,"pin CPU");return cpu;
}
fn median(samples,key,runs) {
    let numbers=h_vec();let i=1;while i<=runs {h_add(numbers,j_n(j_at(samples,i),key));i=i+1;}
    i=1;while i<runs {let j=i;while j>0 && h_at(numbers,j)<h_at(numbers,j-1) {let a=h_at(numbers,j);let b=h_at(numbers,j-1);store64(numbers+8+j*8,b);store64(numbers+j*8,a);j=j-1;}i=i+1;}return h_at(numbers,runs/2);
}
fn main(argc,argv) {
    h_environment(argc,argv);h_assert(argc>=2 && argc<=5,"compiler [rows=50000] [runs=7, odd] [report.json]");let compiler=h_real(load64(argv+8));let rows=50000;let runs=7;if argc>2 {rows=h_number(load64(argv+16));}if argc>3 {runs=h_number(load64(argv+24));}h_assert(rows>=1000 && rows<=100000 && rows%100==0 && runs>=3 && runs<=15 && runs%2==1,"row/run bounds");
    let cpu=pin();let work=h_temp();let flex=h_join(work,"flexdb");let sqlite=h_join(work,"sqlite");h_compile(compiler,"scripts/bench-flexdb-worker.flex",flex);
    let command=h_args("cc","-O3","scripts/bench-flexdb-sqlite.c","-o",sqlite,"-lsqlite3");h_ok(command);let version=h_out(h_ok(h_args("sqlite3","--version",0,0,0,0)));
    let names=h_args("flexdb-fresh","flexdb-prepared","sqlite-delete","sqlite-wal",0,0);let data=j_object();let i=0;while i<4 {j_set(data,h_at(names,i),j_array());i=i+1;}
    let round=0;while round<=runs {let slot=0;while slot<4 {let mode=(round+slot)%4;let name=h_at(names,mode);let path=h_join(work,h_cat3(name,h_int(round),".db"));let executable=flex;let option=0;if mode==1 {option="prepared";}if mode>=2 {executable=sqlite;option="delete";if mode==3 {option="wal";}}
            let result=h_ok(h_args(executable,path,h_int(rows),option,0,0));j_push(j_get(data,name),j_parse(h_out(result)));slot=slot+1;
        }h_print(1,h_cat3("Completed round ",h_int(round)," (round 0 is warmup)\n"));round=round+1;
    }
    let keys=h_args("insert_ns","lookup_ns","count_ns","materialize_ns","update_ns","durable_ns");h_add(keys,"reopen_ns");h_add(keys,"bytes");h_add(keys,"peak_kib");h_add(keys,"close_checkpoint_ns");h_add(keys,"first_scan_ns");let medians=j_object();i=0;while i<4 {let name=h_at(names,i);let result=j_object();let k=0;while k<h_count(keys) {let key=h_at(keys,k);j_set(result,key,j_int(median(j_get(data,name),key,runs)));k=k+1;}j_set(medians,name,result);h_print(1,h_cat3(name," ",h_cat(j_dump(result),"\n")));i=i+1;}
    let report=j_object();j_set(report,"cpu",j_int(cpu));j_set(report,"work_directory",j_string(work));j_set(report,"rows",j_int(rows));j_set(report,"runs",j_int(runs));j_set(report,"sqlite_version",j_string(version));j_set(report,"medians",medians);j_set(report,"samples_including_warmup",data);
    j_set(report,"method",j_string("One CPU, alternating order; warmup excluded, odd-run medians. Native compiled Flexscript and C -O3/system SQLite, prepared SQL, NOMUTEX, 64MiB SQLite cache, FULL sync, DELETE and WAL. FlexDB fresh and reusable input values. Bulk insert one transaction, 100000 ID lookups in one read transaction, 100 count scans, 20 materialized ID scans, 1000 batch updates, 100 single-write durable transactions. Reopen plus first lookup, warm OS cache; not cold storage. No secondary age index. FlexDB retains data in RAM; SQLite caches disk pages. Close/checkpoint cost and first full scan after reopen recorded separately. Creation/compilation/query preparation excluded. Durability intent comparable; no claim of equivalent crash-safety maturity."));
    let report_path=h_join(work,"report.json");if argc>4 {report_path=load64(argv+32);}j_save(report_path,report);h_print(1,h_cat3("Report: ",report_path,"\n"));return 0;
}
