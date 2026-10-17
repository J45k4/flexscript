// Two binary32 lanes packed in one 64-bit word (low, high).
// Ordinary scalar bodies are the fallback on other compiler targets.
import "f32.flex";
lowering f32x2_add "f32x2.add" "cpu-cxx";
lowering f32x2_sub "f32x2.sub" "cpu-cxx";
lowering f32x2_mul "f32x2.mul" "cpu-cxx";
fn f32x2_add(a,b){return f32_add(a&4294967295,b&4294967295)|(f32_add((a>>32)&4294967295,(b>>32)&4294967295)<<32);}
fn f32x2_sub(a,b){return f32_sub(a&4294967295,b&4294967295)|(f32_sub((a>>32)&4294967295,(b>>32)&4294967295)<<32);}
fn f32x2_mul(a,b){return f32_mul(a&4294967295,b&4294967295)|(f32_mul((a>>32)&4294967295,(b>>32)&4294967295)<<32);}
