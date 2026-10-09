// The same bundled frontend can also be loaded as an ordinary extension.
import "../../compiler/frontends/seta.flex";
fn frontend_compile(text,size,version,path) {return seta_frontend(text,size,version,path);}
