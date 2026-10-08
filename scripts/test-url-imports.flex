import "lib/harness.flex";
import "lib/tls-fixture.flex";
fn tu_route(routes,path,body) {
    let route=j_object();
    j_set(route,"body",j_string(body));
    j_set(routes,path,route);
    return route;
}
fn tu_redirect(routes,path,location) {
    let route=j_object();
    j_set(route,"location",j_string(location));
    j_set(routes,path,route);
    return 0;
}
fn tu_import(path,body) {
    return h_cat3("import \"",path,h_cat3("\"; ",body,""));
}
fn tu_reject(text,message) {
    t_program(text);
    h_save(t_binary,"preserve existing output");
    return t_reject(t_fixture,t_binary,message);
}
fn tu_vm(path,option,status,message) {
    let args=h_args(t_compiler,"run","--interpret",0,0,0);
    if option {
        h_add(args,option);
        if h_equal(option,"--restricted") {h_add(args,"--allow-url-imports");}
    }
    h_add(args,path);
    let p=h_run(args);
    h_check(p,status,"");
    if message { h_assert(h_has(h_err(p),message),h_err(p)); }
    t_checks=t_checks+1;
    return p;
}
fn tu_suite(compiler,secure) {
    t_init(compiler);
    let dir=h_join(t_work,"https");
    h_mkdir(dir);
    h_save(h_join(dir,"requests"),"");
    let mode=4;if !secure {mode=5;}
    let server=sf_start(dir,mode);
    let environment=h_env;
    if secure {h_setenv("SSL_CERT_FILE",h_join(dir,"localhost.pem"));}
    else {h_setenv("SSL_CERT_FILE","/no/such/certificate");}
    let url=sf_url;
    let routes=j_object();
    tu_route(routes,"/pkg/shared.flex","global answer=42;");
    tu_route(routes,"/pkg/a.flex","import \"./shared.flex\"; fn a(){return answer;}");
    tu_route(routes,"/pkg/b.flex","import \"../pkg/shared.flex\"; fn b(){return answer;}");
    tu_route(routes,"/pkg/main.flex","import \"a.flex\"; import \"b.flex\"; fn main(){return a()+b();}");
    tu_route(routes,"/pkg/root.flex","import \"/pkg/shared.flex\"; fn root(){return answer;}");
    tu_route(routes,"/pkg/protocol.flex",tu_import(h_cat(h_replace(h_replace(url,"https:",""),"http:",""),"/pkg/shared.flex"),"fn protocol(){return answer;}"));
    tu_route(routes,"/pkg/query.flex?old","import \"?new\"; fn query(){return queried;}");
    tu_route(routes,"/pkg/query.flex?new","global queried=31;");
    tu_route(routes,"/moved/library.flex","import \"value.flex\"; fn moved(){return relocated;}");
    tu_route(routes,"/moved/value.flex","global relocated=23;");
    tu_redirect(routes,"/redirect","/moved/library.flex");
    tu_redirect(routes,"/absolute",h_cat(url,"/moved/library.flex"));
    tu_redirect(routes,"/downgrade","http://localhost/source.flex");
    tu_redirect(routes,"/loop","/loop");
    tu_route(routes,"/cycle/a.flex","import \"b.flex\";");
    tu_route(routes,"/cycle/b.flex","import \"../cycle/./a.flex\";");
    tu_route(routes,"/cycle/redirect.flex","import \"/cycle/alias\";");
    tu_redirect(routes,"/cycle/alias","/cycle/redirect.flex");
    tu_route(routes,"/bad.flex","fn bad(){\n  return @;\n}");
    tu_route(routes,"/deferred.flex","fn bad(){\n  missing();\n}");
    tu_route(routes,"/empty.flex","");
    tu_route(routes,"/network.flex","fn main(){let fd=syscall(41,2,1,0,0,0,0);if fd<0{return 1;}syscall(3,fd,0,0,0,0,0);return 0;}");
    tu_route(routes,"/double//slash.flex","global doubled=17;");
    tu_route(routes,"/encoded/%2e%2e/value.flex","global encoded=19;");
    let chunks=h_buffer();
    h_text(chunks,"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n");
    let chunk_body="global chunked=29;";
    let at=0;
    while at<h_len(chunk_body) {
        h_text(chunks,"1\r\n");h_append(chunks,chunk_body+at,1);h_text(chunks,"\r\n");
        at=at+1;
    }
    h_text(chunks,"0\r\n\r\n");
    j_set(tu_route(routes,"/chunked.flex",""),"raw",j_string(h_data(chunks)));
    j_set(tu_route(routes,"/closed.flex",""),"raw",j_string("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nglobal closed=27;"));
    j_set(tu_route(routes,"/truncated.flex",""),"raw",j_string("HTTP/1.1 200 OK\r\nContent-Length: 100\r\nConnection: close\r\n\r\nshort"));
    j_set(tu_route(routes,"/ambiguous.flex",""),"raw",j_string("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"));
    let other=0;let plain_url=0;
    if secure {
        let plain_dir=h_join(t_work,"plain");h_mkdir(plain_dir);
        h_save(h_join(plain_dir,"requests"),"");
        other=sf_start(plain_dir,5);plain_url=sf_url;
        let plain_routes=j_object();
        tu_route(plain_routes,"/plain.flex","global plain=9;");
        tu_redirect(plain_routes,"/upgrade",h_cat(url,"/pkg/shared.flex"));
        tu_redirect(plain_routes,"/upgrade-downgrade",h_cat(url,"/downgrade"));
        j_save(h_join(plain_dir,"routes.json"),plain_routes);
        tu_redirect(routes,"/downgrade",h_cat(plain_url,"/plain.flex"));
        tu_route(routes,"/mixed.flex",tu_import(h_cat(plain_url,"/plain.flex"),"fn mixed(){return plain;}"));
    }
    let secret=h_join(t_work,"secret.flex");
    h_save(secret,"global remote_value=99;");
    tu_route(routes,secret,"global remote_value=11;");
    tu_route(routes,"/absolute-path.flex",tu_import(secret,"fn remote_path(){return remote_value;}"));
    let i=1;
    while i<64 {
        let body="global deepest=7;";
        if i<63 { body=tu_import(h_cat3("f",h_int(i+1),".flex"),""); }
        tu_route(routes,h_cat3("/depth/f",h_int(i),".flex"),body);
        i=i+1;
    }
    i=0;
    while i<256 {
        tu_route(routes,h_cat3("/count/f",h_int(i),".flex"),"");
        i=i+1;
    }
    let large=h_join(dir,"large.flex");
    h_save(large,h_repeat(" ",16777216));
    let large_route=tu_route(routes,"/large.flex","");
    j_set(large_route,"file",j_string(large));
    j_save(h_join(dir,"routes.json"),routes);

    t_native(tu_import(h_cat(url,"/pkg/shared.flex"),"fn main(){return answer;}"),42,"");
    t_native(tu_import(h_cat(url,"/pkg/a.flex"),tu_import(h_cat(url,"/pkg/b.flex"),"fn main(){return a()+b();}")),84,"");
    let requests=h_read(h_join(dir,"requests"));
    h_save(h_join(dir,"requests"),"");
    t_native(tu_import(h_cat(url,"/pkg/shared.flex"),tu_import(h_cat(url,"/pkg/../pkg/./shared.flex"),"fn main(){return answer;}")),42,"");
    t_assert(h_equal(h_read(h_join(dir,"requests")),"/pkg/shared.flex\n"),"repeated normalized URL was fetched twice");
    t_native(tu_import(h_cat(h_replace(url,"localhost","LOCALHOST"),"/pkg/shared.flex"),tu_import(h_cat(url,"/pkg/shared.flex"),"fn main(){return answer;}")),42,"");
    t_native(tu_import(h_cat(url,"/../../../pkg/shared.flex"),"fn main(){return answer;}"),42,"");
    t_native(tu_import(h_cat(url,"/pkg/root.flex"),"fn main(){return root();}"),42,"");
    t_native(tu_import(h_cat(url,"/pkg/protocol.flex"),"fn main(){return protocol();}"),42,"");
    t_native(tu_import(h_cat(url,"/pkg/query.flex?old"),"fn main(){return query();}"),31,"");
    t_native(tu_import(h_cat(url,"/redirect"),tu_import(h_cat(url,"/moved/library.flex"),"fn main(){return moved();}")),23,"");
    t_native(tu_import(h_cat(url,"/absolute"),"fn main(){return moved();}"),23,"");
    t_native(tu_import(h_cat(url,"/empty.flex"),"fn main(){return 0;}"),0,"");
    t_native(tu_import(h_cat(url,"/double//slash.flex"),"fn main(){return doubled;}"),17,"");
    t_native(tu_import(h_cat(url,"/encoded/%2e%2e/value.flex"),"fn main(){return encoded;}"),19,"");
    t_native(tu_import(h_cat(url,"/chunked.flex"),"fn main(){return chunked;}"),29,"");
    t_native(tu_import(h_cat(url,"/closed.flex"),"fn main(){return closed;}"),27,"");
    if secure {
        t_native(tu_import(h_cat(plain_url,"/upgrade"),"fn main(){return answer;}"),42,"");
        t_native(tu_import(h_cat(url,"/mixed.flex"),"fn main(){return mixed();}"),9,"");
        tu_reject(tu_import(h_cat(plain_url,"/upgrade-downgrade"),"fn main(){}"),"must use HTTPS");
    }
    h_compile(t_compiler,h_cat(url,"/pkg/main.flex"),t_binary);
    h_check(h_run(h_args(t_binary,0,0,0,0,0)),84,"");
    t_checks=t_checks+1;
    // Remote libraries remain compatible with local definitions.
    h_save(h_join(t_work,"local.flex"),"global local=5;");
    t_native(tu_import("local.flex",tu_import(h_cat(url,"/pkg/shared.flex"),"fn main(){return answer+local;}")),47,"");
    t_native(tu_import(h_cat(url,"/absolute-path.flex"),"fn main(){return remote_path();}"),11,"");
    t_native(tu_import(h_cat(url,"/depth/f1.flex"),"fn main(){return deepest;}"),7,"");
    tu_route(routes,"/depth/f63.flex","import \"f64.flex\"; global deepest=7;");
    tu_route(routes,"/depth/f64.flex","");
    j_save(h_join(dir,"routes.json"),routes);
    tu_reject(tu_import(h_cat(url,"/depth/f1.flex"),"fn main(){return deepest;}"),"import nesting exceeds 64");
    let many=h_buffer();
    i=0;
    while i<255 {
        h_text(many,tu_import(h_cat3(url,"/count/f",h_cat(h_int(i),".flex")),""));
        i=i+1;
    }
    t_native(h_cat(h_data(many),"fn main(){}"),0,"");
    tu_reject(h_cat(h_data(many),tu_import(h_cat(url,"/count/f255.flex"),"fn main(){}")),"too many imported files");

    tu_reject(tu_import(h_cat(url,"/cycle/a.flex"),"fn main(){}"),"circular import");
    tu_reject(tu_import(h_cat(url,"/cycle/redirect.flex"),"fn main(){}"),"circular import");
    let p=tu_reject(tu_import(h_cat(url,"/bad.flex"),"fn main(){}"),"unexpected source byte");
    t_assert(h_has(h_err(p),h_cat(url,"/bad.flex:2:10: error:")),h_err(p));
    p=tu_reject(tu_import(h_cat(url,"/deferred.flex"),"fn main(){}"),"undefined function");
    t_assert(h_has(h_err(p),h_cat(url,"/deferred.flex:2:3: error:")),h_err(p));
    tu_reject(tu_import(h_cat(url,"/missing.flex"),"fn main(){}"),"non-success status");
    if secure {tu_reject(tu_import(h_cat(url,"/downgrade"),"fn main(){}"),"must use HTTPS");}
    tu_reject(tu_import(h_cat(url,"/loop"),"fn main(){}"),"Too many HTTP redirects");
    tu_reject(tu_import(h_cat(url,"/large.flex"),"fn main(){}"),"size limit");
    tu_reject(tu_import(h_cat(url,"/truncated.flex"),"fn main(){}"),"Truncated HTTP body");
    tu_reject(tu_import(h_cat(url,"/ambiguous.flex"),"fn main(){}"),"HTTP");
    tu_reject(tu_import("ftp://localhost/source.flex","fn main(){}"),"source URLs must use HTTP or HTTPS");
    tu_reject(tu_import("file:///etc/passwd","fn main(){}"),"source URLs must use HTTP or HTTPS");
    tu_reject(tu_import("https://user@localhost/a.flex","fn main(){}"),"invalid source URL authority");
    tu_reject(tu_import("https://localhost:65536/a.flex","fn main(){}"),"invalid source URL port");
    tu_reject(tu_import("https://localhost/a.flex#fragment","fn main(){}"),"invalid source URL path");
    if secure {
        h_setenv("SSL_CERT_FILE","/no/such/certificate");
        tu_reject(tu_import(h_cat(url,"/pkg/shared.flex"),"fn main(){}"),"TLS");
        h_setenv("SSL_CERT_FILE",h_join(dir,"localhost.pem"));
        tu_reject(tu_import(h_cat(h_replace(url,"localhost","127.0.0.1"),"/pkg/shared.flex"),"fn main(){}"),"TLS");
    }

    t_program(tu_import(h_cat(url,"/pkg/shared.flex"),"fn main(){return answer;}"));
    requests=h_read(h_join(dir,"requests"));
    tu_vm(t_fixture,"--no-url-imports",1,"--no-url-imports");
    tu_vm(h_cat(url,"/pkg/main.flex"),"--no-url-imports",1,"--no-url-imports");
    t_assert(h_equal(requests,h_read(h_join(dir,"requests"))),"VM fetched a URL with imports disabled");
    tu_vm(t_fixture,0,42,0);
    tu_vm(h_cat(url,"/pkg/main.flex"),0,84,0);
    tu_vm(h_cat(url,"/network.flex"),0,0,0);
    tu_vm(h_cat(url,"/network.flex"),"--restricted",70,"capability denied");
    tu_vm(t_fixture,"--allow-url-imports",42,0);
    h_stop(server);
    if other {h_stop(other);}
    h_env=environment;
    return t_done();
}
fn suite(compiler) {
    let https=tu_suite(compiler,1);
    let http=tu_suite(compiler,0);
    return https+http;
}
fn main(argc,argv) {
    return t_entry(argc,argv);
}
