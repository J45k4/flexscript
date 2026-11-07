import "cnf.flex";
// Independent resolution-certificate checking. Derived clauses follow the
// original clauses in work. Each record is (left clause, right clause, pivot).
// Both parents precede the conclusion. The final clause must be empty.
fn pr_check(original,work,steps,count,final,budget) {
    if !pv_formula_valid(original) || !pv_formula_valid(work) || load64(original)!=load64(work) || count<0 || count>1048576 || budget<0 {return 0;}
    let base=load64(original+8);if load64(work+8)!=base+count || final<1 || final>base+count || (count && !steps) {return 0;}
    let c=0;while c<base {let a=load64(original+48)+c*16;let b=load64(work+48)+c*16;
        if load64(a+8)!=load64(b+8) {return 0;}let j=0;while j<load64(a+8) {
            if budget<=0 {return 0;}budget=budget-1;
            if load64(load64(original+56)+(load64(a)+j)*8)!=load64(load64(work+56)+(load64(b)+j)*8) {return 0;}j=j+1;
        }c=c+1;
    }
    let size=(load64(original)+1)*8;let marks=alloc(size);if marks<0 {return 0;}let accepted=1;let step=0;
    while step<count && accepted {
        if budget<=0 {accepted=0;}else {budget=budget-1;}
        let row=steps+step*24;let left=load64(row);let right=load64(row+8);let pivot=load64(row+16);let conclusion=base+step+1;
        if left<1 || right<1 || left>=conclusion || right>=conclusion || pivot<1 || pivot>load64(original) {accepted=0;}
        if accepted {
            let i=0;while i<=load64(original) {store64(marks+i*8,0);i=i+1;}
            let expected=0;let side=0;let first_sign=0;
            while side<2 && accepted {let parent=left;if side {parent=right;}let clause=load64(work+48)+(parent-1)*16;let j=0;let sign=0;
                while j<load64(clause+8) && accepted {if budget<=0 {accepted=0;}else {budget=budget-1;}
                    let literal=load64(load64(work+56)+(load64(clause)+j)*8);let variable=literal;let polarity=1;if variable<0 {variable= -variable;polarity= -1;}
                    if variable==pivot {if sign && sign!=polarity {accepted=0;}sign=polarity;}
                    else {let prior=load64(marks+variable*8);if prior && prior!=polarity {accepted=0;}if !prior {expected=expected+1;store64(marks+variable*8,polarity);}}
                    j=j+1;
                }
                if !sign {accepted=0;}if !side {first_sign=sign;}else if sign!= -first_sign {accepted=0;}side=side+1;
            }
            let clause=load64(work+48)+(conclusion-1)*16;if load64(clause+8)!=expected {accepted=0;}
            let j=0;while j<load64(clause+8) && accepted {
                if budget<=0 {accepted=0;}else {budget=budget-1;}
                let literal=load64(load64(work+56)+(load64(clause)+j)*8);let variable=literal;let sign=1;if variable<0 {variable= -variable;sign= -1;}
                if load64(marks+variable*8)!=sign {accepted=0;}store64(marks+variable*8,0);j=j+1;
            }
        }step=step+1;
    }
    if load64(load64(work+48)+(final-1)*16+8) {accepted=0;}syscall(11,marks,size,0,0,0,0);return accepted;
}
