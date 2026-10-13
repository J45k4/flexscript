// Browser device adapter for independently validating and executing generated
// WGSL. The language frontend and both shader emitters live in Flexscript.
import { readdir, readFile, mkdtemp, rm } from 'node:fs/promises';
import { resolve, join } from 'node:path';

async function verify(shaders) {
  const check = (ok, message) => { if (!ok) throw new Error(message); };
  check(navigator.gpu, 'WebGPU unavailable');
  const adapter = await navigator.gpu.requestAdapter();
  check(adapter, 'WebGPU adapter unavailable');
  const device = await adapter.requestDevice();
  const errors = [];
  device.addEventListener('uncapturederror', event => errors.push(event.error.message));
  device.pushErrorScope('validation');
  const modules = {};
  for (const [name, code] of Object.entries(shaders)) {
    const module = device.createShaderModule({ label: name, code });
    const info = await module.getCompilationInfo();
    const failures = info.messages.filter(message => message.type === 'error');
    check(!failures.length, `${name}: ${failures.map(m => `${m.lineNum}:${m.linePos}: ${m.message}`).join('\n')}`);
    modules[name] = module;
  }
  for (const textured of [false, true]) {
    const prefix = textured ? 'textured' : 'triangle';
    const pipeline = await device.createRenderPipelineAsync({
      layout: 'auto',
      vertex: { module: modules[`${prefix}-vertex`], entryPoint: 'main' },
      fragment: { module: modules[`${prefix}-fragment`], entryPoint: 'main', targets: [{ format: 'rgba8unorm' }] },
      primitive: { topology: 'triangle-list' },
    });
    const texture = device.createTexture({ size: [64, 64], format: 'rgba8unorm', usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC });
    const readback = device.createBuffer({ size: 64 * 256, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
    let group, paint, uniform;
    if (textured) {
      paint = device.createTexture({ size: [1, 1], format: 'rgba8unorm', usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST });
      device.queue.writeTexture({ texture: paint }, new Uint8Array([192, 128, 64, 255]), { bytesPerRow: 4 }, [1, 1]);
      uniform = device.createBuffer({ size: 16, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
      device.queue.writeBuffer(uniform, 0, new Float32Array([0.5, 1, 0.5, 1]));
      group = device.createBindGroup({ layout: pipeline.getBindGroupLayout(0), entries: [
        { binding: 0, resource: paint.createView() },
        { binding: 1, resource: device.createSampler() },
        { binding: 2, resource: { buffer: uniform } },
      ] });
    }
    const encoder = device.createCommandEncoder();
    const pass = encoder.beginRenderPass({ colorAttachments: [{ view: texture.createView(), clearValue: [0, 0, 0, 0], loadOp: 'clear', storeOp: 'store' }] });
    pass.setPipeline(pipeline);
    if (group) pass.setBindGroup(0, group);
    pass.draw(3);
    pass.end();
    encoder.copyTextureToBuffer({ texture }, { buffer: readback, bytesPerRow: 256 }, [64, 64]);
    device.queue.submit([encoder.finish()]);
    await readback.mapAsync(GPUMapMode.READ);
    const bytes = new Uint8Array(readback.getMappedRange());
    const expected = textured ? [96, 128, 32, 255] : [64, 128, 191, 255];
    for (let i = 0; i < bytes.length; i++) check(Math.abs(bytes[i] - expected[i % 4]) <= 1, `${prefix}: pixel byte ${i} = ${bytes[i]}, expected ${expected[i % 4]}`);
    readback.unmap();readback.destroy();texture.destroy();paint?.destroy();uniform?.destroy();
  }
  const count = 129;
  const values = Float32Array.from({ length: count }, (_, i) => i);
  const input = device.createBuffer({ size: values.byteLength, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
  const output = device.createBuffer({ size: values.byteLength, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC });
  const readback = device.createBuffer({ size: values.byteLength, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
  device.queue.writeBuffer(input, 0, values);
  const pipeline = await device.createComputePipelineAsync({ layout: 'auto', compute: { module: modules['vector-compute'], entryPoint: 'main' } });
  const group = device.createBindGroup({ layout: pipeline.getBindGroupLayout(0), entries: [
    { binding: 0, resource: { buffer: input } }, { binding: 1, resource: { buffer: output } },
  ] });
  const encoder = device.createCommandEncoder();
  const pass = encoder.beginComputePass();pass.setPipeline(pipeline);pass.setBindGroup(0, group);pass.dispatchWorkgroups(3);pass.end();
  encoder.copyBufferToBuffer(output, 0, readback, 0, values.byteLength);
  device.queue.submit([encoder.finish()]);await readback.mapAsync(GPUMapMode.READ);
  const actual = new Float32Array(readback.getMappedRange());
  for (let i = 0; i < count; i++) check(actual[i] === i * 3 + 7, `compute ${i}: ${actual[i]}`);
  readback.unmap();readback.destroy();input.destroy();output.destroy();
  // Struct layout oracle: bytes at the offsets in the generated layout comment.
  const recordBytes = 128, records = new ArrayBuffer(count * recordBytes);
  for (let i = 0; i < count; i++) {
    const f = new Float32Array(records, i * recordBytes, 32);
    f.set([i], 0);f.set([i, 1, 2, 1, 5, 6], 4);f.set([2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1], 12);
    new Uint32Array(records, i * recordBytes + 112, 1)[0] = i;
  }
  const tint = device.createBuffer({ size: 32, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
  device.queue.writeBuffer(tint, 0, new Float32Array([1, 2, 3, 4, 0, 0, 0, 0]));
  const particles = device.createBuffer({ size: records.byteLength, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
  const results = device.createBuffer({ size: records.byteLength, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC });
  const structReadback = device.createBuffer({ size: records.byteLength, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
  device.queue.writeBuffer(particles, 0, records);
  const structPipeline = await device.createComputePipelineAsync({ layout: 'auto', compute: { module: modules['structs-compute'], entryPoint: 'main' } });
  const structGroup = device.createBindGroup({ layout: structPipeline.getBindGroupLayout(0), entries: [
    { binding: 0, resource: { buffer: tint } }, { binding: 1, resource: { buffer: particles } }, { binding: 2, resource: { buffer: results } },
  ] });
  const structEncoder = device.createCommandEncoder();
  const structPass = structEncoder.beginComputePass();structPass.setPipeline(structPipeline);structPass.setBindGroup(0, structGroup);structPass.dispatchWorkgroups(3);structPass.end();
  structEncoder.copyBufferToBuffer(results, 0, structReadback, 0, records.byteLength);
  device.queue.submit([structEncoder.finish()]);await structReadback.mapAsync(GPUMapMode.READ);
  const mapped = structReadback.getMappedRange();
  for (let i = 0; i < count; i++) {
    const f = new Float32Array(mapped, i * recordBytes, 32), id = new Uint32Array(mapped, i * recordBytes + 112, 1)[0];
    const expected = [[0, i * 2 + 5], [1, 6], [2, 0], [4, i + 4], [5, 6], [6, 10], [7, i ? 2 : 1], [8, 5], [9, 6], [12, 2], [27, 1]];
    for (const [index, value] of expected) check(f[index] === value, `struct ${i} float ${index}: ${f[index]}, expected ${value}`);
    check(id === i + 1, `struct ${i} id: ${id}`);
  }
  structReadback.unmap();structReadback.destroy();tint.destroy();particles.destroy();results.destroy();
  const validation = await device.popErrorScope();
  check(!validation, validation?.message);check(!errors.length, errors.join('\n'));
  const info = adapter.info;
  device.destroy();
  return { modules: Object.keys(modules).length, renderedPixels: 8192, computeResults: count, structRecords: count, adapter: { vendor: info?.vendor, architecture: info?.architecture, description: info?.description } };
}

const option = (name, fallback) => {
  const i = Bun.argv.indexOf(name);
  if (i < 0) return fallback;
  if (!Bun.argv[i + 1]) throw new Error(`${name} needs a value`);
  return Bun.argv[i + 1];
};
const directory = resolve(option('--dir', 'build/shaders'));
const browser = option('--browser', 'chromium');
const shaders = {};
for (const name of (await readdir(directory)).filter(n => n.endsWith('.wgsl')).sort()) shaders[name.slice(0, -5)] = await readFile(join(directory, name), 'utf8');
if (!Object.keys(shaders).length) throw new Error(`No WGSL modules in ${directory}`);
const token = crypto.randomUUID();
const profile = await mkdtemp(join(directory, 'webgpu-'));
let resolveResult;
const result = new Promise(resolve => { resolveResult = resolve; });
const page = `<!doctype html><script>(${verify.toString()})(${JSON.stringify(shaders).replaceAll('<', '\\u003c')}).then(result=>fetch('/${token}',{method:'POST',body:JSON.stringify({ok:true,...result})}),error=>fetch('/${token}',{method:'POST',body:JSON.stringify({ok:false,error:String(error.stack||error)})}));</script>`;
let server;
let child;
let timer;
try {
  server = Bun.serve({ hostname: '127.0.0.1', port: 0, async fetch(request) {
    const path = new URL(request.url).pathname;
    if (path === `/${token}` && request.method === 'POST') { resolveResult(await request.json());return new Response('ok'); }
    if (path === '/' && request.method === 'GET') return new Response(page, { headers: { 'Content-Type': 'text/html' } });
    return new Response('Not found', { status: 404 });
  } });
  child = Bun.spawn([browser, '--headless', '--no-sandbox', '--disable-dev-shm-usage', '--enable-unsafe-webgpu', '--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--no-first-run', '--no-default-browser-check', `--user-data-dir=${profile}`, `http://127.0.0.1:${server.port}/`], { stdout: 'ignore', stderr: 'pipe' });
  const stderr = new Response(child.stderr).text();
  const timeout = new Promise(resolve => { timer = setTimeout(() => resolve({ ok: false, error: 'WebGPU test timed out after 30 seconds' }), 30000); });
  const answer = await Promise.race([result, timeout, child.exited.then(code => ({ ok: false, error: `Chromium exited ${code}` }))]);
  child.kill();await child.exited;
  const log = await stderr;
  console.log(JSON.stringify(answer, null, 2));
  if (!answer.ok) { console.error(log.slice(-8192));process.exitCode = 1; }
} finally {
  clearTimeout(timer);child?.kill();server?.stop(true);await rm(profile, { recursive: true, force: true });
}
