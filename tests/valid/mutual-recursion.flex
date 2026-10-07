fn even(n) { if n == 0 { return 1; } return odd(n-1); } fn odd(n) { if n == 0 { return 0; } return even(n-1); } fn main() { return even(8); }
