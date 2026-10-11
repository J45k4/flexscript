// Schedule rewrites retain both original outputs, so other tensor consumers
// remain valid. The model graph and checkpoint do not depend on this pass.
global lm_fusion=7;
fn lm_fuse() {
    let steps=h_vec();let i=0;
    while i<h_count(lm_steps) {
        let s=h_at(lm_steps,i);let next=0;if i+1<h_count(lm_steps) {next=h_at(lm_steps,i+1);}
        let third=0;if i+2<h_count(lm_steps) {third=h_at(lm_steps,i+2);}
        if (lm_fusion&1) && next && third && load64(s)==5 && load64(next)==5 && load64(third)==5 && load64(s+24)==load64(next+24) && load64(s+24)==load64(third+24) && load64(s+40)==load64(next+40) && load64(s+40)==load64(third+40) && load64(next+8)==load64(third+8) {
            let qrows=load64(s+8)/32;let krows=load64(next+8)/32;
            let x=load64(s+24);let w=load64(s+16);let y=load64(s+32);let n=load64(s+40);
            store64(s,10);store64(s+8,(qrows+krows*2)*32);store64(s+96,qrows|(krows<<32));
            store64(s+16,x);store64(s+24,w);store64(s+32,load64(next+16));store64(s+40,load64(third+16));
            store64(s+48,y);store64(s+56,load64(next+32));store64(s+64,load64(third+32));store64(s+72,n);i=i+2;
        }else if (lm_fusion&1) && next && load64(s)==6 && load64(s+40)==128 && load64(next)==2 && load64(s+32)==load64(next+16) && load64(s+8)*2==load64(next+8) {
            let original=load64(s+32);let epsilon=load64(s+56);
            store64(s,7);store64(s+32,load64(next+24));store64(s+40,epsilon);
            store64(s+48,load64(next+32));store64(s+56,load64(next+40));store64(s+64,original);i=i+1;
        }else if (lm_fusion&4) && next && load64(s)==3 && load64(s+40)==1 && load64(next)==6 && load64(next+40)!=128 && load64(s+32)==load64(next+16) && load64(s+8)*128==load64(next+40)*load64(next+8) {
            let residual=load64(s+32);store64(s,9);store64(s+8,load64(next+8));store64(s+32,load64(next+32));
            store64(s+40,load64(next+40));store64(s+48,load64(next+48));store64(s+56,load64(next+56));
            store64(s+64,load64(next+24));store64(s+72,residual);i=i+1;
        }else if (lm_fusion&2) && next && i+3<h_count(lm_steps) && load64(s)==5 && load64(next)==3 && load64(next+40)==3 && load64(next+16)==load64(s+32) {
            let up=h_at(lm_steps,i+2);let mul=h_at(lm_steps,i+3);
            if load64(up)==5 && load64(up+40)==load64(s+40) && load64(up+24)==load64(s+24) && load64(up+8)==load64(s+8) && load64(mul)==3 && load64(mul+40)==2 && load64(mul+8)*32==load64(s+8) && ((load64(mul+16)==load64(next+32) && load64(mul+24)==load64(up+32)) || (load64(mul+24)==load64(next+32) && load64(mul+16)==load64(up+32))) {
                let x=load64(s+24);let raw=load64(s+32);
                store64(s,8);store64(s+24,load64(up+16));store64(s+32,x);store64(s+48,raw);
                store64(s+56,load64(next+32));store64(s+64,load64(up+32));store64(s+72,load64(mul+32));i=i+3;
            }
        }
        h_add(steps,s);i=i+1;
    }
    lm_steps=steps;return 0;
}
