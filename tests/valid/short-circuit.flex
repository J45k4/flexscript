global n=0; fn bump() { n=n+1; return 5; } fn main() { let a=0 && bump(); let b=1 || bump(); let c=1 && bump(); let d=0 || bump(); return n*10+a+b+c+d; }
