import "lower.flex";
import "../../../compiler/source-sdk.flex";
fn frontend_compile(text,size,version,path) {
    if version!=1 {pg_init(text,size,path);pg_error("unsupported frontend API version");}
    pup_parse(text,size,path);let source=pup_lower();return frontend_source(source,pl_size);
}
