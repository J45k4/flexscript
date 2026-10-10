// Linux x86-64 Vulkan 1.2 adapter, with hardware ray queries via KHR extensions.
// Structures use the official 64-bit ABI; no C shim or CUDA toolkit is needed.
import "ffi.flex";
global vk_library=0;
global vk_instance=0;
global vk_physical=0;
global vk_device=0;
global vk_queue=0;
global vk_family=0;
global vk_status=0;
global vk_error=0;
global vk_allocations=0;
global vk_accelerations=0;
global vk_objects=0;
global vk_scratch_alignment=256;
fn vk_u32(p,v) {let i=0;while i<4 {store8(p+i,v>>(i*8));i=i+1;}return 0;}
fn vk_get_u32(p) {return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn vk_struct(size,kind) {let p=alloc(size);vk_u32(p,kind);return p;}
fn vk_symbol(name) {
    if !vk_library {vk_library=ffi_open("libvulkan.so.1");}
    if !vk_library {vk_status=-10001;vk_error="Vulkan loader unavailable";return 0;}
    let p=ffi_symbol(vk_library,name);if p {return p;}
    let get=ffi_symbol(vk_library,"vkGetDeviceProcAddr");
    if vk_device && get {p=ffi_call(get,vk_device,name,0,0,0,0);if p {return p;}}
    get=ffi_symbol(vk_library,"vkGetInstanceProcAddr");
    if vk_instance && get {p=ffi_call(get,vk_instance,name,0,0,0,0);if p {return p;}}
    vk_status=-10002;vk_error=name;return 0;
}
fn vk_call(name,a,b,c,d,e,f) {
    let p=vk_symbol(name);if !p {return vk_status;}
    vk_status=ffi_call_i32(p,a,b,c,d,e,f);if vk_status {vk_error=name;}return vk_status;
}
fn vk_void(name,a,b,c,d,e,f) {
    let p=vk_symbol(name);if !p {return vk_status;}
    ffi_call(p,a,b,c,d,e,f);vk_status=0;return 0;
}
fn vk_address(name,a,b) {let p=vk_symbol(name);if !p {return 0;}return ffi_call(p,a,b,0,0,0,0);}
fn vk_keep(kind,handle) {
    let node=alloc(24);store64(node,vk_objects);store64(node+8,kind);store64(node+16,handle);vk_objects=node;return handle;
}
fn vk_ray_open(ordinal) {
    if vk_instance || vk_device {vk_status=-10009;vk_error="Vulkan device already open; close it before reopening";return 0;}
    vk_status=0;vk_error=0;
    let app=vk_struct(48,0);store64(app+16,"Flexscript");vk_u32(app+44,4202496);
    let info=vk_struct(64,1);store64(info+24,app);let value=alloc(8);
    if vk_call("vkCreateInstance",info,0,value,0,0,0) {return 0;}vk_instance=load64(value);
    let count=alloc(8);if vk_call("vkEnumeratePhysicalDevices",vk_instance,count,0,0,0,0) {return 0;}
    if ordinal<0 || ordinal>=vk_get_u32(count) {vk_status=-10003;vk_error="Vulkan device ordinal unavailable";return 0;}
    let devices=alloc(vk_get_u32(count)*8);
    if vk_call("vkEnumeratePhysicalDevices",vk_instance,count,devices,0,0,0) {return 0;}vk_physical=load64(devices+ordinal*8);
    let properties=vk_struct(840,1000059001);let acceleration=vk_struct(64,1000150014);store64(properties+8,acceleration);
    if vk_void("vkGetPhysicalDeviceProperties2",vk_physical,properties,0,0,0,0) {return 0;}
    vk_scratch_alignment=vk_get_u32(acceleration+56);
    let bda=vk_struct(32,1000257000);let asf=vk_struct(40,1000150013);
    let ray=vk_struct(24,1000348013);let sync=vk_struct(24,1000314007);
    store64(bda+8,asf);store64(asf+8,ray);store64(ray+8,sync);
    let features=vk_struct(240,1000059000);store64(features+8,bda);
    if vk_void("vkGetPhysicalDeviceFeatures2",vk_physical,features,0,0,0,0) {return 0;}
    if !vk_get_u32(bda+16) || !vk_get_u32(asf+16) || !vk_get_u32(ray+16) || !vk_get_u32(sync+16) {
        vk_status=-10004;vk_error="Device lacks buffer addresses, acceleration structures, ray queries or synchronization2";return 0;
    }
    // Enable only the features used here, clearing optional reported fields.
    vk_u32(bda+20,0);vk_u32(bda+24,0);let i=20;while i<40 {vk_u32(asf+i,0);i=i+4;}
    if vk_void("vkGetPhysicalDeviceQueueFamilyProperties",vk_physical,count,0,0,0,0) {return 0;}
    let families=alloc(vk_get_u32(count)*24);if vk_void("vkGetPhysicalDeviceQueueFamilyProperties",vk_physical,count,families,0,0,0) {return 0;}
    vk_family=-1;i=0;while i<vk_get_u32(count) {if vk_family<0 && (vk_get_u32(families+i*24)&2) {vk_family=i;}i=i+1;}
    if vk_family<0 {vk_status=-10005;vk_error="No compute queue";return 0;}
    let priority=alloc(4);vk_u32(priority,0x3f800000);let queue=vk_struct(40,2);
    vk_u32(queue+20,vk_family);vk_u32(queue+24,1);store64(queue+32,priority);
    let extensions=alloc(40);store64(extensions,"VK_KHR_acceleration_structure");store64(extensions+8,"VK_KHR_ray_query");
    store64(extensions+16,"VK_KHR_deferred_host_operations");store64(extensions+24,"VK_KHR_synchronization2");store64(extensions+32,"VK_KHR_push_descriptor");
    let create=vk_struct(72,3);store64(create+8,bda);vk_u32(create+20,1);store64(create+24,queue);
    vk_u32(create+48,5);store64(create+56,extensions);
    if vk_call("vkCreateDevice",vk_physical,create,0,value,0,0) {return 0;}vk_device=load64(value);
    if vk_void("vkGetDeviceQueue",vk_device,vk_family,0,value,0,0) {return 0;}vk_queue=load64(value);return vk_device;
}
fn vk_device_name() {
    let properties=alloc(1024);if vk_void("vkGetPhysicalDeviceProperties",vk_physical,properties,0,0,0,0) {return 0;}return properties+20;
}
// Buffer record: VkBuffer, VkDeviceMemory, mapped pointer, device address, bytes.
fn vk_buffer(bytes,usage,host) {
    let info=vk_struct(56,12);store64(info+24,bytes);vk_u32(info+32,usage);
    let value=alloc(8);if vk_call("vkCreateBuffer",vk_device,info,0,value,0,0) {return 0;}
    let record=alloc(48);store64(record,load64(value));store64(record+32,bytes);
    let node=alloc(16);store64(node,vk_allocations);store64(node+8,record);vk_allocations=node;
    let req=alloc(24);if vk_void("vkGetBufferMemoryRequirements",vk_device,load64(record),req,0,0,0) {return 0;}
    let memory=alloc(520);if vk_void("vkGetPhysicalDeviceMemoryProperties",vk_physical,memory,0,0,0,0) {return 0;}
    let bits=vk_get_u32(req+16);let wanted=1;if host {wanted=6;}
    let i=0;let selected=-1;while i<vk_get_u32(memory) {
        if selected<0 && (bits&(1<<i)) && (vk_get_u32(memory+4+i*8)&wanted)==wanted {selected=i;}i=i+1;
    }
    if selected<0 {vk_status=-10006;vk_error="No compatible Vulkan memory type";return 0;}
    let allocate=vk_struct(32,5);store64(allocate+16,load64(req));vk_u32(allocate+24,selected);
    if usage&0x20000 {let flags=vk_struct(24,1000060000);vk_u32(flags+16,2);store64(allocate+8,flags);}
    if vk_call("vkAllocateMemory",vk_device,allocate,0,value,0,0) {return 0;}store64(record+8,load64(value));
    if vk_call("vkBindBufferMemory",vk_device,load64(record),load64(value),0,0,0) {return 0;}
    if host {
        if vk_call("vkMapMemory",vk_device,load64(record+8),0,bytes,0,value) {return 0;}store64(record+16,load64(value));
    }
    if usage&0x20000 {let address=vk_struct(24,1000244001);store64(address+16,load64(record));store64(record+24,vk_address("vkGetBufferDeviceAddress",vk_device,address));}
    return record;
}
fn vk_commands() {
    let pool=vk_struct(24,39);vk_u32(pool+16,2);vk_u32(pool+20,vk_family);let value=alloc(8);
    if vk_call("vkCreateCommandPool",vk_device,pool,0,value,0,0) {return 0;}
    let handle=vk_keep(1,load64(value));let allocate=vk_struct(32,40);store64(allocate+16,handle);vk_u32(allocate+28,1);
    if vk_call("vkAllocateCommandBuffers",vk_device,allocate,value,0,0,0) {return 0;}
    let cmd=load64(value);let begin=vk_struct(32,42);vk_u32(begin+16,1);
    if vk_call("vkBeginCommandBuffer",cmd,begin,0,0,0,0) {return 0;}return cmd;
}
fn vk_barrier(cmd) {
    let barrier=vk_struct(48,1000314000);store64(barrier+16,0x10000);store64(barrier+24,0x10000);
    store64(barrier+32,0x14000);store64(barrier+40,0xa000);
    let dep=vk_struct(64,1000314003);vk_u32(dep+20,1);store64(dep+24,barrier);
    return vk_void("vkCmdPipelineBarrier2KHR",cmd,dep,0,0,0,0);
}
fn vk_submit(cmd) {
    if vk_call("vkEndCommandBuffer",cmd,0,0,0,0,0) {return vk_status;}
    let commands=alloc(8);store64(commands,cmd);let submit=vk_struct(72,4);vk_u32(submit+40,1);store64(submit+48,commands);
    if vk_call("vkQueueSubmit",vk_queue,1,submit,0,0,0) {return vk_status;}return vk_call("vkQueueWaitIdle",vk_queue,0,0,0,0,0);
}
// Build one triangle geometry or one instance geometry, with explicit primitive count.
fn vk_acceleration(geometry,kind,primitives) {
    if !geometry || (kind!=0 && kind!=1) || primitives<1 || primitives>4294967295 {vk_status=-10010;vk_error="Invalid acceleration-structure geometry";return 0;}
    let build=vk_struct(80,1000150000);vk_u32(build+16,kind);vk_u32(build+20,1);
    vk_u32(build+48,1);store64(build+56,geometry);
    let count=alloc(4);vk_u32(count,primitives);let sizes=vk_struct(40,1000150020);
    if vk_void("vkGetAccelerationStructureBuildSizesKHR",vk_device,0,build,count,sizes,0) {return 0;}
    let buffer=vk_buffer(load64(sizes+16),0x100000|0x20000,0);if !buffer {return 0;}
    let create=vk_struct(64,1000150017);store64(create+24,load64(buffer));store64(create+40,load64(sizes+16));vk_u32(create+48,kind);
    let value=alloc(8);if vk_call("vkCreateAccelerationStructureKHR",vk_device,create,0,value,0,0) {return 0;}
    let acceleration=load64(value);let node=alloc(16);store64(node,vk_accelerations);store64(node+8,acceleration);vk_accelerations=node;
    let alignment=vk_scratch_alignment;let scratch=vk_buffer(load64(sizes+32)+alignment,0x20|0x20000,0);if !scratch {return 0;}
    store64(build+40,acceleration);store64(build+72,(load64(scratch+24)+alignment-1)&(-alignment));
    let range=alloc(16);vk_u32(range,primitives);let ranges=alloc(8);store64(ranges,range);
    let cmd=vk_commands();if !cmd {return 0;}
    if vk_void("vkCmdBuildAccelerationStructuresKHR",cmd,1,build,ranges,0,0) {return 0;}
    if vk_barrier(cmd) || vk_submit(cmd) {return 0;}return acceleration;
}
fn vk_acceleration_address(acceleration) {
    let info=vk_struct(24,1000150002);store64(info+16,acceleration);return vk_address("vkGetAccelerationStructureDeviceAddressKHR",vk_device,info);
}
fn vk_triangle_geometry(vertices,stride,count) {
    let g=vk_struct(96,1000150006);vk_u32(g+88,1);let t=g+24;vk_u32(t,1000150005);
    vk_u32(t+16,106);store64(t+24,load64(vertices+24));store64(t+32,stride);vk_u32(t+40,count-1);vk_u32(t+44,1000165000);return g;
}
fn vk_instance_geometry(instances) {
    let g=vk_struct(96,1000150006);vk_u32(g+16,2);vk_u32(g+24,1000150004);store64(g+48,load64(instances+24));return g;
}
fn vk_instance_identity(pointer,acceleration) {
    let i=0;while i<64 {store8(pointer+i,0);i=i+1;}
    vk_u32(pointer,0x3f800000);vk_u32(pointer+20,0x3f800000);vk_u32(pointer+40,0x3f800000);
    vk_u32(pointer+48,0xff000000);vk_u32(pointer+52,0x01000000);store64(pointer+56,vk_acceleration_address(acceleration));return 0;
}
// A compute pipeline with a push acceleration-structure descriptor at binding 0
// and a storage buffer at binding 1. Shader entry point is main.
// Record: pipeline, pipeline layout, descriptor layout, shader module.
fn vk_ray_pipeline(spirv,bytes) {
    if bytes<20 || bytes%4 || vk_get_u32(spirv)!=0x07230203 {vk_status=-10007;vk_error="Invalid SPIR-V module";return 0;}
    let value=alloc(8);let bindings=alloc(48);vk_u32(bindings,0);vk_u32(bindings+4,1000150000);vk_u32(bindings+8,1);vk_u32(bindings+12,32);
    vk_u32(bindings+24,1);vk_u32(bindings+28,7);vk_u32(bindings+32,1);vk_u32(bindings+36,32);
    let descriptors=vk_struct(32,32);vk_u32(descriptors+16,1);vk_u32(descriptors+20,2);store64(descriptors+24,bindings);
    if vk_call("vkCreateDescriptorSetLayout",vk_device,descriptors,0,value,0,0) {return 0;}let ds=vk_keep(2,load64(value));
    let sets=alloc(8);store64(sets,ds);let layout=vk_struct(48,30);vk_u32(layout+20,1);store64(layout+24,sets);
    if vk_call("vkCreatePipelineLayout",vk_device,layout,0,value,0,0) {return 0;}let pl=vk_keep(3,load64(value));
    let shader=vk_struct(40,16);store64(shader+24,bytes);store64(shader+32,spirv);
    if vk_call("vkCreateShaderModule",vk_device,shader,0,value,0,0) {return 0;}let sm=vk_keep(4,load64(value));
    let info=vk_struct(96,29);vk_u32(info+24,18);vk_u32(info+44,32);store64(info+48,sm);store64(info+56,"main");store64(info+72,pl);vk_u32(info+88,-1);
    if vk_call("vkCreateComputePipelines",vk_device,0,1,info,0,value) {return 0;}let pipeline=vk_keep(5,load64(value));
    let record=alloc(32);store64(record,pipeline);store64(record+8,pl);store64(record+16,ds);store64(record+24,sm);return record;
}
fn vk_ray_dispatch(pipeline,acceleration,output,x,y,z) {
    if x<1 || y<1 || z<1 || x>65535 || y>65535 || z>65535 {vk_status=-10008;vk_error="Invalid dispatch dimensions";return vk_status;}
    let cmd=vk_commands();if !cmd {return vk_status;}
    if vk_void("vkCmdBindPipeline",cmd,1,load64(pipeline),0,0,0) {return vk_status;}
    let writes=vk_struct(128,35);let as=vk_struct(32,1000150007);let handle=alloc(8);store64(handle,acceleration);vk_u32(as+16,1);store64(as+24,handle);
    store64(writes+8,as);vk_u32(writes+32,1);vk_u32(writes+36,1000150000);
    vk_u32(writes+64,35);vk_u32(writes+88,1);vk_u32(writes+96,1);vk_u32(writes+100,7);
    let buffer=alloc(24);store64(buffer,load64(output));store64(buffer+16,load64(output+32));store64(writes+112,buffer);
    if vk_void("vkCmdPushDescriptorSetKHR",cmd,1,load64(pipeline+8),0,2,writes) {return vk_status;}
    if vk_void("vkCmdDispatch",cmd,x,y,z,0,0) {return vk_status;}
    if vk_barrier(cmd) {return vk_status;}return vk_submit(cmd);
}
fn vk_close() {
    if vk_device {
        vk_call("vkDeviceWaitIdle",vk_device,0,0,0,0,0);
        let node=vk_objects;while node {
            let kind=load64(node+8);let name="vkDestroyCommandPool";
            if kind==2 {name="vkDestroyDescriptorSetLayout";}else if kind==3 {name="vkDestroyPipelineLayout";}
            else if kind==4 {name="vkDestroyShaderModule";}else if kind==5 {name="vkDestroyPipeline";}
            vk_void(name,vk_device,load64(node+16),0,0,0,0);node=load64(node);
        }
        node=vk_accelerations;while node {vk_void("vkDestroyAccelerationStructureKHR",vk_device,load64(node+8),0,0,0,0);node=load64(node);}
        node=vk_allocations;while node {
            let b=load64(node+8);if load64(b+16) {vk_void("vkUnmapMemory",vk_device,load64(b+8),0,0,0,0);}
            if load64(b) {vk_void("vkDestroyBuffer",vk_device,load64(b),0,0,0,0);}
            if load64(b+8) {vk_void("vkFreeMemory",vk_device,load64(b+8),0,0,0,0);}node=load64(node);
        }
        vk_void("vkDestroyDevice",vk_device,0,0,0,0,0);vk_device=0;
    }
    if vk_instance {vk_void("vkDestroyInstance",vk_instance,0,0,0,0,0);vk_instance=0;}
    vk_queue=0;vk_physical=0;vk_objects=0;vk_accelerations=0;vk_allocations=0;return 0;
}
