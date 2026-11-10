// Experimental host-side deformable chain overlay for Flexscript physics.
// Consecutive particles have stretch springs; second neighbours have bending
// springs. Rigid contact remains the existing solver's job; no GPU path yet.

// chain: world, count, link count, particle IDs, links, saved forces.
// link: body A, body B, rest distance, spring constant, damping.
fn sc_chain(world, ids, count, stretch, bend, damping) {
    h_assert(count >= 3 && count <= 128, "chain needs 3..128 particles");
    h_assert(ph_positive(stretch) && ph_finite(bend) && !ph_lt(bend, 0) && ph_finite(damping) && !ph_lt(damping, 0), "invalid spring parameters");
    let chain = alloc(80); let copied = alloc(count * 8); let links = alloc((count * 2 - 3) * 40); let forces = alloc(count * 24);
    store64(chain, world); store64(chain + 8, count); store64(chain + 16, count * 2 - 3); store64(chain + 24, copied); store64(chain + 32, links); store64(chain + 40, forces); store64(chain + 48, stretch); store64(chain + 56, bend); store64(chain + 64, damping); store64(chain + 72, chain);
    let i = 0;
    while i < count {
        let id = load64(ids + i * 8); h_assert(id >= 0 && id < load64(world + 8), "invalid chain particle");
        let j = 0; while j < i { h_assert(load64(copied + j * 8) != id, "duplicate chain particle"); j = j + 1; }
        let inv = load64(ph_body(world, id) + 112); let dt = load64(world + 120);
        h_assert(!ph_lt(0x3e800000, ph_mul(ph_mul(ph_add(stretch, bend), ph_mul(dt, dt)), inv)) && !ph_lt(0x3f000000, ph_mul(ph_mul(damping, dt), inv)), "chain parameters exceed explicit integration bounds");
        store64(copied + i * 8, id); i = i + 1;
    }
    let index = 0; let span = 1;
    while span <= 2 {
        i = 0; while i + span < count {
            let a = load64(copied + i * 8); let b = load64(copied + (i + span) * 8); let p = ph_body(world, a) + 8; let q = ph_body(world, b) + 8;
            let x = ph_sub(load64(q), load64(p)); let y = ph_sub(load64(q + 8), load64(p + 8)); let z = ph_sub(load64(q + 16), load64(p + 16));
            let length = ph_sqrt(ph_dot(x, y, z, x, y, z)); h_assert(ph_positive(length), "chain has coincident or invalid particles");
            let link = links + index * 40; store64(link, a); store64(link + 8, b); store64(link + 16, length);
            let k = stretch; if span == 2 { k = bend; } store64(link + 24, k); store64(link + 32, damping); index = index + 1; i = i + 1;
        } span = span + 1;
    }
    h_assert(sc_check(chain), "chain parameters exceed group stability bounds");
    return chain;
}
fn sc_check(chain) {
    let world = load64(chain); let ids = load64(chain + 24); let count = load64(chain + 8); let dt = load64(world + 120);
    let i = 0; while i < count {
        let id = load64(ids + i * 8); if id < 0 || id >= load64(world + 8) { return 0; }
        let inv = load64(ph_body(world,id) + 112);
        if !ph_finite(inv) || ph_lt(inv,0) || !ph_positive(dt) ||
           ph_lt(0x3d800000, ph_mul(ph_mul(ph_add(load64(chain+48),load64(chain+56)), ph_mul(dt,dt)), inv)) ||
           ph_lt(0x3e000000, ph_mul(ph_mul(load64(chain+64),dt),inv)) { return 0; }
        i = i + 1;
    } return 1;
}
fn sc_forces(chain) {
    let world = load64(chain); let links = load64(chain + 32);
    let valid = 1; let i = 0;
    while i < load64(chain + 16) && valid {
        let link = links + i * 40; let a = ph_body(world, load64(link)); let b = ph_body(world, load64(link + 8));
        let x = ph_sub(load64(b + 8), load64(a + 8)); let y = ph_sub(load64(b + 16), load64(a + 16)); let z = ph_sub(load64(b + 24), load64(a + 24));
        let d2 = ph_dot(x, y, z, x, y, z);
        if !ph_finite(d2) || ph_lt(d2, 0x2b8cbccc) { valid = 0; }
        else {
            let length = ph_sqrt(d2); let inv = ph_rcp(length); let nx = ph_mul(x, inv); let ny = ph_mul(y, inv); let nz = ph_mul(z, inv);
            let vx = ph_sub(load64(b + 64), load64(a + 64)); let vy = ph_sub(load64(b + 72), load64(a + 72)); let vz = ph_sub(load64(b + 80), load64(a + 80));
            let magnitude = ph_add(ph_mul(load64(link + 24), ph_sub(length, load64(link + 16))), ph_mul(load64(link + 32), ph_dot(vx, vy, vz, nx, ny, nz)));
            if !ph_finite(magnitude) { valid = 0; } else {
                let axis = 0; while axis < 3 { let n = nx; if axis == 1 { n = ny; } if axis == 2 { n = nz; } let force = ph_mul(magnitude, n);
                    store64(a + 144 + axis * 8, ph_add(load64(a + 144 + axis * 8), force));
                    store64(b + 144 + axis * 8, ph_sub(load64(b + 144 + axis * 8), force)); axis = axis + 1;
                }
            }
        } i = i + 1;
    }
    return valid;
}
// A group step sums every chain's force before advancing the shared world once.
// Chains may not share particles; use a single chain for connected material.
fn sc_step_group(chains, n) {
    if n < 1 || n > 128 { return 0; }
    let first = load64(chains); if !first { return 0; } let world = load64(first); if load64(world + 192) { return 0; }
    let i = 0; while i < n {
        let c = load64(chains + i * 8); if !c || load64(c) != world || !sc_check(c) { return 0; }
        let j = 0; while j < i {
            let other = load64(chains + j * 8); let a = 0;
            while a < load64(c + 8) { let b = 0; while b < load64(other + 8) {
                if load64(load64(c + 24) + a * 8) == load64(load64(other + 24) + b * 8) { return 0; } b = b + 1;
            } a = a + 1; } j = j + 1;
        } i = i + 1;
    }
    i = 0; while i < n { let c = load64(chains + i * 8); let count = load64(c + 8); let ids = load64(c + 24); let saved = load64(c + 40); let a = 0;
        while a < count { let body = ph_body(world,load64(ids+a*8)); let k = 0; while k < 3 { store64(saved+a*24+k*8,load64(body+144+k*8)); k=k+1; } a=a+1; } i=i+1;
    }
    let valid = 1; i = 0; while i < n && valid { valid = sc_forces(load64(chains + i * 8)); i = i + 1; }
    let result = 0; if valid { result = ph_step(world); } else { store64(world + 192, 2); }
    i = 0; while i < n { let c = load64(chains+i*8); let a = 0; while a < load64(c+8) {
        let body = ph_body(world,load64(load64(c+24)+a*8)); let k = 0; while k < 3 { store64(body+144+k*8,load64(load64(c+40)+a*24+k*8)); k=k+1; } a=a+1;
    } i=i+1; } return result;
}
fn sc_step(chain) { return sc_step_group(chain + 72,1); }
fn sc_close(chain) {
    let count = load64(chain + 8); syscall(11,load64(chain+24),count*8,0,0,0,0);
    syscall(11,load64(chain+32),(count*2-3)*40,0,0,0,0); syscall(11,load64(chain+40),count*24,0,0,0,0);
    return syscall(11,chain,80,0,0,0,0);
}
