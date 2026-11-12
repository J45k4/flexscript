import "../../libs/monolith/cache.flex";
global rc_checks=0;
fn rc_check(ok,message) {m_assert(ok,message);rc_checks=rc_checks+1;return 0;}
fn main() {
    rc_check(mono_resource_limits(16384,2,8192),"limits");
    let data=m_take(4);m_copy(data,"abc",4);let first=mono_resource_bytes(data,3,"text/plain");rc_check(first,"snapshot");store8(data,122);
    rc_check(m_eq(mono_resource_data(first),"abc"),"snapshot owns bytes");rc_check(mono_resource_size(first)==3,"binary length");
    let tag=mono_resource_etag(first);rc_check(mono_resource_matches(tag,tag),"strong match");rc_check(mono_resource_matches(m_cat("W/",tag),tag),"weak match");
    rc_check(mono_resource_matches(m_cat("\"x,y\", W/",tag),tag),"comma inside opaque tag");rc_check(mono_resource_matches(m_cat(", , ",m_cat(tag,", \t")),tag),"empty list members");
    rc_check(mono_resource_matches(" * \t",tag),"wildcard");rc_check(!mono_resource_matches(m_cat(tag,", garbage"),tag),"malformed tail cannot match");rc_check(!mono_resource_matches(m_cat("*,",tag),tag),"wildcard is not a list member");
    rc_check(!mono_resource_matches("\"unterminated",tag),"malformed tag");rc_check(!mono_resource_matches(m_cat("w/",tag),tag),"weak prefix is case sensitive");
    rc_check(!mono_resource_bytes(data,3,"text/plain\r\nInjected: yes"),"MIME injection rejected");rc_check(!mono_resource_bytes(data,8193,"text/plain"),"size cap");
    let second=mono_resource_bytes("",0,"application/octet-stream");rc_check(second && mono_resource_size(second)==0,"empty binary snapshot");
    rc_check(!mono_resource_bytes("x",1,"text/plain"),"count cap");rc_check(!mono_resource_limits(32768,3,8192),"cannot reconfigure populated cache");
    rc_check(mono_resource_count()==2 && mono_resource_retained_bytes()==8192,"bounded accounting");rc_check(mono_resource_release(second),"release");rc_check(!mono_resource_release(second),"double release rejected");
    mono_resources_clear();rc_check(!mono_resource_count() && !mono_resource_retained_bytes(),"clear");
    rc_check(mono_resource_limits(8192,3,8192),"new empty limits");let big=m_take(5000);let i=0;while i<5000 {store8(big+i,i%256);i=i+1;}
    let binary=mono_resource_bytes(big,5000,"application/octet-stream");rc_check(binary && load8(mono_resource_data(binary)+4096)==0,"NUL bytes preserved");rc_check(!mono_resource_bytes("",0,"text/plain"),"retained page budget");
    mono_resources_clear();mono_resource_limits(16384,3,8192);let mark=m_mark();let scratch=m_take(8);m_copy(scratch,"arena",6);let owned=mono_resource_bytes(scratch,5,"text/plain");m_reset(mark);rc_check(m_eq(mono_resource_data(owned),"arena"),"snapshot survives request arena reset");
    let other=mono_resource_bytes("arena",5,"text/javascript");rc_check(!m_eq(mono_resource_version(owned),mono_resource_version(other)),"MIME identity changes version");
    rc_check(mono_resource_match(mono_resource_url("/test",owned),"/test",owned)==2,"version URL");rc_check(mono_resource_match("/test","/test",owned)==1,"alias URL");rc_check(!mono_resource_match("/test?v=old","/test",owned),"stale version rejected");
    rc_check(!mono_resource_url("/test?x=y",owned),"query URL rejected");rc_check(!mono_resource_url("//outside.example/path",owned),"network-path URL rejected");mono_resources_clear();m_print(1,m_cat("Resource unit checks passed: ",m_cat(m_int(rc_checks),"\n")));return 0;
}
