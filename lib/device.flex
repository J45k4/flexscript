// Selectable GPU host API for shared ML schedules and graph replay.
import "cuda.flex";
import "hip.flex";
global device_backend=0;
global device_status=0;
fn device_select_hip(enabled) {device_backend=enabled;return 0;}
fn device_error() {if device_backend {let v=hip_error();device_status=hip_status;return v;}let v=cuda_error();device_status=cuda_status;return v;}
fn device_device_count() {if device_backend {let v=hip_device_count();device_status=hip_status;return v;}let v=cuda_device_count();device_status=cuda_status;return v;}
fn device_device(ordinal) {if device_backend {let v=hip_device(ordinal);device_status=hip_status;return v;}let v=cuda_device(ordinal);device_status=cuda_status;return v;}
fn device_device_attribute(device,attribute) {if device_backend {let v=hip_device_attribute(device,attribute);device_status=hip_status;return v;}let v=cuda_device_attribute(device,attribute);device_status=cuda_status;return v;}
fn device_device_name(device) {if device_backend {let v=hip_device_name(device);device_status=hip_status;return v;}let v=cuda_device_name(device);device_status=cuda_status;return v;}
fn device_memory_info() {if device_backend {let v=hip_memory_info();device_status=hip_status;return v;}let v=cuda_memory_info();device_status=cuda_status;return v;}
fn device_context_device(ordinal) {if device_backend {let v=hip_context_device(ordinal);device_status=hip_status;return v;}let v=cuda_context_device(ordinal);device_status=cuda_status;return v;}
fn device_close(context) {if device_backend {let v=hip_close(context);device_status=hip_status;return v;}let v=cuda_close(context);device_status=cuda_status;return v;}
fn device_synchronize() {if device_backend {let v=hip_synchronize();device_status=hip_status;return v;}let v=cuda_synchronize();device_status=cuda_status;return v;}
fn device_module(image) {if device_backend {let v=hip_module(image);device_status=hip_status;return v;}let v=cuda_module(image);device_status=cuda_status;return v;}
fn device_unload(module) {if device_backend {let v=hip_unload(module);device_status=hip_status;return v;}let v=cuda_unload(module);device_status=cuda_status;return v;}
fn device_buffer(bytes) {if device_backend {let v=hip_buffer(bytes);device_status=hip_status;return v;}let v=cuda_buffer(bytes);device_status=cuda_status;return v;}
fn device_free(pointer) {if device_backend {let v=hip_free(pointer);device_status=hip_status;return v;}let v=cuda_free(pointer);device_status=cuda_status;return v;}
fn device_upload(device,host,bytes) {if device_backend {let v=hip_upload(device,host,bytes);device_status=hip_status;return v;}let v=cuda_upload(device,host,bytes);device_status=cuda_status;return v;}
fn device_download(host,device,bytes) {if device_backend {let v=hip_download(host,device,bytes);device_status=hip_status;return v;}let v=cuda_download(host,device,bytes);device_status=cuda_status;return v;}
fn device_upload_async(device,host,bytes,stream) {if device_backend {let v=hip_upload_async(device,host,bytes,stream);device_status=hip_status;return v;}let v=cuda_upload_async(device,host,bytes,stream);device_status=cuda_status;return v;}
fn device_download_async(host,device,bytes,stream) {if device_backend {let v=hip_download_async(host,device,bytes,stream);device_status=hip_status;return v;}let v=cuda_download_async(host,device,bytes,stream);device_status=cuda_status;return v;}
fn device_copy_async(to,from,bytes,stream) {if device_backend {let v=hip_copy_async(to,from,bytes,stream);device_status=hip_status;return v;}let v=cuda_copy_async(to,from,bytes,stream);device_status=cuda_status;return v;}
fn device_host_buffer(bytes) {if device_backend {let v=hip_host_buffer(bytes);device_status=hip_status;return v;}let v=cuda_host_buffer(bytes);device_status=cuda_status;return v;}
fn device_host_free(pointer) {if device_backend {let v=hip_host_free(pointer);device_status=hip_status;return v;}let v=cuda_host_free(pointer);device_status=cuda_status;return v;}
fn device_function(module,name) {if device_backend {let v=hip_function(module,name);device_status=hip_status;return v;}let v=cuda_function(module,name);device_status=cuda_status;return v;}
fn device_function_attribute(function,attribute) {if device_backend {let v=hip_function_attribute(function,attribute);device_status=hip_status;return v;}let v=cuda_function_attribute(function,attribute);device_status=cuda_status;return v;}
fn device_occupancy(function,threads,shared) {if device_backend {let v=hip_occupancy(function,threads,shared);device_status=hip_status;return v;}let v=cuda_occupancy(function,threads,shared);device_status=cuda_status;return v;}
fn device_dispatch(function,config,arguments) {if device_backend {let v=hip_dispatch(function,config,arguments);device_status=hip_status;return v;}let v=cuda_dispatch(function,config,arguments);device_status=cuda_status;return v;}
fn device_launch_words(module,input,output,count,config,words) {if device_backend {let v=hip_launch_words(module,input,output,count,config,words);device_status=hip_status;return v;}let v=cuda_launch_words(module,input,output,count,config,words);device_status=cuda_status;return v;}
fn device_launch(module,input,output,count) {if device_backend {let v=hip_launch(module,input,output,count);device_status=hip_status;return v;}let v=cuda_launch(module,input,output,count);device_status=cuda_status;return v;}
fn device_stream() {if device_backend {let v=hip_stream();device_status=hip_status;return v;}let v=cuda_stream();device_status=cuda_status;return v;}
fn device_stream_wait(stream) {if device_backend {let v=hip_stream_wait(stream);device_status=hip_status;return v;}let v=cuda_stream_wait(stream);device_status=cuda_status;return v;}
fn device_stream_close(stream) {if device_backend {let v=hip_stream_close(stream);device_status=hip_status;return v;}let v=cuda_stream_close(stream);device_status=cuda_status;return v;}
fn device_capture_begin(stream) {if device_backend {let v=hip_capture_begin(stream);device_status=hip_status;return v;}let v=cuda_capture_begin(stream);device_status=cuda_status;return v;}
fn device_capture_end(stream) {if device_backend {let v=hip_capture_end(stream);device_status=hip_status;return v;}let v=cuda_capture_end(stream);device_status=cuda_status;return v;}
fn device_graph_instance(graph) {if device_backend {let v=hip_graph_instance(graph);device_status=hip_status;return v;}let v=cuda_graph_instance(graph);device_status=cuda_status;return v;}
fn device_graph_launch(graph,stream) {if device_backend {let v=hip_graph_launch(graph,stream);device_status=hip_status;return v;}let v=cuda_graph_launch(graph,stream);device_status=cuda_status;return v;}
fn device_graph_upload(graph,stream) {if device_backend {let v=hip_graph_upload(graph,stream);device_status=hip_status;return v;}let v=cuda_graph_upload(graph,stream);device_status=cuda_status;return v;}
fn device_graph_close(graph) {if device_backend {let v=hip_graph_close(graph);device_status=hip_status;return v;}let v=cuda_graph_close(graph);device_status=cuda_status;return v;}
fn device_graph_instance_close(graph) {if device_backend {let v=hip_graph_instance_close(graph);device_status=hip_status;return v;}let v=cuda_graph_instance_close(graph);device_status=cuda_status;return v;}
fn device_event() {if device_backend {let v=hip_event();device_status=hip_status;return v;}let v=cuda_event();device_status=cuda_status;return v;}
fn device_event_record(event,stream) {if device_backend {let v=hip_event_record(event,stream);device_status=hip_status;return v;}let v=cuda_event_record(event,stream);device_status=cuda_status;return v;}
fn device_event_wait(event) {if device_backend {let v=hip_event_wait(event);device_status=hip_status;return v;}let v=cuda_event_wait(event);device_status=cuda_status;return v;}
fn device_stream_wait_event(stream,event) {if device_backend {let v=hip_stream_wait_event(stream,event);device_status=hip_status;return v;}let v=cuda_stream_wait_event(stream,event);device_status=cuda_status;return v;}
fn device_event_close(event) {if device_backend {let v=hip_event_close(event);device_status=hip_status;return v;}let v=cuda_event_close(event);device_status=cuda_status;return v;}
fn device_event_elapsed_f32(start,end) {if device_backend {let v=hip_event_elapsed_f32(start,end);device_status=hip_status;return v;}let v=cuda_event_elapsed_f32(start,end);device_status=cuda_status;return v;}
fn device_config(gx,gy,gz,bx,by,bz,shared,stream) {if device_backend {let v=hip_config(gx,gy,gz,bx,by,bz,shared,stream);device_status=hip_status;return v;}let v=cuda_config(gx,gy,gz,bx,by,bz,shared,stream);device_status=cuda_status;return v;}
fn device_copy(to,from,bytes) {if device_backend {let v=hip_copy(to,from,bytes);device_status=hip_status;return v;}let v=cuda_call("cuMemcpyDtoD_v2",to,from,bytes,0,0,0);device_status=cuda_status;return v;}
