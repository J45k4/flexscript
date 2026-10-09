// Small in-memory file adapter, usable in browsers and Linux JS hosts alike.
// It implements the file operations needed by the Flexscript compiler.
// Paths address this map only; they never open files on the host filesystem.
const encoder = new TextEncoder()
const decoder = new TextDecoder()
const pathOf = path => {
	const parts = []
	for (const part of path.split('/')) {
		if (part === '..') parts.pop()
		else if (part && part !== '.') parts.push(part)
	}
	return '/' + parts.join('/')
}

export function createMemoryHost(initial = {}, io = {}) {
	const files = new Map()
	const descriptors = new Map()
	let inode = 1n
	let nextFd = 3n
	const node = bytes => ({ data: typeof bytes === 'string' ? encoder.encode(bytes) : new Uint8Array(bytes), inode: inode++, mode: 0o100644n })
	for (const [path, bytes] of Object.entries(initial)) files.set(pathOf(path), node(bytes))
	const host = {
		...io,
		readFile(path) { return files.get(pathOf(path))?.data.slice() },
		syscall(number, a, b, c, d, e, f) {
			const span = (pointer, size) => {
				if (pointer < 0n || size < 0n || pointer + size > BigInt(this.memory.buffer.byteLength)) {
					throw new RangeError('Flexscript file adapter memory access out of bounds')
				}
				return new Uint8Array(this.memory.buffer, Number(pointer), Number(size))
			}
			const path = pointer => {
				const bytes = span(pointer, BigInt(this.memory.buffer.byteLength) - pointer)
				const end = bytes.indexOf(0)
				if (end < 0) throw new RangeError('Unterminated Flexscript file path')
				return pathOf(decoder.decode(bytes.subarray(0, end)))
			}
			if (number === 2n) {
				const name = path(a)
				const access = b & 3n
				const allowed = 3n | 64n | 128n | 512n | 2048n | 131072n | 524288n
				if (access === 3n || (b & ~allowed)) return -22n
				let file = files.get(name)
				if (file && (b & 64n) && (b & 128n)) return -17n
				if (!file) {
					if (!(b & 64n)) return -2n
					file = node(new Uint8Array())
					file.mode = 0o100000n | (c & 0o777n)
					files.set(name, file)
				}
				if (b & 512n) {
					if (access === 0n) return -22n
					file.data = new Uint8Array()
				}
				const fd = nextFd++
				descriptors.set(fd, { file, position: 0, access })
				return fd
			}
			if (number === 0n || number === 1n) {
				if (number === 1n && (a === 1n || a === 2n)) return this.defaultSyscall(number, a, b, c, d, e, f)
				const descriptor = descriptors.get(a)
				if (!descriptor || (number === 0n ? descriptor.access === 1n : descriptor.access === 0n)) return -9n
				const bytes = span(b, c)
				const { file, position } = descriptor
				if (number === 0n) {
					const count = Math.min(bytes.length, Math.max(0, file.data.length - position))
					bytes.set(file.data.subarray(position, position + count))
					descriptor.position += count
					return BigInt(count)
				}
				if (position + bytes.length > 67108864) return -27n
				if (position + bytes.length > file.data.length) {
					const grown = new Uint8Array(position + bytes.length)
					grown.set(file.data)
					file.data = grown
				}
				file.data.set(bytes, position)
				descriptor.position += bytes.length
				return c
			}
			if (number === 3n) return descriptors.delete(a) ? 0n : -9n
			if (number === 5n || number === 77n || number === 91n) {
				const descriptor = descriptors.get(a)
				if (!descriptor) return -9n
				const { file } = descriptor
				if (number === 5n) {
					const bytes = span(b, 144n)
					bytes.fill(0)
					const stat = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
					stat.setBigUint64(0, 1n, true)
					stat.setBigUint64(8, file.inode, true)
					stat.setBigUint64(24, file.mode, true)
					stat.setBigUint64(48, BigInt(file.data.length), true)
				} else if (number === 77n) {
					if (descriptor.access === 0n) return -9n
					if (b < 0n || b > 67108864n) return -27n
					const resized = new Uint8Array(Number(b))
					resized.set(file.data.subarray(0, resized.length))
					file.data = resized
				} else file.mode = 0o100000n | (b & 0o777n)
				return 0n
			}
			return this.defaultSyscall(number, a, b, c, d, e, f)
		},
	}
	return host
}
