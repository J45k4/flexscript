// Strict, length-delimited UTF-8. An encoded read is (scalar<<3)|byte_count.
// Explicit lengths support U+0000; invalid/truncated encodings return -1.
global unicode_error=0;
fn unicode_fail(message){unicode_error=message;return 0;}
fn unicode_utf8_read(text,n,at){
    if !text || at<0 || at>=n{return -1;}let c=load8(text+at);if c<128{return (c<<3)|1;}let bytes=0;let cp=0;let minimum=0;
    if c>=194 && c<=223{bytes=2;cp=c&31;minimum=128;}else if c>=224 && c<=239{bytes=3;cp=c&15;minimum=2048;}else if c>=240 && c<=244{bytes=4;cp=c&7;minimum=65536;}else{return -1;}
    if at>n-bytes{return -1;}let i=1;while i<bytes{let b=load8(text+at+i);if b<128 || b>191{return -1;}cp=(cp<<6)|(b&63);i=i+1;}if cp<minimum || cp>1114111 || (cp>=55296 && cp<=57343){return -1;}return (cp<<3)|bytes;
}
