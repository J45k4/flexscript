fn main() { let s="a\t\r\n\\\"\0"; return (load8(s+1)==9)+(load8(s+2)==13)+(load8(s+3)==10)+(load8(s+4)==92)+(load8(s+5)==34)+(load8(s+6)==0); }
