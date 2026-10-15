// UTC calendar conversion for the TLS platform ABI. No host/device calls.
// Output follows the nine 32-bit fields of C struct tm (36 bytes).
fn ct_word(p,n) {let i=0;while i<4 {store8(p+i,n>>(i*8));i=i+1;}return 0;}
fn ct_gmtime(seconds,out,capacity) {
    if seconds<0 || seconds>253402300799 || !out || capacity<36 {return 0;}
    let days=seconds/86400;let rest=seconds%86400;let z=days+719468;let era=z/146097;let doe=z-era*146097;
    let yoe=(doe-doe/1460+doe/36524-doe/146096)/365;let year=yoe+era*400;let doy=doe-(365*yoe+yoe/4-yoe/100);let mp=(5*doy+2)/153;
    let day=doy-(153*mp+2)/5+1;let month=mp+3;if mp>=10 {month=mp-9;}if month<=2 {year=year+1;}
    let y=year-1;let first=365*(year-1970)+(y/4-1969/4)-(y/100-1969/100)+(y/400-1969/400);
    ct_word(out,rest%60);ct_word(out+4,rest/60%60);ct_word(out+8,rest/3600);ct_word(out+12,day);ct_word(out+16,month-1);ct_word(out+20,year-1900);ct_word(out+24,(days+4)%7);ct_word(out+28,days-first);ct_word(out+32,0);return out;
}
