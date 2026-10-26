// Verify every API-reference byte through bounded VM pages with all grants denied.
import "lib/collie-test.flex";
fn reference_literal(source,name){
    let prefix=h_cat3("fn ",name,"(){return ");let at=h_find(source,prefix);h_assert(at>=0,h_cat("Missing generated function: ",name));
    j_source=source;j_offset=at+h_len(prefix);return j_parse_string();
}
fn main(argc,argv){
    ct_init(argc,argv);let generated=h_read(h_join(ct_out,"engine-generated.flex"));
    let full=reference_literal(generated,"ca_hardware_api");let index=reference_literal(generated,"ca_hardware_index");
    let request=j_object();j_set(request,"config",ct_config);j_set(request,"action",j_string("permissions"));
    let policy=cj_get(ct_call(8,request),"policy");h_assert(policy && j_kind(policy)==4 && j_count(policy)>=31,"Incomplete permission policy");
    let denied=j_object();let fields=j_value(policy);let i=0;
    while i<h_count(fields){j_set(denied,load64(h_at(fields,i)),j_bool(0));i=i+1;}j_set(ct_config,"permissions",denied);
    let actual=ct_vm("fn main(){let v=hardware_api();if db_kind(v)!=2{return 1;}db_io(0,1,db_word(v),db_bytes(v));return 0;}");
    h_assert(h_equal(actual,index) && h_len(index)<=32768,"Compact hardware index changed or was truncated");
    ct_pass("the compact function index is returned intact through the actual VM with every capability denied");
    let size=h_len(full);let offset=0;
    while offset<size{
        let count=size-offset;if count>4096{count=4096;}let next=offset+count;if next==size{next=-1;}
        let source=h_replace(h_replace(h_replace("fn main(){let p=hardware_api_page(OFFSET,4096);if !p || db_word(device_field(p,\"total\"))!=TOTAL || db_word(device_field(p,\"next\"))!=NEXT{return 1;}let v=device_field(p,\"text\");db_io(0,1,db_word(v),db_bytes(v));return 0;}","OFFSET",h_int(offset)),"TOTAL",h_int(size)),"NEXT",h_int(next));
        actual=ct_vm(source);h_assert(h_len(actual)==count && h_bytes(actual,full+offset,count),h_cat("Hardware reference page differs at byte ",h_int(offset)));offset=offset+count;
    }
    ct_pass("every detailed reference byte is readable via bounded pages, including the full NFC/OMAPI contracts");
    actual=ct_vm("fn main(){let p=hardware_api_page(0,32768);if !p{return 1;}let v=device_field(p,\"text\");if db_bytes(v)!=32768{return 2;}db_io(0,1,db_word(v),db_bytes(v));return 0;}");
    h_assert(h_len(actual)==32768 && h_bytes(actual,full,32768),"Maximum hardware reference page was truncated");
    ct_pass("a maximum32768-byte reference page survives the complete typed RPC frame without truncation");
    ct_vm(h_replace(h_replace("fn main(){if hardware_api_page(-1,100) || hardware_api_page(0,0) || hardware_api_page(0,32769) || hardware_api_page(TOO_FAR,10){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"invalid_argument\"){return 2;}let end=hardware_api_page(EOF,10);if db_word(device_field(end,\"next\"))!=-1 || db_bytes(device_field(end,\"text\")){return 3;}return 0;}","TOO_FAR",h_int(size+1)),"EOF",h_int(size)));
    ct_pass("invalid page bounds are structured errors and an exact EOF returns an empty final page");
    let report=j_object();j_set(report,"reference_bytes",j_int(size));j_set(report,"index_bytes",j_int(h_len(index)));j_set(report,"denied_capabilities",j_int(j_count(policy)));return ct_done(report,"hardware-reference-report.json");
}
