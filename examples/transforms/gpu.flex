extend "../../extensions/compose.flex" with "step";
fn step(value) {return value*3+7;}
fn kernel(i,input,output,count) {store64(output+i*8,step_twice(load64(input+i*8)));return 0;}
