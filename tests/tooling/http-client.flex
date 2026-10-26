import "../../scripts/lib/json.flex";
import "../../libs/http.flex";
fn ht_n(o,key) {let p=j_get(o,key);if p {return j_value(p);}return 0;}
fn ht_s(o,key) {let p=j_get(o,key);if p {return j_value(p);}return "";}

fn ht_fd_count() {
    let fd=syscall(2,"/proc/self/fd",0x90000,0,0,0,0);let buffer=alloc(8192);
    let count=0;let n=syscall(217,fd,buffer,8192,0,0,0);let at=0;
    while at<n {let size=load8(buffer+at+16)|(load8(buffer+at+17)<<8);let name=buffer+at+19;
        if !net_equal(name,".") && !net_equal(name,"..") {count=count+1;}at=at+size;
    }tcp_close(fd);syscall(11,buffer,8192,0,0,0,0);return count;
}
fn main(argc,argv) {
    h_environment(argc,argv);h_restore_sigpipe();let config=j_parse(h_read(load64(argv+8)));
    let jobs=j_get(config,"jobs");let count=j_count(jobs);let records=alloc(count*32);
    let initial=ht_fd_count();let start=net_now();let active=0;let i=0;
    while i<count {
        let job=j_at(jobs,i);let opts=http_client_options();let timeout=ht_n(job,"timeout");if !timeout {timeout=2000;}
        store64(opts,timeout);let limit=j_get(job,"limit");if limit {store64(opts+8,j_value(limit));}
        store64(opts+16,ht_n(job,"redirects"));store64(opts+24,ht_n(job,"https_only"));
        store64(opts+40,ht_n(job,"truncate"));let ca=j_get(job,"ca");if ca {store64(opts+32,j_value(ca));}
        let method=ht_s(job,"method");if !load8(method) {method="GET";}
        let body=0;let size=0;let upload=j_get(job,"body_hex");
        if upload {body=h_unhex(j_value(upload));size=h_len(j_value(upload))/2;}
        let request=http_client_start(method,j_s(job,"url"),ht_s(job,"headers"),body,size,opts);
        if request && ht_n(job,"cancel_immediate") {http_client_cancel(request);}
        http_client_options_free(opts);let record=records+i*32;store64(record,request);
        if request {active=active+1;}else {store64(record+8,http_client_message);}i=i+1;
    }
    while active {
        i=0;while i<count {let record=records+i*32;let request=load64(record);
            if request && !load64(record+16) {
                let cancel=ht_n(j_at(jobs,i),"cancel_after");if cancel && net_now()-start>=cancel {http_client_cancel(request);}
                let result=http_client_step(request);
                if http_client_size(request)>0 && result==0 {store64(record+24,1);}
                if result {store64(record+16,net_now()-start+1);active=active-1;}
            }i=i+1;
        }h_sleep(1);
    }
    let rows=j_array();i=0;
    while i<count {
        let record=records+i*32;let request=load64(record);let row=j_object();
        j_set(row,"elapsed",j_int(load64(record+16)));j_set(row,"streamed",j_bool(load64(record+24)));
        if request {
            j_set(row,"status",j_int(http_client_status(request)));j_set(row,"size",j_int(http_client_size(request)));
            j_set(row,"body_hex",j_string(h_hex(http_client_data(request),http_client_size(request))));
            let url=http_client_url(request);j_set(row,"url",j_string(h_slice(url,h_len(url))));j_set(row,"truncated",j_bool(http_client_truncated(request)));
            let header=http_client_header(request,"X-Test");if header {j_set(row,"header",j_string(h_slice(header,h_len(header))));}
            let error=http_client_error(request);if error {j_set(row,"error",j_string(error));}
            http_client_free(request);
        }else {j_set(row,"error",j_string(load64(record+8)));}
        j_push(rows,row);i=i+1;
    }
    let output=j_object();j_set(output,"jobs",rows);j_set(output,"fds_before",j_int(initial));j_set(output,"fds_after",j_int(ht_fd_count()));
    j_set(output,"children",j_int(syscall(61,-1,0,1,0,0,0)));h_print(1,j_dump(output));return 0;
}
