// Common byte filling; chip wrappers select the random-word register.
fn esp_radio_cb_random(a,b,c,d,e,f,g,h) {return esp_radio_random_word();
}
fn esp_radio_cb_get_random(a,b,c,d,e,f,g,h) {let i=0;while i<b {let n=esp_radio_random_word();let j=0;while j<4 && i<b {store8(a+i,n>>(j*8));i=i+1;j=j+1;}}return 0;
}
fn esp_fill_random(a,b,c,d,e,f,g,h) {let i=0;while i<b {let n=esp_radio_random_word();let j=0;while j<4 && i<b {store8(a+i,n>>(j*8));i=i+1;j=j+1;}}return 0;
}
