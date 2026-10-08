import "../lib/http.flex";
fn main(argc,argv) {
    if argc!=2 {let usage="Usage: https-get https://host/path\n";syscall(1,2,usage,net_length(usage),0,0,0);return 1;}
    if !https_get(load64(argv+8),1048576,30000) {
        if net_message {syscall(1,2,net_message,net_length(net_message),0,0,0);}return 1;
    }
    let sent=0;while sent<http_size {let n=syscall(1,1,http_output+sent,http_size-sent,0,0,0);if n<=0 {return 1;}sent=sent+n;}return 0;
}
