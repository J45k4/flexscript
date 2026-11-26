// Interleaved 36-byte triangle-list vertices: float3 position, float3 normal,
// float2 UV, and an application-supplied uint. Input coordinates and UVs use
// thousandths and vertex writers return the next vertex index.
fn render_packed_vertex(buf, idx, x_mm, y_mm, z_mm, nx_m, ny_m, nz_m, u_m, v_m, packed) {
    let p = buf + idx * 36;
    render_float(p + 0, x_mm, 1000);
    render_float(p + 4, y_mm, 1000);
    render_float(p + 8, z_mm, 1000);
    render_float(p + 12, nx_m, 1000);
    render_float(p + 16, ny_m, 1000);
    render_float(p + 20, nz_m, 1000);
    render_float(p + 24, u_m, 1000);
    render_float(p + 28, v_m, 1000);
    gui__put32(p + 32, packed);
    return idx + 1;
}

// Append an axis-aligned box in millimetres centered at (cx, cy, cz) with size (sx, sy, sz)
fn render_packed_box(buf, idx, cx, cy, cz, sx, sy, sz, col) {
    let x0 = cx - sx / 2; let x1 = cx + sx / 2;
    let y0 = cy - sy / 2; let y1 = cy + sy / 2;
    let z0 = cz - sz / 2; let z1 = cz + sz / 2;

    // +Y top
    idx = render_packed_vertex(buf, idx, x0, y1, z0, 0, 1000, 0, 0, 0, col);
    idx = render_packed_vertex(buf, idx, x0, y1, z1, 0, 1000, 0, 0, sz, col);
    idx = render_packed_vertex(buf, idx, x1, y1, z1, 0, 1000, 0, sx, sz, col);
    idx = render_packed_vertex(buf, idx, x0, y1, z0, 0, 1000, 0, 0, 0, col);
    idx = render_packed_vertex(buf, idx, x1, y1, z1, 0, 1000, 0, sx, sz, col);
    idx = render_packed_vertex(buf, idx, x1, y1, z0, 0, 1000, 0, sx, 0, col);

    // -Y bottom
    idx = render_packed_vertex(buf, idx, x0, y0, z0, 0, -1000, 0, 0, 0, col);
    idx = render_packed_vertex(buf, idx, x1, y0, z1, 0, -1000, 0, sx, sz, col);
    idx = render_packed_vertex(buf, idx, x0, y0, z1, 0, -1000, 0, 0, sz, col);
    idx = render_packed_vertex(buf, idx, x0, y0, z0, 0, -1000, 0, 0, 0, col);
    idx = render_packed_vertex(buf, idx, x1, y0, z0, 0, -1000, 0, sx, 0, col);
    idx = render_packed_vertex(buf, idx, x1, y0, z1, 0, -1000, 0, sx, sz, col);

    // -Z front
    idx = render_packed_vertex(buf, idx, x0, y0, z0, 0, 0, -1000, 0, 0, col);
    idx = render_packed_vertex(buf, idx, x0, y1, z0, 0, 0, -1000, 0, sy, col);
    idx = render_packed_vertex(buf, idx, x1, y1, z0, 0, 0, -1000, sx, sy, col);
    idx = render_packed_vertex(buf, idx, x0, y0, z0, 0, 0, -1000, 0, 0, col);
    idx = render_packed_vertex(buf, idx, x1, y1, z0, 0, 0, -1000, sx, sy, col);
    idx = render_packed_vertex(buf, idx, x1, y0, z0, 0, 0, -1000, sx, 0, col);

    // +Z back
    idx = render_packed_vertex(buf, idx, x1, y0, z1, 0, 0, 1000, 0, 0, col);
    idx = render_packed_vertex(buf, idx, x1, y1, z1, 0, 0, 1000, 0, sy, col);
    idx = render_packed_vertex(buf, idx, x0, y1, z1, 0, 0, 1000, sx, sy, col);
    idx = render_packed_vertex(buf, idx, x1, y0, z1, 0, 0, 1000, 0, 0, col);
    idx = render_packed_vertex(buf, idx, x0, y1, z1, 0, 0, 1000, sx, sy, col);
    idx = render_packed_vertex(buf, idx, x0, y0, z1, 0, 0, 1000, sx, 0, col);

    // +X right
    idx = render_packed_vertex(buf, idx, x1, y0, z0, 1000, 0, 0, 0, 0, col);
    idx = render_packed_vertex(buf, idx, x1, y1, z0, 1000, 0, 0, 0, sy, col);
    idx = render_packed_vertex(buf, idx, x1, y1, z1, 1000, 0, 0, sz, sy, col);
    idx = render_packed_vertex(buf, idx, x1, y0, z0, 1000, 0, 0, 0, 0, col);
    idx = render_packed_vertex(buf, idx, x1, y1, z1, 1000, 0, 0, sz, sy, col);
    idx = render_packed_vertex(buf, idx, x1, y0, z1, 1000, 0, 0, sz, 0, col);

    // -X left
    idx = render_packed_vertex(buf, idx, x0, y0, z1, -1000, 0, 0, 0, 0, col);
    idx = render_packed_vertex(buf, idx, x0, y1, z1, -1000, 0, 0, 0, sy, col);
    idx = render_packed_vertex(buf, idx, x0, y1, z0, -1000, 0, 0, sz, sy, col);
    idx = render_packed_vertex(buf, idx, x0, y0, z1, -1000, 0, 0, 0, 0, col);
    idx = render_packed_vertex(buf, idx, x0, y1, z0, -1000, 0, 0, sz, sy, col);
    idx = render_packed_vertex(buf, idx, x0, y0, z0, -1000, 0, 0, sz, 0, col);

    return idx;
}

fn render_packed_mesh(device) {
    // 4 attributes: pos(3f), normal(3f), uv(2f), packed uint(1u integer)
    let attrs = gui__zero(alloc(4 * 48), 4 * 48);
    // loc 0: vec3 pos @ 0
    store64(attrs + 0, 0); store64(attrs + 8, 3); store64(attrs + 16, 0x1406); store64(attrs + 32, 0);
    // loc 1: vec3 normal @ 12
    store64(attrs + 48, 1); store64(attrs + 56, 3); store64(attrs + 64, 0x1406); store64(attrs + 80, 12);
    // loc 2: vec2 uv @ 24
    store64(attrs + 96, 2); store64(attrs + 104, 2); store64(attrs + 112, 0x1406); store64(attrs + 128, 24);
    // loc 3: uint packed uint @ 32 (integer input = 1)
    store64(attrs + 144, 3); store64(attrs + 152, 1); store64(attrs + 160, 0x1405); store64(attrs + 176, 32); store64(attrs + 184, 1);
    let mesh = render_mesh(device, 36, attrs, 4);
    syscall(11, attrs, 4 * 48, 0, 0, 0, 0);
    return mesh;
}
