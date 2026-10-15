// Allocation-free byte helpers shared by bounded application protocols.
fn nb_copy(out,input,size) {let i=0;while i<size {store8(out+i,load8(input+i));i=i+1;}return size;}
fn nb_zero(out,size) {let i=0;while i<size {store8(out+i,0);i=i+1;}return 0;}
fn nb_lower(c) {if c>=65 && c<=90 {return c+32;}return c;}
fn nb_equal(a,b,size) {let i=0;while i<size {if load8(a+i)!=load8(b+i) {return 0;}i=i+1;}return 1;}
fn nb_ci(a,size,b,bsize) {if size!=bsize {return 0;}let i=0;while i<size {if nb_lower(load8(a+i))!=nb_lower(load8(b+i)) {return 0;}i=i+1;}return 1;}
fn nb_token(c) {if (c>=48 && c<=57) || (c>=65 && c<=90) || (c>=97 && c<=122) {return 1;}let t="!#$%&'*+-.^_`|~";let i=0;while i<15 {if c==load8(t+i) {return 1;}i=i+1;}return 0;}
fn nb_hex(c) {if c>=48 && c<=57 {return c-48;}c=nb_lower(c);if c>=97 && c<=102 {return c-87;}return -1;}
fn nb_digits(n,base) {let size=1;while n>=base {n=n/base;size=size+1;}return size;}
fn nb_number(out,n,base) {let digits=nb_digits(n,base);let i=digits;let alphabet="0123456789abcdef";while i {i=i-1;store8(out+i,load8(alphabet+n%base));n=n/base;}return digits;}
