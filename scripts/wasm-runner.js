// Mechanical WebAssembly engine adapter for the Flexscript test harness.
// Fixtures, comparisons and assertions belong to scripts/test-wasm.flex.
import { instantiateFlexscript } from '../platform/wasm-host.js'
import { createMemoryHost } from '../platform/wasm-files.js'

const request = await Bun.file(Bun.argv[2]).json()
const stdout = []
const stderr = []
const decode = chunks => {
	const decoder = new TextDecoder()
	return chunks.map(bytes => decoder.decode(bytes, { stream: true })).join('') + decoder.decode()
}
const report = {}
try {
	const bytes = await Bun.file(request.module).arrayBuffer()
	report.valid = WebAssembly.validate(bytes)
	const module = new WebAssembly.Module(bytes)
	report.imports = WebAssembly.Module.imports(module).map(item => `${item.module}.${item.name}`)
	const host = createMemoryHost(request.files, { stdout: bytes => stdout.push(bytes), stderr: bytes => stderr.push(bytes) })
	if (request.ffi) Object.assign(host, {
		ffi_open: () => 101n,
		ffi_symbol: () => 102n,
		ffi_call: (pointer, a, b, c, d, e, f) => a + b * 10n + c * 100n + d * 1000n + e * 10000n + f * 100000n,
		ffi_call_i32: () => 0xffffffffn,
		ffi_call_u32: () => -1n,
	})
	const app = await instantiateFlexscript(module, host)
	if (request.probe === 'alloc') {
		report.values = [0n, -1n, 1073741825n, 8n, 70000n].map(size => app.exports.__flex_alloc(size).toString())
		report.pages = app.memory.buffer.byteLength / 65536
	} else {
		report.result = app.run(request.argv).toString()
	}
	if (request.output) {
		const artifact = host.readFile(request.output)
		if (!artifact) throw new Error(`Missing virtual output: ${request.output}`)
		if (request.save) await Bun.write(request.save, artifact)
		else report.output = new TextDecoder().decode(artifact)
	}
} catch (error) {
	report.error = String(error)
	report.trap = error instanceof WebAssembly.RuntimeError
}
report.stdout = request.binary ? '' : decode(stdout)
report.stderr = decode(stderr)
report.stdoutHex = stdout.flatMap(bytes => Array.from(bytes, byte => byte.toString(16).padStart(2, '0'))).join('')
console.log(JSON.stringify(report))
