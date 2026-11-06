// Quote a UTF-8 string as a Flexscript source literal.
import "json.flex";
fn source_quote(text){
    let b=h_buffer();h_text(b,"\"");let i=0;
    while load8(text+i){let c=load8(text+i);if c==34||c==92{h_text(b,"\\");h_append(b,text+i,1);}else if c==10{h_text(b,"\\n");}else if c==13{h_text(b,"\\r");}else if c==9{h_text(b,"\\t");}else if c==8{h_text(b,"\\b");}else if c==12{h_text(b,"\\f");}else if c<32{h_text(b,"\\u00");h_text(b,h_hex(text+i,1));}else{h_append(b,text+i,1);}i=i+1;}
    h_text(b,"\"");return h_data(b);
}
