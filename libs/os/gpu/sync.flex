// Portable generation barrier. The host must keep the entire grid resident.
// One arrival per block; every thread publishes its writes before rendezvous.
// Scratch is zeroed by the host before each launch, never inside a racing grid.
fn os_sync(work) {
    gpu_device_release_fence();gpu_barrier();
    if !gpu_thread_x() {
        let generation=gpu_device_load_relaxed64(work+968);
        let arrival=gpu_device_add64(work+960,1);
        if arrival+1==gpu_grid_dim_x() {gpu_device_store_release64(work+960,0);gpu_device_store_release64(work+968,generation+1);}
        else {while gpu_device_load_relaxed64(work+968)==generation {}}
    }
    gpu_barrier();gpu_device_acquire_fence();return 0;
}
