// Pure SDK scheduling policy. No CPU, clock, interrupt or context operations.
// TCB: next536,state544,base priority552,deadline560; wait kind592,
// object600,event bits608,all616,effective priority624,wake-hint scratch632. State3 waits.
// Wait kinds:1 semaphore,2 mutex,3 receive,4 send,5 event.
fn esp_sdk_task_linked(first,target) {
    if !first || !target {return 0;}let t=first;
    while 1 {if t==target {return t;}t=load64(t+536);if t==first {return 0;}}return 0;
}
fn esp_sdk_task_ready(task,now) {
    let state=load64(task+544);let deadline=load64(task+560);
    if state==1 {return deadline<=now;}if state!=3 {return 0;}
    if deadline<=now {return 1;}let kind=load64(task+592);let object=load64(task+600);if !object {return 0;}
    if kind==1 {return load64(object+8)>0;}
    if kind==2 {return !load64(object);}
    if kind==3 {return load64(object+24)>0;}
    if kind==4 {return load64(object+24)<load64(object);}
    if kind==5 {let bits=load64(task+608);let match=load64(object)&bits;if load64(task+616) {return match==bits;}return match!=0;}
    return 0;
}
fn esp_sdk_task_priorities(current,now,slot) {
    if !current {return 0;}let count=0;let t=current;
    let first=1;while first || t!=current {first=0;store64(t+slot,load64(t+552));count=count+1;t=load64(t+536);}
    // Recompute donations, including chains, so release/deletion/timeouts drop
    // inherited priorities. At most one pass per task; cycles cannot spin.
    let pass=0;let changed=1;while changed && pass<count {changed=0;t=current;first=1;
        while first || t!=current {first=0;
            if load64(t+544)==3 && load64(t+592)==2 && load64(t+560)>now {
                let mutex=load64(t+600);if mutex {let owner=esp_sdk_task_linked(current,load64(mutex));
                    if owner && load64(owner+544)!=2 && load64(owner+slot)<load64(t+slot) {store64(owner+slot,load64(t+slot));changed=1;}
                }
            }
            t=load64(t+536);
        }pass=pass+1;
    }
    return count;
}
fn esp_sdk_task_choose(current,now) {
    if !current {return 0;}esp_sdk_task_priorities(current,now,624);let t=0;
    // Start after the current task: equal-priority peers rotate. Include the
    // current task last so lower-priority tasks never displace a ready one.
    let best=0;let priority= -1;t=load64(current+536);
    let scanning=1;while scanning {if esp_sdk_task_ready(t,now) && load64(t+624)>priority {best=t;priority=load64(t+624);}if t==current {scanning=0;}else {t=load64(t+536);}}return best;
}

// A vendor wake bool requests reconsideration, not a promised context switch.
// Use an upper bound for waiter priority and the current task's base priority.
// Pending timeout expirations can only add conservative requests; the IRQ tail
// uses the real clock and exact inheritance. Keep hint scratch separate from
// effective priorities so this clock-free query never corrupts policy state.
fn esp_sdk_task_wake_hint(current,object,kind) {
    if !current || !object || (kind!=1 && kind!=3 && kind!=4) {return 0;}
    esp_sdk_task_priorities(current,0,632);let priority=load64(current+552);let task=load64(current+536);
    while task!=current {if load64(task+544)==3 && load64(task+592)==kind && load64(task+600)==object && load64(task+632)>priority {return 1;}task=load64(task+536);}return 0;
}
