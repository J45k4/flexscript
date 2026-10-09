// Optional offline Rust oracle. Ordinary test-f64 needs no Rust.
import {createHash} from 'node:crypto'
import {fileURLToPath} from 'node:url'
const root=fileURLToPath(new URL('../',import.meta.url)),prefix=`/tmp/flexscript-f64-oracle-${process.pid}`
const rust=fileURLToPath(new URL('../tests/tooling/f64-oracle.rs',import.meta.url))
const target=fileURLToPath(new URL('../tests/tooling/f64-goldens.words',import.meta.url))
const proofTarget=fileURLToPath(new URL('../tests/tooling/f64-goldens.json',import.meta.url))
let child=Bun.spawn(['rustc','--edition=2021','-O',rust,'-o',prefix],{stdout:'inherit',stderr:'inherit'})
if(await child.exited)throw Error('Binary64 oracle compile failed')
child=Bun.spawn([prefix,`${prefix}.words`],{stdout:'inherit',stderr:'inherit'})
if(await child.exited)throw Error('Binary64 oracle failed')
const bytes=new Uint8Array(await Bun.file(`${prefix}.words`).arrayBuffer())
const hash=bytes=>createHash('sha256').update(bytes).digest('hex')
const sources={}
for(const name of ['tests/tooling/f64-oracle.rs','scripts/f64-goldens.js'])sources[name]=hash(new Uint8Array(await Bun.file(root+name).arrayBuffer()))
const proof=JSON.stringify({version:1,generator:'bun scripts/f64-goldens.js',recordWords:4,records:bytes.length/32,fields:['operation','aBitsOrI64','bBits','expectedBitsOrI64'],operations:['add','sub','mul','div','lt','eq','le','from_i64','to_i64_trunc','to_i64_nearest_ties_even','to_i64_round_ties_away','gt','ge','ne','sqrt'],reference:'Rust binary64 hardware arithmetic/comparisons and saturating casts; NaNs canonicalized to0x7ff8000000000000',randomSeed:123,randomPairs:3072,exceptionalBoundaryPairs:729,halfwayRoundingPairs:586,sources,fixtureSha256:hash(bytes)},null,'\t')+'\n'
if(process.argv.includes('--check')){
	if(hash(new Uint8Array(await Bun.file(target).arrayBuffer()))!==hash(bytes)||await Bun.file(proofTarget).text()!==proof)throw Error('Binary64 oracle fixtures changed')
}else {await Bun.write(target,bytes);await Bun.write(proofTarget,proof)}
console.log(`Recorded ${bytes.length/32} binary64 bit-pattern fixtures; SHA-256 ${hash(bytes)}`)
