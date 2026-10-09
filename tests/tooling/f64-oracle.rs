// Optional offline binary64 oracle; ordinary checks use committed words.
use std::io::Write;
fn next(s:&mut u64)->u64{*s=s.wrapping_add(0x9e3779b97f4a7c15);let mut z=*s;z=(z^(z>>30)).wrapping_mul(0xbf58476d1ce4e5b9);z=(z^(z>>27)).wrapping_mul(0x94d049bb133111eb);z^(z>>31)}
fn canon(x:f64)->u64{if x.is_nan(){0x7ff8000000000000}else{x.to_bits()}}
fn row(o:&mut std::fs::File,op:i64,a:u64,b:u64,v:u64){for x in [op as u64,a,b,v]{o.write_all(&x.to_le_bytes()).unwrap()}}
fn pair(o:&mut std::fs::File,a:u64,b:u64){let x=f64::from_bits(a);let y=f64::from_bits(b);for(op,v)in [(0,canon(x+y)),(1,canon(x-y)),(2,canon(x*y)),(3,canon(x/y)),(4,(x<y)as u64),(5,(x==y)as u64),(6,(x<=y)as u64),(11,(x>y)as u64),(12,(x>=y)as u64),(13,(x!=y)as u64),(14,canon(x.sqrt()))]{row(o,op,a,b,v)}for(op,v)in [(8,x as i64),(9,x.round_ties_even()as i64),(10,x.round()as i64)]{row(o,op,a,0,v as u64)}}
fn main(){let mut o=std::fs::File::create(std::env::args().nth(1).expect("output fixture path")).unwrap();let edge=[0u64,0x8000000000000000,1,2,3,0xfffffffffffff,0x10000000000000,0x10000000000001,0x10000000000002,0x7ff0000000000000,0xfff0000000000000,0x7fefffffffffffff,0xffefffffffffffff,0x7ff8000000000001,0xfff8000000000001,0x7ff0000000000001,0xfff0000000000001,0x3ff0000000000000,0x3fe0000000000000,0x3ff8000000000000,0x4004000000000000,0x4330000000000000,0x433fffffffffffff,0x4340000000000000,0x43dfffffffffffff,0x43e0000000000000,0xc3e0000000000000];for &a in &edge{for &b in &edge{pair(&mut o,a,b)}}
let mut s=123;for _ in 0..3072{let a=next(&mut s);let b=next(&mut s);pair(&mut o,a,b);row(&mut o,7,a,0,canon((a as i64)as f64));}
for n in -1022..=1023{if n%7==0{let a=((n+1023)as u64)<<52;let half=2f64.powi(n-53);pair(&mut o,a,half.to_bits());pair(&mut o,a|1,half.to_bits());}}
for a in [0i64,1,-1,i64::MIN,i64::MAX,9007199254740991,9007199254740993,-9007199254740993]{row(&mut o,7,a as u64,0,canon(a as f64))}
}
