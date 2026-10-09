// Browser/Bun platform bridge. Flexscript emits the module; the host supplies I/O.
// All language values, including pointers, cross the boundary as BigInt words.
const encoder = new TextEncoder()

class FlexExit extends Error {
	constructor(code) {
		super('Flexscript exit')
		this.code = code
	}
}

export async function instantiateFlexscript(bytes, host = {}) {
	const api = {}
	const span = (pointer, size) => {
		if (pointer < 0n || size < 0n || pointer + size > BigInt(api.memory.buffer.byteLength)) {
			throw new RangeError('Flexscript host memory access out of bounds')
		}
		return new Uint8Array(api.memory.buffer, Number(pointer), Number(size))
	}
	const syscall = (number, a, b, c) => {
		if (number === 1n && (a === 1n || a === 2n)) {
			const data = span(b, c).slice()
			const write = a === 1n ? host.stdout : host.stderr
			if (!write) return -9n
			write(data)
			return c
		}
		if (number === 60n || number === 231n) throw new FlexExit(a)
		return -38n // ENOSYS: the browser has no Linux syscall table.
	}
	const names = ['syscall', 'ffi_open', 'ffi_symbol', 'ffi_call', 'ffi_call_i32', 'ffi_call_u32']
	const flex = Object.fromEntries(names.map(name => [name, (...args) => {
		const handler = host[name] ?? (name === 'syscall' ? syscall : null)
		if (!handler) throw new Error(`Flexscript host capability unavailable: flex.${name}`)
		return BigInt(handler.apply(api, args))
	}]))
	const loaded = await WebAssembly.instantiate(bytes, { flex })
	api.instance = loaded instanceof WebAssembly.Instance ? loaded : loaded.instance
	api.exports = api.instance.exports
	api.memory = api.exports.memory
	api.defaultSyscall = syscall
	api.alloc = size => {
		const address = api.exports.__flex_alloc(BigInt(size))
		if (address < 0n) throw new RangeError(`Flexscript allocation failed: ${address}`)
		return address
	}
	api.string = text => {
		const data = encoder.encode(text)
		const address = api.alloc(data.length + 1)
		span(address, BigInt(data.length + 1)).set([...data, 0])
		return address
	}
	api.run = (argv = ['app.wasm']) => {
		try {
			if (api.exports.main.length === 0) return api.exports.main()
			const pointers = argv.map(api.string)
			const address = api.alloc((pointers.length + 1) * 8)
			const view = new DataView(api.memory.buffer)
			pointers.forEach((pointer, i) => view.setBigUint64(Number(address) + i * 8, pointer, true))
			view.setBigUint64(Number(address) + pointers.length * 8, 0n, true)
			return api.exports.main(BigInt(pointers.length), address)
		} catch (error) {
			if (error instanceof FlexExit) return error.code
			throw error
		}
	}
	return api
}
