// Guest typed-value JSON printer used by host integration fixtures.
fn text(p,n){db_io(0,1,p,n);}
fn number(n){let p=alloc(32);let i=32;if n==0{text("0",1);return 0;}while n>0{i=i-1;store8(p+i,48+n%10);n=n/10;}text(p+i,32-i);return 0;}
fn dump(v){let kind=db_kind(v);if kind==0{text("null",4);}else if kind==1{number(db_word(v));}else if kind==2 || kind==3{let p=db_word(v);let i=0;text("\"",1);while i<db_bytes(v){let c=load8(p+i);if c==34 || c==92{text("\\",1);text(p+i,1);}else if c<32{let b=alloc(6);db_copy(b,"\\u00",4);store8(b+4,load8("0123456789abcdef"+c/16));store8(b+5,load8("0123456789abcdef"+c%16));text(b,6);}else{text(p+i,1);}i=i+1;}text("\"",1);}else{let i=0;text("[",1);while i<db_count(v){if i{text(",",1);}dump(db_at(v,i));i=i+1;}text("]",1);}return 0;}
