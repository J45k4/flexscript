import "../../libs/monolith/web.flex";
global rw_resource=0;
fn app_init(path) {rw_resource=mono_resource_file(path,"application/octet-stream");m_assert(rw_resource,mono_resource_error);return 0;}
fn app_tick() {return 0;}
fn app_request(fd) {
    if m_eq(web_path,"/asset") {let version=web_get("v");if m_len(version) && !m_eq(version,mono_resource_version(rw_resource)) {return web_reply(fd,404,"text/plain","Wrong version","");}let mode="revalidate";if m_len(version) && web_field_count==1 {mode="immutable";}return web_resource(fd,rw_resource,mode,31536000);}
    if m_eq(web_path,"/private") {if !m_eq(web_cookie,"allow=1") {return web_reply(fd,401,"text/plain","Unauthorized","");}return web_resource(fd,rw_resource,"private",0);}
    if m_eq(web_path,"/no-store") {return web_resource(fd,rw_resource,"no-store",0);}
    if m_eq(web_path,"/generic-304") {return web_reply(fd,304,"text/plain","not a response body","");}
    if m_eq(web_path,"/stats") {return web_reply(fd,200,"text/plain",m_int(mono_resource_count()),"");}
    return web_reply(fd,200,"text/plain","dynamic","");
}
fn main(argc,argv) {return web_run(argc,argv,9021,"missing.fixture");}
