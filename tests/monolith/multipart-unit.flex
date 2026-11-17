import "monolith/multipart.flex";
fn check(ok,message) {if !ok {m_print(2,message);m_print(2,"\n");syscall(60,1,0,0,0,0,0);}return 0;}
fn main(argc,argv) {
 let input="--foo\r\nContent-Disposition: form-data; name=\"file\"; filename=\"data.bin\"\r\nContent-Type: application/octet-stream\r\n\r\na\0b\r\n--foox\r\nc\r\n--foo\r\nContent-Disposition: form-data; name=\"field\"\r\n\r\nhello\r\n--foo--\r\n";let n=174;
 // Embedded NUL means the fixture length must come from the explicit literals.
 n=m_len("--foo\r\nContent-Disposition: form-data; name=\"file\"; filename=\"data.bin\"\r\nContent-Type: application/octet-stream\r\n\r\na")+1+m_len("b\r\n--foox\r\nc\r\n--foo\r\nContent-Disposition: form-data; name=\"field\"\r\n\r\nhello\r\n--foo--\r\n");
 let s=mono_mp_open("multipart/form-data; boundary=foo",input,n,4);check(s,"open");check(mono_mp_next(s)==1,"first");check(m_eq(mono_mp_name(s),"file") && m_eq(mono_mp_filename(s),"data.bin"),"metadata");let p=mono_mp_data(s);check(mono_mp_size(s)==14 && load8(p)==97 && load8(p+1)==0 && load8(p+2)==98,"binary");check(mono_mp_next(s)==1 && m_eq(mono_mp_name(s),"field") && mono_mp_size(s)==5,"second");check(mono_mp_next(s)==0,"final");check(!mono_mp_open("multipart/form-data; boundary=foo; boundary=bar",input,n,4),"duplicate boundary");m_print(1,"multipart parser passed\n");return 0;
}
