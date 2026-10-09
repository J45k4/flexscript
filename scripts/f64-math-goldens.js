// Optional offline oracle: the unchanged libm0.2.16 crate supplies every bit.
import { mkdir } from 'node:fs/promises'
import { createHash } from 'node:crypto'
const write=async (path,value)=>{if(Bun.argv.includes('--check')){const actual=new Uint8Array(await Bun.file(path).arrayBuffer());const expected=typeof value==='string'?new TextEncoder().encode(value):new Uint8Array(value);if(actual.length!==expected.length||actual.some((v,i)=>v!==expected[i]))throw Error(`Oracle changed: ${path}`)}else await Bun.write(path,value)}
const crate=process.env.LIBM_SOURCE
if(!crate)throw Error('Set LIBM_SOURCE to the original libm0.2.16 source directory')
const directory=`/tmp/setaworld-libm-oracle-${crypto.randomUUID()}`
await mkdir(`${directory}/src`,{recursive:true})
await Bun.write(`${directory}/Cargo.toml`,`[package]\nname='setaworld-libm-oracle'\nversion='0.1.0'\nedition='2021'\n[dependencies]\nlibm={path='${crate}'}\n`)
await Bun.write(`${directory}/src/main.rs`,`use std::io::{Read,Write};fn main(){let mut raw=Vec::new();std::io::stdin().read_to_end(&mut raw).unwrap();let mut out=Vec::new();for r in raw.chunks_exact(24){let op=i64::from_le_bytes(r[..8].try_into().unwrap());let a=u64::from_le_bytes(r[8..16].try_into().unwrap());let b=u64::from_le_bytes(r[16..].try_into().unwrap());let x=f64::from_bits(a);let y=f64::from_bits(b);let z=match op{0=>libm::hypot(x,y),1=>libm::atan(x),2=>libm::atan2(x,y),3=>libm::exp(x),4=>libm::scalbn(x,b as i64 as i32),5=>libm::sin(x),6=>libm::cos(x),_=>panic!()};out.extend_from_slice(&op.to_le_bytes());out.extend_from_slice(&a.to_le_bytes());out.extend_from_slice(&b.to_le_bytes());out.extend_from_slice(&z.to_bits().to_le_bytes());}std::io::stdout().write_all(&out).unwrap();}`)
const build=Bun.spawn(['cargo','build','--offline','--release','--manifest-path',`${directory}/Cargo.toml`],{stdout:'inherit',stderr:'inherit',env:{...process.env,CARGO_TARGET_DIR:`${directory}/target`,RUSTFLAGS:'-Awarnings'}})
if(await build.exited)throw Error('Original libm offline oracle build failed')
const bits=x=>{const b=new DataView(new ArrayBuffer(8));b.setFloat64(0,x,true);return b.getBigUint64(0,true)}
const rows=[]
const edge=[0n,1n,0x8000000000000000n,0x8000000000000001n,0x000fffffffffffffn,0x0010000000000000n,0x7fefffffffffffffn,0x7ff0000000000000n,0xfff0000000000000n,0x7ff8000000000000n,0xfff8000000000000n,0x7ff0000000000001n,0xfff0000000000001n,...[1,-1,.35,.4375,.6875,1.1875,2.4375,1e-9,1e-6,1e-3,1e-12,1e-300,1e300,1/60,.1,.5,.6,.7,9.8,Math.PI,-Math.PI].map(bits)]
for(const a of edge){for(const op of [1,3])rows.push([op,a,0n]);for(const b of edge)for(const op of [0,2])rows.push([op,a,b]);for(const n of [-2147483648,-2000,-1075,-1023,-1022,-970,-969,-53,-1,0,1,53,969,1022,1023,1075,2000,2147483647])rows.push([4,a,BigInt.asUintN(64,BigInt(n))])}
let seed=0x3518907
const word=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed}
const randomBits=()=>BigInt(word())<<32n|BigInt(word())
for(let i=0;i<6000;i++){const a=randomBits(),b=randomBits();rows.push([0,a,b],[1,a,0n],[2,a,b],[3,a,0n],[4,a,BigInt.asUintN(64,BigInt(word()%5000-2500))])}
for(let i=-1500;i<=1500;i++) {const x=i/2;rows.push([3,bits(x),0n]);for(const delta of [-1n,0n,1n])rows.push([1,bits(i/160)+delta,0n])}
// All finite trig fixtures are within the explicitly supported original medium
// reduction range. Original huge-argument fixtures are retained separately.
const unsupported=[]
const trig=a=>{const ix=Number((a>>32n)&0x7fffffffn);for(const op of [5,6]){if(ix<0x413921fb||ix>=0x7ff00000)rows.push([op,a,0n]);else unsupported.push([op,a,0n])}}
for(const a of edge)trig(a)
for(let i=0;i<6000;i++){trig(bits((word()/4294967296-.5)*3200000));trig(randomBits())}
for(let i=-1600;i<=1600;i++)for(const delta of [-1n,0n,1n])trig(BigInt.asUintN(64,bits(i*Math.PI/160)+delta))
for(const high of [0x3e46a09e,0x3e500000,0x3fe921fb,0x4002d97c,0x400f6a7a,0x4012d97c,0x4015fdbc,0x401921fb,0x401c463b,0x413921fa])for(const low of [0n,1n,0xffffffffn])for(const sign of [0n,0x8000000000000000n])trig(sign|(BigInt(high)<<32n)|low)
const input=new DataView(new ArrayBuffer(rows.length*24))
rows.forEach((r,i)=>r.forEach((v,f)=>input.setBigUint64(i*24+f*8,BigInt(v),true)))
const child=Bun.spawn([`${directory}/target/release/setaworld-libm-oracle`],{stdin:new Uint8Array(input.buffer),stdout:'pipe',stderr:'inherit'})
const output=await new Response(child.stdout).arrayBuffer()
if(await child.exited || output.byteLength!==rows.length*32)throw Error('Original libm oracle failed')
await write('tests/tooling/f64-math-goldens.words',output)
const extra=new DataView(new ArrayBuffer(unsupported.length*24))
unsupported.forEach((r,i)=>r.forEach((v,f)=>extra.setBigUint64(i*24+f*8,BigInt(v),true)))
const originalExtra=Bun.spawn([`${directory}/target/release/setaworld-libm-oracle`],{stdin:new Uint8Array(extra.buffer),stdout:'pipe',stderr:'inherit'})
const omitted=await new Response(originalExtra.stdout).arrayBuffer()
if(await originalExtra.exited||omitted.byteLength!==unsupported.length*32)throw Error('Original unsupported-range fixture failed')
await write('tests/tooling/f64-math-large.words',omitted)
const hash=async path=>createHash('sha256').update(new Uint8Array(await Bun.file(path).arrayBuffer())).digest('hex')
const sourceNames=['src/math/hypot.rs','src/math/atan.rs','src/math/atan2.rs','src/math/exp.rs','src/math/scalbn.rs','src/math/generic/scalbn.rs','src/math/sin.rs','src/math/cos.rs','src/math/k_sin.rs','src/math/k_cos.rs','src/math/rem_pio2.rs','src/math/rem_pio2_large.rs','LICENSE.txt']
await write('tests/tooling/f64-math-goldens.json',JSON.stringify({version:1,crate:'libm0.2.16',generator:'bun scripts/f64-math-goldens.js',records:rows.length,recordWords:4,functions:['hypot','atan','atan2','exp','scalbn','sin','cos'],trigSupported:'Finite abs(x) high word <0x413921fb; nonfinite result bits tested separately. Large finite Payne-Hanek reduction is OPEN.',unsupportedRecords:unsupported.length,comparison:'All64resultbits, including signedzeros/subnormals/infinities/NaNpayloads; no numeric tolerance',originalSources:Object.fromEntries(await Promise.all(sourceNames.map(async p=>[p,await hash(`${crate}/${p}`)]))),sources:{'scripts/f64-math-goldens.js':await hash('scripts/f64-math-goldens.js')},fixtures:{'tests/tooling/f64-math-goldens.words':await hash('tests/tooling/f64-math-goldens.words'),'tests/tooling/f64-math-large.words':await hash('tests/tooling/f64-math-large.words')}},null,'\t')+'\n')
console.log(`Recorded ${rows.length} unchanged libm strict-bit math results`)
