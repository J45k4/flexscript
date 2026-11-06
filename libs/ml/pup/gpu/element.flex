// Scalar operations and warp reductions specialized to static tensor shapes.
import "indexing.flex";
fn cg_element(node,silu) {
    cg_dimensions(node);cg_code=h_buffer();let op=load64(node);let shape=node+64;let a=node+96;let b=node+128;let value=0;
    cg_line("let other=gpu_launch_word(0);let weights=gpu_launch_word(1);let bias=gpu_launch_word(2);");
    if op>=3 && op<=7 {
        cg_line(cg_f2("let x=gpu_load_u32(input+(@0@)*4);let y=gpu_load_u32(other+(@1@)*4);",cg_broadcast("index",shape,a),cg_broadcast("index",shape,b)));
        let name="add";if op==4 {name="sub";}if op==5 {name="mul";}if op==6 {name="div";}if op==7 {name="max";}value=h_cat3("vk_",name,"(x,y)");
    }else if op==24 {value="vk_sigmoid(gpu_load_u32(input+index*4))";}
    else if op==10 {
        let terms=h_buffer();let i=0;while i<4 {if i {h_text(terms,"+");}let coordinate=cg_r(cg_q("index",cg_product(shape,i+1,4)),load64(shape+i*8));h_text(terms,h_cat3(coordinate,"*",h_int(cg_product(a,cg_param(node,i)+1,4))));i=i+1;}value=h_cat3("gpu_load_u32(input+(",h_data(terms),")*4)");
    }else if op==25 || op==26 {
        let axis=cg_param(node,0);let inner=cg_product(shape,axis+1,4);let dimension=load64(shape+axis*8);let coordinate=cg_r(cg_q("index",inner),dimension);let outer=cg_q("index",inner*dimension);let tail=cg_r("index",inner);
        cg_num("ad",load64(a+axis*8));cg_num("bd",load64(b+axis*8));cg_num("inner",inner);cg_num("start",cg_param(node,1));
        if op==26 {value=cg_expand(cg_f3("gpu_load_u32(input+((@0@*@ad@+@1@+@start@)*@inner@+@2@)*4)",outer,coordinate,tail));}
        else {cg_line(cg_f1("let coordinate=@0@;let source=input;let dimension=@ad@;if coordinate>=@ad@ {coordinate=coordinate-@ad@;source=other;dimension=@bd@;}",coordinate));value=cg_expand(cg_f2("gpu_load_u32(source+((@0@*dimension+coordinate)*@inner@+@1@)*4)",outer,tail));}
    }else if op==27 {
        let scale=cg_param(node,0);let src=cg_expand(cg_f3("((@0@*@a2@+@1@)*@a3@+@2@)",cg_q("index",load64(shape+16)*load64(shape+24)),cg_q(cg_r(cg_q("index",load64(shape+24)),load64(shape+16)),scale),cg_q(cg_r("index",load64(shape+24)),scale)));value=h_cat3("gpu_load_u32(input+",src,"*4)");
    }else if op==12 || op==14 {
        let cin=load64(a+8);let ih=load64(a+16);let iw=load64(a+24);let cout=load64(shape+8);let oh=load64(shape+16);let ow=load64(shape+24);let k=cg_param(node,0);let groups=cg_param(node,3);
        cg_line(cg_f4("let ox=@0@;let oy=@1@;let channel=@2@;let batch=@3@;",cg_r("index",ow),cg_r(cg_q("index",ow),oh),cg_r(cg_q("index",ow*oh),cout),cg_q("index",ow*oh*cout)));
        let initial="0";let channels=cin/groups;let first=h_cat3(cg_q("channel",cout/groups),"*",h_int(channels));if op==14 {initial="0xff800000";channels=1;first="channel";}cg_num("channels",channels);cg_num("kk",k*k);
        cg_line(cg_f1("let sum=@0@;",initial));cg_line(cg_f1("let first=@0@;let ci=0;while ci<@channels@ {",first));
        let ky=0;while ky<k {cg_num("dy",ky-cg_param(node,2));cg_line("let iy=oy*@stride@+@dy@;if iy>=0 && iy<@ih@ {");let kx=0;while kx<k {cg_num("dx",kx-cg_param(node,2));cg_num("at",ky*k+kx);cg_line("let ix=ox*@stride@+@dx@;if ix>=0 && ix<@iw@ {let x=gpu_load_u32(input+(((batch*@cin@+first+ci)*@ih@+iy)*@iw@+ix)*4);");if op==14 {cg_line("sum=vk_max(sum,x);");}else {cg_line("sum=gpu_f32_fma(x,gpu_load_u32(weights+((channel*@channels@+ci)*@kk@+@at@)*4),sum);");}cg_line("}");kx=kx+1;}cg_line("}");ky=ky+1;}
        cg_line("ci=ci+1;}");if load64(node+208) {cg_line("sum=vk_add(sum,gpu_load_u32(bias+channel*4));");}value="sum";if silu {value=cg_activation(value);}
    }else if op==28 {
        let axis=cg_param(node,0);let inner=cg_product(shape,axis+1,4);let length=load64(shape+axis*8);cg_num("inner",inner);cg_num("length",length);cg_num("rowstep",length*inner);
        cg_line(cg_f2("let row=index>>5;let lane=gpu_lane();let start=@0@*@rowstep@+@1@;",cg_q("row",inner),cg_r("row",inner)));
        cg_line("let maximum=0xff800000;let i=lane;while i<@length@ {maximum=vk_max(maximum,gpu_load_u32(input+(start+i*@inner@)*4));i=i+32;}");let distance=16;while distance {cg_num("distance",distance);cg_line("maximum=vk_max(maximum,gpu_shuffle(maximum,lane^@distance@,4294967295));");distance=distance/2;}
        cg_line("let sum=0;i=lane;while i<@length@ {sum=vk_add(sum,vk_exp(vk_sub(gpu_load_u32(input+(start+i*@inner@)*4),maximum)));i=i+32;}");cg_line("let reciprocal=gpu_f32_rcp_approx(gpu_warp_sum_f32(sum));");cg_line("i=lane;while i<@length@ {let value=vk_mul(vk_exp(vk_sub(gpu_load_u32(input+(start+i*@inner@)*4),maximum)),reciprocal);gpu_store_u32(output+(start+i*@inner@)*4,value);i=i+32;}");cg_work=cg_product(shape,0,4)/length*32;cg_threads=128;cg_shared=0;return h_slice(h_data(cg_code),h_size(cg_code)-1);
    }else {h_die(h_cat("unsupported tensor operation: ",h_int(op)));}
    cg_line(cg_f1("gpu_store_u32(output+index*4,@0@);",value));cg_work=cg_product(shape,0,4);cg_threads=128;cg_shared=0;return h_slice(h_data(cg_code),h_size(cg_code)-1);
}
fn cg_stencil(node,silu) {
    let fallback=cg_element(node,silu);cg_code=h_buffer();let cin=load64(node+104);let ih=load64(node+112);let iw=load64(node+120);let cout=load64(node+72);let oh=load64(node+80);let ow=load64(node+88);let k=cg_param(node,0);let groups=cg_param(node,3);
    cg_num("iylimit",ih-k+1);cg_num("ixlimit",iw-k+1);cg_num("weightstep",k*k*4);
    cg_line("let weights=gpu_launch_word(1);let bias=gpu_launch_word(2);");cg_line(cg_f4("let ox=@0@;let oy=@1@;let channel=@2@;let batch=@3@;",cg_r("index",ow),cg_r(cg_q("index",ow),oh),cg_r(cg_q("index",ow*oh),cout),cg_q("index",ow*oh*cout)));
    cg_line("let iy=oy*@stride@-@pad@;let ix=ox*@stride@-@pad@;");cg_line("if iy>=0 && iy<@iylimit@ && ix>=0 && ix<@ixlimit@ {");cg_line(cg_f1("let source=input+(((batch*@cin@+@0@)*@ih@+iy)*@iw@+ix)*4;let lookup=weights+channel*@weightstep@;",cg_q("channel",cout/groups)));
    let j=0;while j<k*k {cg_num("j",j);cg_num("offset",j*4);cg_line("let weight@j@=gpu_load_u32(lookup+@offset@);");j=j+1;}
    let ky=0;while ky<k {let kx=0;while kx<k {cg_num("j",ky*k+kx);cg_num("offset",(ky*iw+kx)*4);cg_line("let pixel@j@=gpu_load_u32(source+@offset@);");kx=kx+1;}ky=ky+1;}
    cg_line("let sum=0;");j=0;while j<k*k {cg_num("j",j);cg_line("sum=gpu_f32_fma(pixel@j@,weight@j@,sum);");j=j+1;}if load64(node+208) {cg_line("sum=vk_add(sum,gpu_load_u32(bias+channel*4));");}let value="sum";if silu {value=cg_activation(value);}cg_line(cg_f1("gpu_store_u32(output+index*4,@0@);",value));cg_line(cg_f1("}else{@0@}",fallback));return h_slice(h_data(cg_code),h_size(cg_code)-1);
}
fn cg_input_matrix(node) {
    cg_dimensions(node);cg_code=h_buffer();let k=cg_param(node,0);let groups=cg_param(node,3);let cin=load64(node+104);let ow=load64(node+88);let n=load64(node+80)*ow;let reduction=cin/groups*k*k;cg_num("inGroup",cin/groups);
    cg_line(cg_f3("let col=@0@;let kk=@1@;let batch=@2@;",cg_r("index",n),cg_r(cg_q("index",n),reduction),cg_q("index",n*reduction)));
    cg_line(cg_f4("let iy=@0@*@stride@+@1@-@pad@;let ix=@2@*@stride@+@3@-@pad@;",cg_q("col",ow),cg_r(cg_q("kk",k),k),cg_r("col",ow),cg_r("kk",k)));
    cg_line("let valid=(iy>=0)*(iy<@ih@)*(ix>=0)*(ix<@iw@);");cg_line(cg_f3("let at=(((@0@*@cin@+@1@*@inGroup@+@2@)*@ih@+iy)*@iw@+ix)*valid;",cg_q("batch",groups),cg_r("batch",groups),cg_q("kk",k*k)));
    cg_line("let value=gpu_load_u32(input+at*4)&(0-valid);gpu_store_u32(output+index*4,value);");return h_slice(h_data(cg_code),h_size(cg_code)-1);
}
