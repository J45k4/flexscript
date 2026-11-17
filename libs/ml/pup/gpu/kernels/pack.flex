// High FP16 plus a residual scaled by 2^10. Each FP32 element becomes one word.
import "ops.flex";
fn gpu_launch_word(index) {return 0;}
fn gpu_atomic_or64(pointer,value) {return 0;}
fn gpu_f32x2_to_f16x2(value) {return 0;}
fn gpu_f16x2_to_f32x2(value) {return 0;}
fn packed_offset(at) {let channels=gpu_launch_word(1);if !channels {return at;}let spatial=gpu_launch_word(2);let row=vk_quotient(at,channels*spatial);let c=vk_quotient(vk_remainder(at,channels*spatial),spatial);let s=vk_remainder(at,spatial);return (row*spatial+s)*channels+c;}
fn kernel(index,input,output,count) {
    let at=index*2;if at<count {
        let a=gpu_load_u32(input+at*4);let b=0;if at+1<count {b=gpu_load_u32(input+(at+1)*4);}
        if (a&0x7fffffff)>0x477fe000 || (b&0x7fffffff)>0x477fe000 {gpu_atomic_or64(gpu_launch_word(0),1);}
        let high=gpu_f32x2_to_f16x2(a|(b<<32));let rounded=gpu_f16x2_to_f32x2(high);
        let low=gpu_f32x2_to_f16x2(vk_mul(vk_sub(a,rounded&0xffffffff),0x44800000)|(vk_mul(vk_sub(b,rounded>>32),0x44800000)<<32));
        gpu_store_u32(output+packed_offset(at)*4,(high&65535)|((low&65535)<<16));if at+1<count {gpu_store_u32(output+packed_offset(at+1)*4,(high>>16)|(low&0xffff0000));}
    }return 0;
}
fn main() {return 78;}
