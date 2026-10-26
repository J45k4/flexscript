import "../libs/http.flex";

fn main(argc,argv) {
    if argc!=2 {syscall(1,2,"Usage: http-client URL\n",23,0,0,0);return 2;}
    let options=http_client_options();
    let request=http_client_start("GET",load64(argv+8),"",0,0,options);
    http_client_options_free(options);
    if !request {syscall(1,2,http_client_message,net_length(http_client_message),0,0,0);return 1;}
    let result=http_client_wait(request);let error=http_client_error(request);
    if error {syscall(1,2,error,net_length(error),0,0,0);}
    if result>0 {
        let size=http_client_size(request);let at=0;
        while at<size {let n=syscall(1,1,http_client_data(request)+at,size-at,0,0,0);if n>0 {at=at+n;}else if n!=-4 {http_client_free(request);return 1;}}
    }
    let status=http_client_status(request);http_client_free(request);
    if result<0 || status<200 || status>=300 {return 1;}return 0;
}
