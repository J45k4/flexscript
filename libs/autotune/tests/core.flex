import "../driver.flex";
global ac_checks=0;
fn ac_assert(ok,text) {h_assert(ok,text);ac_checks=ac_checks+1;return 0;}
fn ac_tile(m,n,k,threads,lc) {let tile=j_object();j_set(tile,"m",j_int(m));j_set(tile,"n",j_int(n));j_set(tile,"k",j_int(k));j_set(tile,"threads",j_int(threads));j_set(tile,"laneColumns",j_int(lc));return tile;}
fn ac_core() {
    ac_checks=0;ac_assert(at_name("gemm-64_k16") && !at_name("../gemm") && !at_name("") && !at_name("a/b"),"candidate path validation");
    ac_assert(at_tile_valid(ac_tile(32,64,16,128,16)),"narrow tile rejected");ac_assert(at_tile_valid(ac_tile(64,64,16,128,16)),"wide tile rejected");
    ac_assert(at_tile_valid(ac_tile(32,64,8,64,8)) && at_tile_valid(ac_tile(64,64,32,256,16)),"alternative execution layouts rejected");
    ac_assert(!at_tile_valid(ac_tile(33,64,16,128,16)),"non-power tile accepted");ac_assert(!at_tile_valid(ac_tile(32,64,0,128,16)),"zero K accepted");ac_assert(!at_tile_valid(ac_tile(32,64,16,96,16)),"invalid block size accepted");ac_assert(!at_tile_valid(ac_tile(256,256,64,64,1)),"excess register/shared footprint accepted");
    let tile=at_tile(ac_tile(64,64,16,128,16));ac_assert(j_n(tile,"sharedBytes")==8192 && j_n(tile,"splitChunkAlignment")==16,"launch contract incorrect");
    let times=j_array();j_push(times,j_int(31));j_push(times,j_int(7));j_push(times,j_int(20));j_push(times,j_int(9));let stats=at_stats(times);ac_assert(j_n(stats,"mean_ns")==16 && j_n(stats,"median_ns")==20 && j_n(stats,"min_ns")==7,"integer timing statistics incorrect");
    ac_assert(at_selected("a,ab,b","ab") && !at_selected("a,ab,b","abc") && at_selected(0,"all"),"candidate selection is not exact");return ac_checks;
}
