import "../../libs/image.flex";
import "../../scripts/lib/json.flex";
fn id_n(o,key,fallback){let p=j_get(o,key);if p{return j_value(p);}return fallback;}
fn id_time(clock){syscall(228,1,clock,0,0,0,0);return load64(clock)*1000000000+load64(clock+8);}
fn main(argc,argv){
    h_environment(argc,argv);let config=j_parse(h_read(load64(argv+8)));let data=h_read(j_s(config,"input"));let n=h_file_size;
    let c=image_context();h_assert(c,"image context");image_acceleration(c,id_n(config,"acceleration",1));let op=j_s(config,"operation");let out=0;let encoded=0;
    let source=image_decode(c,data,n);if !source{let result=j_object();j_set(result,"error",j_string(image_error(c)));h_print(1,j_dump(result));image_context_free(c);return 0;}
    let w=id_n(config,"width",load64(source));let h=id_n(config,"height",load64(source+8));
    if h_equal(op,"resize"){out=image_resize(c,source,w,h);}else if h_equal(op,"orient"){out=image_orient(c,source,id_n(config,"orientation",1));}
    else if h_equal(op,"jpeg"){encoded=image_encode_jpeg(c,source,id_n(config,"quality",85));}
    else if h_equal(op,"png"){encoded=image_encode_png(c,source);}
    else if h_equal(op,"preview"){encoded=image_preview(c,data,n,id_n(config,"side",1536),id_n(config,"limit",524288));}
    else if h_equal(op,"benchmark"){
        let lib=ffi_open(j_s(config,"oracle"));h_assert(lib,"reference library");let refdec=ffi_symbol(lib,"oracle_decode");let refresize=ffi_symbol(lib,"oracle_resize");let reffree=ffi_symbol(lib,"oracle_free");let refpreview=ffi_symbol(lib,"oracle_preview");let refencfree=ffi_symbol(lib,"oracle_encoded_free");
        let original=ffi_call(refdec,data,n,0,0,0,0);h_assert(original,"reference decode");let rounds=id_n(config,"rounds",3);let side=id_n(config,"side",1536);let limit=id_n(config,"limit",524288);let clock=h_take(16);
        let report=j_object();j_set(report,"accelerated",j_bool(image_acceleration(c,-1)));let warm=0;while warm<2{
            let r=0;if warm{r=image_decode(c,data,n);h_assert(r,image_error(c));image_free(r);}else{r=ffi_call(refdec,data,n,0,0,0,0);h_assert(r,"warm reference decode");ffi_call(reffree,r,0,0,0,0,0);}
            let key="reference_resize_output";if warm{r=image_resize(c,source,w,h);h_assert(r,image_error(c));key="native_resize_output";}else{r=ffi_call(refresize,original,w,h,0,0,0);h_assert(r,"warm reference resize");}
            let path=j_get(config,key);if path{h_save_bytes(j_value(path),load64(r+24),w*h*4,420);}if warm{image_free(r);}else{ffi_call(reffree,r,0,0,0,0,0);}
            key="reference_preview_output";let prefix="reference_";
            if warm{r=image_preview(c,data,n,side,limit);key="native_preview_output";prefix="native_";}else{r=ffi_call(refpreview,data,n,side,limit,0,0);}
            j_set(report,h_cat(prefix,"preview_ok"),j_bool(r!=0));
            if r{j_set(report,h_cat(prefix,"preview_bytes"),j_int(load64(r+8)));let quality=load64(r+32);if warm{quality=image_blob_quality(r);}j_set(report,h_cat(prefix,"quality"),j_int(quality));path=j_get(config,key);if path{h_save_bytes(j_value(path),load64(r),load64(r+8),420);}if warm{image_blob_free(r);}else{ffi_call(refencfree,r,0,0,0,0,0);}}
            warm=warm+1;
        }
        let rows=j_array();let sample=0;while sample<id_n(config,"samples",5){let mode=0;while mode<2{
            let native=(mode+(sample&1))&1;let times=j_object();j_set(times,"native",j_bool(native));
            let start=id_time(clock);let k=0;while k<rounds{let r=0;if native{r=image_decode(c,data,n);h_assert(r,image_error(c));image_free(r);}else{r=ffi_call(refdec,data,n,0,0,0,0);h_assert(r,"reference decode");ffi_call(reffree,r,0,0,0,0,0);}k=k+1;}j_set(times,"decode_ns",j_int((id_time(clock)-start)/rounds));
            start=id_time(clock);k=0;while k<rounds{let r=0;if native{r=image_resize(c,source,w,h);h_assert(r,image_error(c));image_free(r);}else{r=ffi_call(refresize,original,w,h,0,0,0);h_assert(r,"reference resize");ffi_call(reffree,r,0,0,0,0,0);}k=k+1;}j_set(times,"resize_ns",j_int((id_time(clock)-start)/rounds));
            start=id_time(clock);k=0;while k<rounds{let r=0;if native{r=image_preview(c,data,n,side,limit);if r{image_blob_free(r);}}else{r=ffi_call(refpreview,data,n,side,limit,0,0);if r{ffi_call(refencfree,r,0,0,0,0,0);}}k=k+1;}j_set(times,"preview_ns",j_int((id_time(clock)-start)/rounds));j_push(rows,times);mode=mode+1;
        }sample=sample+1;}j_set(report,"measurements",rows);ffi_call(reffree,original,0,0,0,0,0);image_free(source);image_context_free(c);h_print(1,j_dump(report));return 0;
    }else{out=image_clone(c,source);}
    let result=j_object();j_set(result,"source_width",j_int(load64(source)));j_set(result,"source_height",j_int(load64(source+8)));j_set(result,"orientation",j_int(image_orientation(data,n)));
    if out{j_set(result,"width",j_int(load64(out)));j_set(result,"height",j_int(load64(out+8)));j_set(result,"alpha",j_bool(load64(out+40)));h_save_bytes(j_s(config,"output"),load64(out+24),load64(out+32),420);image_free(out);}
    else if encoded{j_set(result,"bytes",j_int(load64(encoded+8)));h_save_bytes(j_s(config,"output"),load64(encoded),load64(encoded+8),420);image_blob_free(encoded);}
    else{j_set(result,"error",j_string(image_error(c)));}
    image_free(source);image_context_free(c);h_print(1,j_dump(result));return 0;
}
