import "monolith/web.flex";
fn app_init(path) {return 0;}fn app_tick() {return 0;}
fn app_request(fd) {if !web_multipart {return web_reply(fd,200,"text/plain","urlencoded","");}let status=mono_mp_next(web_multipart);if status!=1 || !m_eq(mono_mp_name(web_multipart),"file") {return web_reply(fd,400,"text/plain","missing file","");}let n=mono_mp_size(web_multipart);let p=mono_mp_data(web_multipart);let hash=0;let i=0;while i<n {hash=(hash*31+load8(p+i))%1000000007;i=i+1;}return web_reply(fd,200,"text/plain",m_cat(m_cat(m_int(n),":"),m_int(hash)),"");}
fn main(argc,argv) {return web_run(argc,argv,35551,"/tmp/monolith-test.flexdb");}
