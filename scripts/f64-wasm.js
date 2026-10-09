// Mechanical file device for test-f64.flex, with binary fixture bytes.
import {instantiateFlexscript} from '../platform/wasm-host.js'
import {createMemoryHost} from '../platform/wasm-files.js'
const [modulePath,fixturePath]=Bun.argv.slice(2)
const bytes=await Bun.file(modulePath).arrayBuffer(),module=new WebAssembly.Module(bytes)
const host=createMemoryHost({[fixturePath]:new Uint8Array(await Bun.file(fixturePath).arrayBuffer())})
const app=await instantiateFlexscript(module,host)
console.log(JSON.stringify({valid:WebAssembly.validate(bytes),result:app.run().toString()}))
