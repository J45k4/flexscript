// Register/shared-memory FP32 tiles. All scheduling decisions run natively.
import "element.flex";
global cg_options=0;
global ct_node=0;
fn cg_n(key) {return h_number(j_value(j_need(cg_values,key)));}
fn ct_column(value) {if !cg_n("swizzle") {return value;}return cg_expand(cg_f1("((@0@)^(((@0@)>>5)&@swizzleMask@)*2)",value));}
fn ct_lookup(start,lanes,kind,fallback) {
    let values=h_take(lanes*8);let i=0;let maximum=0;while i<lanes {let n=start+i;if kind==0 {n=n/9;}if kind==1 {n=n/3%3;}if kind==2 {n=n%3;}store64(values+i*8,n);maximum=cg_max(maximum,n);i=i+1;}
    let first=load64(values);let last=load64(values+(lanes-1)*8);let same=1;let arithmetic=1;let delta=0;if lanes>1 {delta=load64(values+8)-first;}i=0;while i<lanes {let n=load64(values+i*8);if n!=first {same=0;}if n!=first+i*delta {arithmetic=0;}i=i+1;}if same {return h_int(first);}
    if arithmetic {if delta>=0 {return h_cat3("(",h_int(first),h_cat3("+lane_k*",h_int(delta),")"));}return h_cat3("(",h_int(last),h_cat3("+(",h_int(lanes-1),h_cat3("-lane_k)*",h_int(-delta),")")));}
    let bits=1;while (maximum>>bits)>0 {bits=bits+1;}if bits*lanes>64 {return fallback;}let packed=0;i=0;while i<lanes {packed=packed|(load64(values+i*8)<<(i*bits));i=i+1;}
    let bytes=h_take(8);let j=0;while j<8 {store8(bytes+j,(packed>>((7-j)*8))&255);j=j+1;}let hex=h_hex(bytes,8);j=0;while load8(hex+j)==48 && j<15 {j=j+1;}return h_cat3("((0x",hex+j,h_cat3(">>(lane_k*",h_int(bits),h_cat3("))&",h_int((1<<bits)-1),")")));
}
fn ct_operands(kk,suffix) {
    let rm=cg_n("rm");let rn=cg_n("rn");let pitch=cg_n("pitch");let tn=cg_n("tn");let size=cg_n("sizeA");let vector=cg_n("vector");let vb=cg_n("vectorB");cg_set("suffix",suffix);let i=0;
    while i<rm {if !(vector && rm%2==0 && i%2) {cg_num("i",i);cg_num("offset",(kk*pitch+i)*4);if vector && rm%2==0 {cg_line("let w@i@@suffix@=gpu_shared_load64(mrb+@offset@);");}else {cg_line("let w@i@@suffix@=gpu_shared_load_u32(mrb+@offset@);");}}i=i+1;}
    let j=0;while j<rn {if !(vb && j%2) {cg_num("j",j);if vb {cg_num("offset",(size+kk*tn)*4);cg_line("let x@j@@suffix@=gpu_shared_load64(nrb@j@+@offset@);");}else {cg_num("offset",(size+kk*tn+j*(tn/rn))*4);cg_line("let x@j@@suffix@=gpu_shared_load_u32(nrb+@offset@);");}}j=j+1;}return 0;
}
fn ct_load(stage,slot,step,partial) {
    let node=ct_node;let op=load64(node);let k=cg_param(node,0);let groups=cg_param(node,3);let cin=load64(node+104);let ih=load64(node+112);let iw=load64(node+120);let ow=load64(node+88);let m=cg_n("m");let n=cg_n("n");let reduction=cg_n("reduction");let threads=cg_n("threads");let tm=cg_n("tm");let tn=cg_n("tn");let tk=cg_n("tk");let size=cg_n("sizeA");let pitch=cg_n("pitch");let limit=tk*tn-step*threads;if stage==0 {limit=tm*tk-step*threads;}
    let active="1";if partial {active=h_cat3("(tid<",h_int(limit),")");}cg_set("active",active);cg_num("slot",slot);cg_num("stepThreads",step*threads);cg_num("stepBytes",step*threads*4);
    if cg_n("cached") {
        if stage==0 {cg_num("step",step);cg_line("let shared@slot@=weight_entry@step@>>32;let mask@slot@=-1;let staged@slot@=gpu_load_u32(gpu_address_f32(a_base,weight_entry@step@*@active@));");}
        else {cg_num("lookup",step%9);cg_num("delta",step/9*(threads/tn)*ih*iw);if cg_n("packedMasks") {cg_line("let shared@slot@=shared_b+@stepBytes@;let mask@slot@=image_lookup@lookup@>>32;let staged@slot@=gpu_load_u32(gpu_address_f32(b_base,(image_lookup@lookup@+@delta@)*@active@));");}else {cg_line("let shared@slot@=shared_b+@stepBytes@;let mask@slot@=0-((image_lookup@lookup@>>31)&1);let staged@slot@=gpu_load_u32(b_base+(((image_lookup@lookup@&0x7fffffff)+@delta@)*@active@)*4);");}}
    }else if cg_n("streamed") {
        let letter="a";let byte_stride=threads/tk*reduction*4;let shared_step=threads/tk*4;let mask="-1";if stage {letter="b";byte_stride=threads/tn*n*4;shared_step=threads*4;if !cg_n("fullB") {mask="column_mask";}}cg_set("stage",letter);cg_num("sharedStep",step*shared_step);cg_num("byteStride",step*byte_stride);cg_set("mask",mask);cg_line("let shared@slot@=shared_@stage@+@sharedStep@;let mask@slot@=@mask@;let staged@slot@=gpu_load_u32(@stage@_base+@byteStride@);");
    }else {
        cg_line("let v=tid+@stepThreads@;");let address=0;let source=0;let shared=0;
        if stage==0 {
            cg_line(cg_f2("let row=bm+@0@;let kk=base+@1@;",cg_q("v",tk),cg_r("v",tk)));let valid="1";if !cg_n("fullA") {valid=cg_expand("(row<@m@)*(kk<@reduction@)");}cg_line(cg_f1("let valid=@0@;",valid));
            address=cg_expand("((batch*@m@+row)*@reduction@+kk)");source="input";if op==12 {address=cg_expand(cg_f1("((@0@*@m@+row)*@reduction@+kk)",cg_r("batch",groups)));source="weights";}shared=cg_expand(cg_f2("(@0@*@pitch@+@1@)*4",cg_r("v",tk),cg_q("v",tk)));
        }else {
            cg_line(cg_f2("let col=bn+@0@;let kk=base+@1@;",cg_r("v",tn),cg_q("v",tn)));let valid="1";if !cg_n("fullB") {valid=cg_expand("(col<@n@)*(kk<@reduction@)");}cg_line(cg_f1("let valid=@0@;",valid));source="input";
            if op==12 && cg_n("im2col") {address=cg_expand("((batch*@reduction@+kk)*@n@+col)");source="other";}
            else if op==12 && k==1 && cg_param(node,1)==1 && cg_param(node,2)==0 {address=cg_expand(cg_f2("((@0@*@cin@+@1@*@inGroup@+kk)*@n@+col)",cg_q("batch",groups),cg_r("batch",groups)));}
            else if op==12 {
                cg_line(cg_f4("let iy=@0@*@stride@+@1@-@pad@;let ix=@2@*@stride@+@3@-@pad@;valid=valid*(iy>=0)*(iy<@ih@)*(ix>=0)*(ix<@iw@);",cg_q("col",ow),cg_r(cg_q("kk",k),k),cg_r("col",ow),cg_r("kk",k)));
                address=cg_expand(cg_f3("(((@0@*@cin@+@1@*@inGroup@+@2@)*@ih@+iy)*@iw@+ix)",cg_q("batch",groups),cg_r("batch",groups),cg_q("kk",k*k)));
            }else {address=cg_expand("((batch*@reduction@+kk)*@n@+col)");source="other";}
            shared=cg_expand(cg_f1("(@sizeA@+@0@)*4",ct_column("v")));
        }
        if partial {cg_line("valid=valid*@active@;");}cg_line(cg_f4("let address=@0@*valid;let shared@slot@=@1@;let mask@slot@=0-valid;let staged@slot@=gpu_load_u32(@2@+address*4);",address,shared,source,""));
    }
    if partial {cg_num("scratchBase",size+tk*tn);cg_line("shared@slot@=shared@slot@*@active@+(@scratchBase@+tid)*4*(1-@active@);mask@slot@=mask@slot@*@active@;");}return 0;
}
fn ct_tiled(node,silu,im2col) {
    ct_node=node;cg_dimensions(node);cg_code=h_buffer();let op=load64(node);let k=cg_param(node,0);let stride=cg_param(node,1);let pad=cg_param(node,2);let groups=cg_param(node,3);let cin=load64(node+104);let ih=load64(node+112);let iw=load64(node+120);let ow=load64(node+88);
    let m=load64(node+80);let n=load64(node+88);let reduction=load64(node+120);let batches=cg_product(node+64,0,2);if op==12 {m=load64(node+72)/groups;n=load64(node+80)*ow;reduction=cin/groups*k*k;batches=load64(node+96)*groups;}else {groups=1;}
    let tm=32;let tn=64;let tk=32;let rm=4;let rn=4;if m<=16 {tm=16;rm=2;}if batches*((m+tm-1)/tm)*((n+tn-1)/tn)<72 {tn=32;}if batches*((m+tm-1)/tm)*((n+tn-1)/tn)<72 {tm=16;rm=2;}if batches*((m+tm-1)/tm)*((n+tn-1)/tn)<72 {tn=16;rn=2;}if batches*((m+tm-1)/tm)*((n+tn-1)/tn)<36 {tm=8;rm=1;}
    if j_n(cg_options,"patchTiles") && op==12 && k==3 {if m<=8 {tm=8;rm=1;}if m%tm==0 {tk=9;if reduction%18==0 {tk=18;}}}
    let tile=j_get(cg_options,"tile");if tile && j_kind(tile)==3 {tm=j_value(j_at(tile,0));tn=j_value(j_at(tile,1));tk=j_value(j_at(tile,2));rm=j_value(j_at(tile,3));rn=j_value(j_at(tile,4));}
    let vector=j_n(cg_options,"vector");let staging=j_n(cg_options,"staging");let pipeline=j_n(cg_options,"pipeline");let pitch=cg_pitch(tm,tk,vector && rm%2==0);let size=pitch*tk;let threads=tm/rm*(tn/rn);let mb=(m+tm-1)/tm;let nb=(n+tn-1)/tn;let vb=vector && rn%2==0 && size%2==0;let swizzle=vb && rn>=4 && tn>=64;let swizzle_mask=0;if swizzle {swizzle_mask=cg_min(rn/2-1,tn/32-1);}
    cg_num("m",m);cg_num("n",n);cg_num("reduction",reduction);cg_num("tm",tm);cg_num("tn",tn);cg_num("tk",tk);cg_num("rm",rm);cg_num("rn",rn);cg_num("pitch",pitch);cg_num("sizeA",size);cg_num("threads",threads);cg_num("vector",vector);cg_num("vectorB",vb);cg_num("swizzle",swizzle);cg_num("swizzleMask",swizzle_mask);cg_num("inGroup",cin/groups);cg_num("im2col",im2col);cg_num("packedMasks",j_n(cg_options,"packedMasks"));
    cg_line(cg_f3("let tid=gpu_thread_x();let block=gpu_block_x();let bn=@0@*@tn@;let bm=@1@*@tm@;let batch=@2@;",cg_r("block",nb),cg_r(cg_q("block",nb),mb),cg_q("block",nb*mb)));cg_line(cg_f2("let mr=@0@*@rm@;let nr=@1@;",cg_q("tid",tn/rn),cg_r("tid",tn/rn)));cg_line("let weights=gpu_launch_word(1);let bias=gpu_launch_word(2);let other=gpu_launch_word(0);let mrb=mr*4;let nrb=nr*4;");
    if vb {cg_line("nr=nr*@rn@;");let j=0;while j<rn {cg_num("j",j);cg_line(cg_f1("let nrb@j@=@0@*4;",ct_column(h_cat3("(nr+",h_int(j),")"))));j=j+2;}}
    let i=0;while i<rm {let j=0;cg_num("i",i);while j<rn {cg_num("j",j);cg_line("let c@i@@j@=0;");j=j+1;}i=i+1;}
    let scratch=0;if staging && (tm*tk%threads%32 || tk*tn%threads%32) {scratch=threads;}let full_a=m%tm==0 && reduction%tk==0;let full_b=n%tn==0 && reduction%tk==0;let streamed=j_n(cg_options,"streaming") && staging && full_a && threads>=tk && threads>=tn && threads%tk==0 && tm*tk%threads==0 && tk*tn%threads==0 && (op==29 || im2col || (op==12 && k==1 && stride==1 && pad==0));
    cg_num("fullA",full_a);cg_num("fullB",full_b);cg_num("streamed",streamed);
    if streamed {
        let row=h_cat3("(bm+",cg_q("tid",tk),")");let address=cg_expand(cg_f2("((batch*@m@+@0@)*@reduction@+@1@)",row,cg_r("tid",tk)));if op==12 {address=cg_expand(cg_f3("((@0@*@m@+@1@)*@reduction@+@2@)",cg_r("batch",groups),row,cg_r("tid",tk)));}
        cg_line(cg_f1("let col=bn+@0@;let column_mask=0-(col<@n@);let safe_col=col*(col<@n@);",cg_r("tid",tn)));let source="input";if op==12 {source="weights";}cg_line(cg_f2("let a_base=@0@+@1@*4;",source,address));source="input";if op==29 || im2col {source="other";}cg_line(cg_f2("let b_base=@0@+((batch*@reduction@+@1@)*@n@+safe_col)*4;",source,cg_q("tid",tn)));
        cg_line(cg_f3("let shared_a=(@0@*@pitch@+@1@)*4;let shared_b=(@sizeA@+@2@)*4;",cg_r("tid",tk),cg_q("tid",tk),ct_column("tid")));
    }
    let cached=staging && op==12 && k==3 && !im2col && full_a && tk%9==0 && threads%tn==0;cg_num("cached",cached);
    if cached {
        cg_line("let a_base=weights;");cg_num("imageBytes",ih*iw*4);cg_line(cg_f2("let b_base=input+(@0@*@cin@+@1@*@inGroup@)*@imageBytes@;",cg_q("batch",groups),cg_r("batch",groups)));cg_line(cg_f1("let shared_b=(@sizeA@+@0@)*4;",ct_column("tid")));
        let step=0;while step<(tm*tk+threads-1)/threads {cg_num("step",step);cg_num("stepThreads",step*threads);cg_line(cg_f1("let v=tid+@stepThreads@;let ar=@0@;let ak=v-ar*@tk@;",cg_q("v",tk)));cg_line(cg_f1("let weight_entry@step@=((@0@*@m@+bm+ar)*@reduction@+ak)|(((ak*@pitch@+ar)*4)<<32);",cg_r("batch",groups)));step=step+1;}
        cg_line(cg_f2("let col=bn+@0@;let oy=@1@;let ox=col-oy*@ow@;oy=oy*@stride@-@pad@;ox=ox*@stride@-@pad@;",cg_r("tid",tn),cg_q("col",ow)));let valid="1";if n%tn {valid=cg_expand("col<@n@");}cg_line(cg_f2("let column_valid=@0@;let lane_k=@1@;",valid,cg_q("tid",tn)));
        let lanes=threads/tn;step=0;while step<cg_min(9,(tk*tn+threads-1)/threads) {let plane=h_cat3("(lane_k+",h_int(step*lanes),")");let channel=ct_lookup(step*lanes,lanes,0,cg_q(plane,9));let ky=ct_lookup(step*lanes,lanes,1,cg_r(cg_q(plane,3),3));let kx=ct_lookup(step*lanes,lanes,2,cg_r(plane,3));let mask="(valid<<31)";if j_n(cg_options,"packedMasks") {mask="((0-valid)<<32)";}cg_num("step",step);cg_num("imageElements",ih*iw);cg_line(cg_f2("let iy=oy+@0@;let ix=ox+@1@;let valid=column_valid*(iy>=0)*(iy<@ih@)*(ix>=0)*(ix<@iw@);",ky,kx));cg_line(cg_f2("let image_lookup@step@=((@0@*@imageElements@+iy*@iw@+ix)*valid)|@1@;",channel,mask));step=step+1;}
    }
    cg_line("let base=0;");cg_line("while base<@reduction@ {");
    if staging {
        let stage=0;while stage<2 {let elements=tm*tk;if stage {elements=tk*tn;}let steps=(elements+threads-1)/threads;let start=0;while start<steps {let count=cg_min(staging,steps-start);let slot=0;while slot<count {let limit=elements-(start+slot)*threads;let uniform=limit<threads && limit%32==0;cg_num("limit",limit);if uniform {cg_line("if tid<@limit@ {");}ct_load(stage,slot,start+slot,limit<threads && limit%32!=0);if uniform {cg_line("}");}slot=slot+1;}
            slot=0;while slot<count {let limit=elements-(start+slot)*threads;let uniform=limit<threads && limit%32==0;cg_num("limit",limit);cg_num("slot",slot);if uniform {cg_line("if tid<@limit@ {");}cg_line("gpu_shared_store_u32(shared@slot@,staged@slot@&mask@slot@);");if uniform {cg_line("}");}slot=slot+1;}start=start+staging;}stage=stage+1;}cg_line("gpu_shared_barrier();");
    }else {
        cg_line("let v=tid;");cg_num("elements",tm*tk);cg_line("while v<@elements@ {");
        cg_line(cg_f2("let row=bm+@0@;let kk=base+@1@;",cg_q("v",tk),cg_r("v",tk)));let valid="1";if !full_a {valid=cg_expand("(row<@m@)*(kk<@reduction@)");}cg_line(cg_f1("let valid=@0@;",valid));
        if op==12 {cg_line(cg_f1("let address=((@0@*@m@+row)*@reduction@+kk)*valid;let value=gpu_load_u32(weights+address*4)&(0-valid);",cg_r("batch",groups)));}else {cg_line("let address=((batch*@m@+row)*@reduction@+kk)*valid;let value=gpu_load_u32(input+address*4)&(0-valid);");}
        cg_line(cg_f2("gpu_shared_store_u32((@0@*@pitch@+@1@)*4,value);v=v+@threads@;",cg_r("v",tk),cg_q("v",tk)));cg_line("}");cg_line("v=tid;");cg_num("elements",tk*tn);cg_line("while v<@elements@ {");valid="1";if !full_b {valid=cg_expand("(col<@n@)*(kk<@reduction@)");}cg_line(cg_f3("let col=bn+@0@;let kk=base+@1@;let valid=@2@;",cg_r("v",tn),cg_q("v",tn),valid));
        if op==12 && im2col {cg_line("let address=((batch*@reduction@+kk)*@n@+col)*valid;let value=gpu_load_u32(other+address*4)&(0-valid);");}
        else if op==12 && k==1 && stride==1 && pad==0 {cg_line(cg_f2("let address=((@0@*@cin@+@1@*@inGroup@+kk)*@n@+col)*valid;let value=gpu_load_u32(input+address*4)&(0-valid);",cg_q("batch",groups),cg_r("batch",groups)));}
        else if op==12 {cg_line(cg_f2("let iy=@0@*@stride@+@1@-@pad@;",cg_q("col",ow),cg_r(cg_q("kk",k),k)));cg_line(cg_f2("let ix=@0@*@stride@+@1@-@pad@;",cg_r("col",ow),cg_r("kk",k)));cg_line(cg_f3("valid=valid*(iy>=0)*(iy<@ih@)*(ix>=0)*(ix<@iw@);let address=(((@0@*@cin@+@1@*@inGroup@+@2@)*@ih@+iy)*@iw@+ix)*valid;let value=gpu_load_u32(input+address*4)&(0-valid);",cg_q("batch",groups),cg_r("batch",groups),cg_q("kk",k*k)));}
        else {cg_line("let address=((batch*@reduction@+kk)*@n@+col)*valid;let value=gpu_load_u32(other+address*4)&(0-valid);");}
        cg_line(cg_f1("gpu_shared_store_u32((@sizeA@+@0@)*4,value);v=v+@threads@;",ct_column("v")));cg_line("}");cg_line("gpu_shared_barrier();");
    }
    let unroll=j_n(cg_options,"unroll");let chunk=tk;if unroll {chunk=cg_min(tk,unroll);while tk%chunk {chunk=chunk-1;}}cg_num("chunk",chunk);cg_num("innerSteps",tk/chunk);
    if chunk<tk {cg_line("mrb=mr*4;");if vb {let j=0;while j<rn {cg_num("j",j);cg_line(cg_f1("nrb@j@=@0@*4;",ct_column(h_cat3("(nr+",h_int(j),")"))));j=j+2;}}else {cg_line("nrb=nr*4;");}cg_line("let inner_steps=@innerSteps@;while inner_steps {");}
    if pipeline {ct_operands(0,"");}let kk=0;while kk<chunk {let suffix="";if pipeline && kk%2 {suffix="_next";}if pipeline {if kk+1<chunk {let next="_next";if kk%2 {next="";}ct_operands(kk+1,next);}}else {ct_operands(kk,"");}
        i=0;while i<rm {let w=h_cat3("w",h_int(i),suffix);if vector && rm%2==0 && i%2 {w=h_cat3("w",h_int(i-1),h_cat(suffix,">>32"));}let j=0;cg_num("i",i);while j<rn {cg_num("j",j);let x=h_cat3("x",h_int(j),suffix);if vb && j%2 {x=h_cat3("x",h_int(j-1),h_cat(suffix,">>32"));}cg_line(cg_f2("c@i@@j@=gpu_f32_fma(@0@,@1@,c@i@@j@);",w,x));j=j+1;}i=i+1;}kk=kk+1;}
    if chunk<tk {cg_num("advanceA",chunk*pitch*4);cg_num("advanceB",chunk*tn*4);cg_line("mrb=gpu_u32_add(mrb,@advanceA@);");if vb {let j=0;while j<rn {cg_num("j",j);cg_line("nrb@j@=gpu_u32_add(nrb@j@,@advanceB@);");j=j+2;}}else {cg_line("nrb=gpu_u32_add(nrb,@advanceB@);");}cg_line("inner_steps=gpu_u32_sub(inner_steps,1);}");cg_line("");}
    cg_line("gpu_shared_barrier();base=base+@tk@;");cg_num("advanceA",tk*4);if streamed {cg_num("advanceB",tk*n*4);cg_line("a_base=a_base+@advanceA@;b_base=b_base+@advanceB@;");}if cached {cg_num("advanceB",tk/9*ih*iw*4);cg_line("a_base=a_base+@advanceA@;b_base=b_base+@advanceB@;");}cg_line("}");
    i=0;while i<rm {cg_num("i",i);cg_line("let row=bm+mr+@i@;");if m%tm {cg_line("if row<@m@ {");}if op==12 && load64(node+208) {cg_line(cg_f1("let bias_value=gpu_load_u32(bias+(@0@*@m@+row)*4);",cg_r("batch",groups)));let j=0;while j<rn {cg_num("j",j);cg_line("c@i@@j@=vk_add(c@i@@j@,bias_value);");j=j+1;}}
        if silu && j_n(cg_options,"batchEpilogue") {let j=0;while j<rn {cg_num("j",j);cg_line("let e@j@=vk_sigmoid_exp(c@i@@j@);");j=j+1;}j=0;while j<rn {cg_num("j",j);cg_line("let r@j@=gpu_f32_rcp_approx(vk_add(0x3f800000,e@j@));");j=j+1;}j=0;while j<rn {cg_num("j",j);cg_line("c@i@@j@=vk_mul(c@i@@j@,vk_sigmoid_finish(c@i@@j@,e@j@,r@j@));");j=j+1;}}
        let j=0;while j<rn {cg_num("j",j);let offset=j;if !vb {offset=j*(tn/rn);}cg_num("columnOffset",offset);cg_line("let col=bn+nr+@columnOffset@;");if n%tn {cg_line("if col<@n@ {");}let value=h_cat3("c",h_int(i),h_int(j));if silu && !j_n(cg_options,"batchEpilogue") {value=cg_activation(value);}cg_line(cg_f1("gpu_store_u32(output+((batch*@m@+row)*@n@+col)*4,@0@);",value));if n%tn {cg_line("}");}j=j+1;}if m%tm {cg_line("}");}i=i+1;
    }
    cg_work=batches*mb*nb*threads;cg_threads=threads;cg_shared=(size+tk*tn+scratch)*4;h_assert(cg_shared<=49152,"tile exceeds shared-memory limit");return h_slice(h_data(cg_code),h_size(cg_code)-1);
}
