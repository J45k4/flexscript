// A tiny independent language: decimal integers, +, -, *, and whitespace.
// Example source: 6 7 *
import "../../compiler/extension-sdk.flex";
fn frontend_compile(text,size,version,path) {
    ir_init(text,size,path,version);ir_begin("main",4,0);
    let i=0;let depth=0;let maximum=0;
    while i<size {
        let c=load8(text+i);
        if c==32 || c==9 || c==10 || c==13 {i=i+1;}
        else if c>=48 && c<=57 {
            let value=0;while i<size && load8(text+i)>=48 && load8(text+i)<=57 {
                let digit=load8(text+i)-48;if value>(9223372036854775807-digit)/10 {ir_error("postfix integer out of range",i);}
                value=value*10+digit;i=i+1;
            }
            ir_emit(1,value);ir_emit(4,depth);depth=depth+1;if depth>4096 {ir_error("postfix stack limit",i);}
            if depth>maximum {maximum=depth;}
        }else if c==43 || c==45 || c==42 {
            if depth<2 {ir_error("postfix stack underflow",i);}
            ir_emit(3,depth-2);ir_emit(2,0);ir_emit(3,depth-1);ir_emit(7,c);ir_emit(4,depth-2);depth=depth-1;i=i+1;
        }else {ir_error("invalid postfix token",i);}
    }
    if depth!=1 {ir_error("postfix program must produce one result",size);}
    ir_emit(3,0);ir_emit(9,0);ir_end(maximum);return ir_finish();
}
