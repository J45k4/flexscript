// Resolve and solve ideal circuits from a frozen PCAD experiment.
// Node voltages use its declared ground. Branch orientation is pin 1 to pin 2.
import "studio/pcad-hierarchy.flex";
import "studio/pcad-circuit-math.flex";

fn psc_kind(model) {
    if m_eq(model,"resistor") {return 1;}
    if m_eq(model,"capacitor") {return 2;}
    if m_eq(model,"voltage") {return 3;}
    return 0;
}
fn psc_unit(kind) {
    if kind==1 {return "Ω";}
    if kind==2 {return "F";}
    return "V";
}
fn psc_value_valid(kind,value) {
    if !f64_is_finite(value) {return 0;}
    if kind==1 {return f64_ge(value,0x3f50624dd2f1a9fc) && f64_le(value,0x41cdcd6500000000);}
    if kind==2 {return f64_ge(value,0x3d719799812dea11) && f64_le(value,0x3ff0000000000000);}
    return kind==3 && f64_magnitude(value)<=0x408f400000000000;
}

fn psc_find(rows,id) {
    let row=load64(rows+16);
    while row {if m_eq(j_string(row,"id"),id) {return row;}row=load64(row+24);}
    return 0;
}

// Circuit elements are [positive net, negative net, kind, value, descriptor].
// The net slots index the resolved graph. Matrix rows are assigned after
// identifying which nets actually participate in an experiment.
fn psc_plan(document,id) {
    cg_error=0;
    if !m_eq(j_string(document,"format"),"puppycorp.pcad") || j_integer(document,"schema_version")!=1 || !ph_id(id,64,1) {
        return cg_fail("Choose a PCAD experiment by its stable ID.");
    }
    let resolved=pcad_resolve(document);
    if !resolved {return 0;}
    let electrical=j_get(resolved,"electrical");
    let experiments=j_get(electrical,"experiments");
    if j_kind(experiments)!=3 || cg_j_count(experiments)>16 {return cg_fail("Choose a stored circuit experiment.");}
    let experiment=0;let row=load64(experiments+16);let seen=j_object();
    while row {
        let key=j_string(row,"id");
        if !ph_id(key,64,1) || !ph_index(seen,key,row) {return cg_fail("Invalid or duplicate experiment ID.");}
        if m_eq(key,id) {experiment=row;}
        row=load64(row+24);
    }
    if !experiment {return cg_fail("Circuit experiment was not found.");}
    let all_nets=j_get(electrical,"nets");let all_devices=j_get(electrical,"components");
    if j_kind(all_nets)!=3 || cg_j_count(all_nets)>128 || j_kind(all_devices)!=3 || cg_j_count(all_devices)>96 {
        return cg_fail("Invalid circuit nets or components.");
    }
    let net_index=j_object();let pin_net=j_object();let observations=m_take(128*8);
    let ordinal=0;let ground=-1;row=load64(all_nets+16);
    while row {
        let net_id=j_string(row,"id");
        if !ph_id(net_id,64,1) || !ph_index(net_index,net_id,row) || !m_len(j_string(row,"name")) {
            return cg_fail("Invalid net identity.");
        }
        if m_eq(net_id,j_string(experiment,"ground_net_id")) {ground=ordinal;}
        let endpoints=j_get(row,"endpoints");
        if j_kind(endpoints)!=3 || cg_j_count(endpoints)>6144 {return cg_fail("Invalid endpoint list.");}
        let pin=load64(endpoints+16);
        while pin {
            let member=j_string(pin,"component_id");let terminal=j_string(pin,"pin_id");
            if !ph_id(member,64,1) || !ph_id(terminal,64,1) || !ph_index(pin_net,ph_key_pin(member,terminal),ordinal+1) {
                return cg_fail("A connected pin must have one net assignment.");
            }
            pin=load64(pin+24);
        }
        store64(observations+ordinal*8,0);
        row=load64(row+24);ordinal=ordinal+1;
    }
    if ground<0 {return cg_fail("Choose a ground net.");}
    let elements=m_take(32*40);let used=0;let source_count=0;let ids=j_object();let labels=j_object();
    let catalog=j_array();row=load64(all_devices+16);
    while row {
        let member=j_string(row,"id");let label=j_string(row,"reference");
        let model=j_get(row,"simulation");let name=j_string(model,"kind");
        if !ph_id(member,64,1) || !ph_index(ids,member,row) || !ph_index(labels,label,row) || m_len(label)>80 {
            return cg_fail("Invalid component identity.");
        }
        if !m_eq(name,"ignore") {
            let kind=psc_kind(name);
            if !kind {return cg_fail(m_cat("Choose a simulation model or Exclude for ",label));}
            let value=psc_number(j_get(model,"value"));
            if !psc_value_valid(kind,value) {return cg_fail(m_cat("Invalid simulation value for ",label));}
            if used>=32 {return cg_fail("Use at most 32 modeled components.");}
            let pins=j_get(row,"pins");
            if j_kind(pins)!=3 || cg_j_count(pins)!=2 {return cg_fail(m_cat("Exactly two pins are required for ",label));}
            let positive=0;let negative=0;let plus_id=0;let minus_id=0;let pin=load64(pins+16);
            while pin {
                let pin_id=j_string(pin,"id");let number=j_string(pin,"number");
                if !ph_id(pin_id,64,1) || j_value(j_get(pin,"no_connect")) {return cg_fail(m_cat("Invalid modeled pin on ",label));}
                if m_eq(number,"1") {positive=ph_get(pin_net,ph_key_pin(member,pin_id));plus_id=pin_id;}
                if m_eq(number,"2") {negative=ph_get(pin_net,ph_key_pin(member,pin_id));minus_id=pin_id;}
                pin=load64(pin+24);
            }
            if !positive || !negative {return cg_fail(m_cat("Pins 1 and 2 need assigned nets on ",label));}
            let slot=elements+used*40;store64(slot,positive-1);store64(slot+8,negative-1);
            store64(slot+16,kind);store64(slot+24,value);
            store64(observations+(positive-1)*8,1);store64(observations+(negative-1)*8,1);
            let device=j_object();cg_j_text(device,"id",member);cg_j_text(device,"reference",label);
            cg_j_text(device,"positive_pin_id",plus_id);cg_j_text(device,"negative_pin_id",minus_id);
            cg_j_text(device,"kind",name);ph_child(device,"value",j_get(model,"value"));
            if j_get(row,"module_occurrence") {ph_child(device,"module_occurrence",j_get(row,"module_occurrence"));}
            if j_get(row,"definition") {
                let binding=j_get(row,"definition");
                let origin=j_object();cg_j_text(origin,"definition_id",j_string(binding,"definition_id"));
                cg_j_int(origin,"revision",j_integer(binding,"revision"));cg_j_set(device,"component_definition",origin);
            }
            j_add(catalog,0,device);store64(slot+32,device);
            if kind==3 {source_count=source_count+1;}
            used=used+1;
        }
        row=load64(row+24);
    }
    if !used || !load64(observations+ground*8) {return cg_fail("The ground net must participate in the circuit.");}
    let probes=j_array();let count=0;let unknowns=0;ordinal=0;row=load64(all_nets+16);
    while row {
        if load64(observations+ordinal*8) {
            let probe=j_object();cg_j_text(probe,"id",j_string(row,"id"));cg_j_text(probe,"name",j_string(row,"name"));
            let index=-1;
            if ordinal!=ground {index=unknowns;unknowns=unknowns+1;}
            cg_j_int(probe,"node",index);
            j_add(probes,0,probe);store64(observations+ordinal*8,probe);count=count+1;
        }
        row=load64(row+24);ordinal=ordinal+1;
    }
    if count>16 {return cg_fail("Use at most 16 participating nets.");}
    let i=0;
    while i<used {
        let pair=elements+i*40;let a=load64(observations+load64(pair)*8);let b=load64(observations+load64(pair+8)*8);
        store64(pair,j_integer(a,"node"));store64(pair+8,j_integer(b,"node"));
        let device=load64(pair+32);
        cg_j_text(device,"positive_net_id",j_string(a,"id"));cg_j_text(device,"negative_net_id",j_string(b,"id"));
        i=i+1;
    }
    // Plan: experiment, probes, modeled elements, count, node count,
    // voltage-source count, ordered exported model descriptors.
    let plan=m_take(56);
    store64(plan,experiment);store64(plan+8,probes);store64(plan+16,elements);
    store64(plan+24,used);store64(plan+32,unknowns);store64(plan+40,source_count);store64(plan+48,catalog);
    return plan;
}

fn psc_mark(matrix,n,row,column,value) {
    if row<0 || column<0 {return 0;}
    let element=matrix+(row*n+column)*8;store64(element,f64_add(load64(element),value));return 1;
}

fn psc_admit(matrix,n,a,b,value) {
    psc_mark(matrix,n,a,a,value);psc_mark(matrix,n,b,b,value);
    psc_mark(matrix,n,a,b,f64_math_neg(value));psc_mark(matrix,n,b,a,f64_math_neg(value));
    return 0;
}

fn psc_constraint(matrix,n,k,a,b) {
    let one=f64_from_i64(1);let negative=f64_from_i64(-1);
    psc_mark(matrix,n,k,a,one);psc_mark(matrix,n,a,k,one);
    psc_mark(matrix,n,k,b,negative);psc_mark(matrix,n,b,k,negative);
    return 0;
}

fn psc_zero(words,n) {let i=0;while i<n {store64(words+i*8,0);i=i+1;}return words;}
fn psc_voltage(vector,node) {if node<0 {return 0;}return load64(vector+node*8);}
fn psc_add_current(rhs,node,value) {
    if node>=0 {let p=rhs+node*8;store64(p,f64_add(load64(p),value));}
    return 0;
}
fn psc_source(plan,id) {
    let elements=load64(plan+16);let i=0;let index=load64(plan+32);
    while i<load64(plan+24) {
        let c=elements+i*40;
        if load64(c+16)==3 {
            if m_eq(j_string(load64(c+32),"id"),id) {return index;}
            index=index+1;
        }
        i=i+1;
    }
    return -1;
}

fn psc_stamp(plan,matrix,rhs,n,dt,initial) {
    let elements=load64(plan+16);let i=0;let k=load64(plan+32);
    while i<load64(plan+24) {
        let c=elements+i*40;let a=load64(c);let b=load64(c+8);let kind=load64(c+16);let value=load64(c+24);
        if kind==1 {psc_admit(matrix,n,a,b,f64_div(f64_from_i64(1),value));}
        if kind==2 && dt {psc_admit(matrix,n,a,b,f64_div(value,dt));}
        if kind==3 || (kind==2 && initial) {
            psc_constraint(matrix,n,k,a,b);
            if kind==3 {store64(rhs+k*8,value);}
            k=k+1;
        }
        i=i+1;
    }
    return 1;
}

fn psc_voltages(plan,x) {
    let out=j_object();let net=load64(load64(plan+8)+16);
    while net {
        cg_j_set(out,j_string(net,"id"),psc_decimal(psc_voltage(x,j_integer(net,"node"))));
        net=load64(net+24);
    }
    return out;
}

fn psc_currents(plan,x) {
    let out=j_object();let i=0;let k=load64(plan+32);
    while i<load64(plan+24) {
        let c=load64(plan+16)+i*40;let kind=load64(c+16);let value=0;
        if kind==1 {value=f64_div(f64_sub(psc_voltage(x,load64(c)),psc_voltage(x,load64(c+8))),load64(c+24));}
        if kind==3 {value=load64(x+k*8);k=k+1;}
        cg_j_set(out,j_string(load64(c+32),"id"),psc_decimal(value));
        i=i+1;
    }
    return out;
}

fn psc_result(plan,analysis) {
    let experiment=load64(plan);let out=j_object();
    cg_j_text(out,"engine","pcad-native-linear-1");cg_j_text(out,"analysis",analysis);
    cg_j_text(out,"ground_net_id",j_string(experiment,"ground_net_id"));
    ph_child(out,"nets",load64(plan+8));ph_child(out,"devices",load64(plan+48));
    cg_j_set(out,"samples",j_array());return out;
}

fn psc_steady(plan,analysis) {
    let settings=j_get(load64(plan),"dc_sweep");let sweep=m_eq(analysis,"dc_sweep");
    let count=1;let first=0;let last=0;let source=-1;
    if sweep {
        count=j_integer(settings,"points");first=psc_number(j_get(settings,"start_v"));last=psc_number(j_get(settings,"stop_v"));
        source=psc_source(plan,j_string(settings,"source_id"));
        if source<0 {return cg_fail("Choose an ideal voltage source for the DC sweep.");}
        if count<2 || count>101 || !psc_value_valid(3,first) || !psc_value_valid(3,last)
            || f64_magnitude(f64_sub(last,first))<0x3e112e0be826d695 {
            return cg_fail("Choose distinct DC endpoints within ±1000 V and 2–101 samples.");
        }
    }
    let n=load64(plan+32)+load64(plan+40);
    if n<1 {return cg_fail("Nothing to solve in this configuration.");}
    let matrix=psc_zero(m_take(n*n*8),n*n);let rhs=psc_zero(m_take(n*8),n);
    let lu=m_take(n*n*8);let pivots=m_take(n*8);let x=m_take(n*8);
    psc_stamp(plan,matrix,rhs,n,0,0);
    if !psc_factor(matrix,lu,pivots,n) {return cg_fail("The DC matrix is singular or ill-conditioned.");}
    let out=psc_result(plan,analysis);let samples=j_get(out,"samples");
    cg_j_set(out,"units",j_parse("{\"voltage\":\"V\",\"current\":\"A\"}"));
    cg_j_text(out,"scope","Ideal DC operating points. Capacitors are open at DC. Device current is positive from pin 1 to pin 2.");
    if sweep {ph_child(out,"swept_source",psc_find(load64(plan+48),j_string(settings,"source_id")));}
    let i=0;
    while i<count {
        let sample=j_object();
        if sweep {
            let value=last;
            if i<count-1 {value=f64_add(first,f64_mul(f64_sub(last,first),f64_div(f64_from_i64(i),f64_from_i64(count-1))));}
            store64(rhs+source*8,value);cg_j_set(sample,"input_v",psc_decimal(value));
        }else {cg_j_int(sample,"time_s",0);}
        if !psc_solve(matrix,lu,pivots,rhs,x,n) {return cg_fail("The DC solution exceeded its numerical tolerance.");}
        cg_j_set(sample,"voltages",psc_voltages(plan,x));cg_j_set(sample,"currents",psc_currents(plan,x));
        j_add(samples,0,sample);i=i+1;
    }
    return out;
}

fn psc_time_sample(plan,out,x,t) {
    let sample=j_object();
    cg_j_set(sample,"time_s",psc_decimal(t));cg_j_set(sample,"voltages",psc_voltages(plan,x));
    return j_add(j_get(out,"samples"),0,sample);
}

fn psc_transient(plan) {
    let experiment=load64(plan);
    let stop=psc_number(j_get(experiment,"stop_s"));let dt=psc_number(j_get(experiment,"step_s"));
    let steps=psc_transient_steps(stop,dt);
    if steps<0 {return cg_fail("Choose a positive time step and stop time of at most 3600 seconds.");}
    if !steps {return cg_fail("Use a whole number of 1–500 time steps.");}
    let elements=load64(plan+16);let count=load64(plan+24);let i=0;
    let n=load64(plan+32)+load64(plan+40);let initial_n=n;
    let conductance=m_take(count*8);
    while i<count {
        let c=elements+i*40;
        if load64(c+16)==2 {
            initial_n=initial_n+1;
            store64(conductance+i*8,f64_div(load64(c+24),dt));
        }
        i=i+1;
    }
    if n<1 {return cg_fail("Nothing to solve in this configuration.");}
    let matrix=m_take(initial_n*initial_n*8);let rhs=m_take(initial_n*8);
    let lu=m_take(initial_n*initial_n*8);let pivots=m_take(initial_n*8);let x=m_take(initial_n*8);
    psc_stamp(plan,psc_zero(matrix,initial_n*initial_n),psc_zero(rhs,initial_n),initial_n,0,1);
    if !psc_factor(matrix,lu,pivots,initial_n) || !psc_solve(matrix,lu,pivots,rhs,x,initial_n) {
        return cg_fail("The zero-capacitor-voltage initial state is inconsistent or floating.");
    }
    let out=psc_result(plan,"transient");
    cg_j_text(out,"scope","Fixed-step backward Euler, zero initial capacitor voltage and intended ideal nets.");
    cg_j_set(out,"units",j_parse("{\"time\":\"s\",\"voltage\":\"V\"}"));
    cg_j_set(out,"integration_step_s",psc_decimal(dt));
    psc_time_sample(plan,out,x,0);
    let bias=psc_zero(m_take(n*8),n);
    psc_stamp(plan,psc_zero(matrix,n*n),bias,n,dt,0);
    if !psc_factor(matrix,lu,pivots,n) {return cg_fail("The transient matrix is singular or ill-conditioned.");}
    let step=1;
    while step<=steps {
        i=0;while i<n {store64(rhs+i*8,load64(bias+i*8));i=i+1;}
        i=0;while i<count {
            let c=elements+i*40;
            if load64(c+16)==2 {
                let a=load64(c);let b=load64(c+8);
                let previous=f64_sub(psc_voltage(x,a),psc_voltage(x,b));
                let current=f64_mul(load64(conductance+i*8),previous);
                psc_add_current(rhs,a,current);psc_add_current(rhs,b,f64_math_neg(current));
            }
            i=i+1;
        }
        if !psc_solve(matrix,lu,pivots,rhs,x,n) {return cg_fail("The transient solution exceeded its numerical tolerance.");}
        psc_time_sample(plan,out,x,f64_mul(dt,f64_from_i64(step)));
        step=step+1;
    }
    return out;
}

fn psc_ac_point(plan,x,n,frequency) {
    let response=j_object();let net=load64(load64(plan+8)+16);
    let sample=j_object();
    cg_j_set(sample,"frequency_hz",psc_decimal(frequency));cg_j_set(sample,"response",response);
    while net {
        let index=j_integer(net,"node");
        let real=psc_voltage(x,index);let imaginary=psc_voltage(x+n*8,index);
        let gain=f64_hypot(real,imaginary);
        let decibels=j_new(0,0);let phase=j_new(0,0);
        if f64_magnitude(gain) {
            decibels=psc_decimal(f64_mul(psc_log(gain),0x40215f2ced384f28));
            phase=psc_decimal(f64_mul(f64_atan2(imaginary,real),0x404ca5dc1a63c1f8));
        }
        let phase_response=j_object();
        cg_j_set(phase_response,"real",psc_decimal(real));
        cg_j_set(phase_response,"imaginary",psc_decimal(imaginary));
        cg_j_set(phase_response,"gain",psc_decimal(gain));
        cg_j_set(phase_response,"gain_db",decibels);cg_j_set(phase_response,"phase_deg",phase);
        cg_j_set(response,j_string(net,"id"),phase_response);
        net=load64(net+24);
    }
    return sample;
}

fn psc_ac(plan) {
    let settings=j_get(load64(plan),"ac");let count=j_integer(settings,"points");
    let first=psc_number(j_get(settings,"start_hz"));let last=psc_number(j_get(settings,"stop_hz"));
    let source_id=j_string(settings,"source_id");let source=psc_source(plan,source_id);
    if source<0 {return cg_fail("Choose an ideal voltage source for the AC stimulus.");}
    if !f64_is_finite(first) || !f64_is_finite(last) || f64_lt(first,0x3eb0c6f7a0b5ed8d)
        || f64_gt(last,0x41cdcd6500000000) || !f64_gt(last,first)
        || f64_lt(f64_div(f64_sub(last,first),first),0x3eb0c6f7a0b5ed8d) || count<2 || count>201 {
        return cg_fail("Choose a wider increasing range within 1 µHz to 1 GHz and 2–201 AC samples.");
    }
    let n=load64(plan+32)+load64(plan+40);let block_n=2*n;
    let G=psc_zero(m_take(n*n*8),n*n);let C=psc_zero(m_take(n*n*8),n*n);
    let rhs=psc_zero(m_take(block_n*8),block_n);let x=m_take(block_n*8);
    let lu=m_take(block_n*block_n*8);let pivots=m_take(block_n*8);
    let block=m_take(block_n*block_n*8);
    psc_stamp(plan,G,rhs,n,0,0);
    if !psc_factor(G,lu,pivots,n) || !psc_solve(G,lu,pivots,rhs,x,n) {
        return cg_fail("AC needs a defined DC operating point.");
    }
    let out=psc_result(plan,"ac");
    cg_j_set(out,"units",j_parse("{\"frequency\":\"Hz\",\"gain\":\"V/V\",\"gain_db\":\"dB\",\"phase\":\"deg\",\"voltage\":\"V\"}"));
    cg_j_set(out,"dc_voltages",psc_voltages(plan,x));
    let device=psc_find(load64(plan+48),source_id);let stimulus=j_object();
    cg_j_text(stimulus,"component_id",source_id);cg_j_int(stimulus,"voltage",1);
    cg_j_text(stimulus,"positive_net_id",j_string(device,"positive_net_id"));
    cg_j_text(stimulus,"negative_net_id",j_string(device,"negative_net_id"));
    cg_j_set(out,"stimulus",stimulus);
    cg_j_text(out,"scope","Small-signal response about the DC operating point. The selected source applies a 1 V perturbation; other voltage sources have zero AC voltage.");
    let i=0;
    while i<load64(plan+24) {
        let c=load64(plan+16)+i*40;
        if load64(c+16)==2 {psc_admit(C,n,load64(c),load64(c+8),load64(c+24));}
        i=i+1;
    }
    let log_start=psc_log(first);let span=f64_sub(psc_log(last),log_start);
    let step=f64_div(span,f64_from_i64(count-1));
    psc_zero(rhs,block_n);store64(rhs+source*8,f64_from_i64(1));
    let p=0;
    while p<count {
        let frequency=first;
        if p==count-1 {frequency=last;}
        else if p>0 {frequency=f64_exp(f64_add(log_start,f64_mul(step,f64_from_i64(p))));}
        let omega=f64_mul(frequency,0x401921fb54442d18);
        // Real block form of (G + jωC) x = rhs.
        i=0;
        while i<n {
            let j=0;
            while j<n {
                let g=load64(G+(i*n+j)*8);
                let c=f64_mul(omega,load64(C+(i*n+j)*8));
                store64(block+(i*block_n+j)*8,g);
                store64(block+((i+n)*block_n+j+n)*8,g);
                store64(block+((i+n)*block_n+j)*8,c);
                store64(block+(i*block_n+j+n)*8,f64_math_neg(c));
                j=j+1;
            }
            i=i+1;
        }
        if !psc_factor(block,lu,pivots,block_n) || !psc_solve(block,lu,pivots,rhs,x,block_n) {
            return cg_fail("The AC matrix is singular or exceeded its numerical tolerance.");
        }
        j_add(j_get(out,"samples"),0,psc_ac_point(plan,x,n,frequency));
        p=p+1;
    }
    return out;
}

fn psc_run(plan) {
    let analysis=j_string(load64(plan),"analysis");
    if m_eq(analysis,"dc") || m_eq(analysis,"dc_sweep") {return psc_steady(plan,analysis);}
    if m_eq(analysis,"transient") {return psc_transient(plan);}
    if m_eq(analysis,"ac") {return psc_ac(plan);}
    return cg_fail("Choose a supported circuit analysis.");
}

fn psc_case_values(plan,variation) {
    let id=j_string(variation,"component_id");
    let experiment=load64(plan);
    if m_eq(j_string(experiment,"analysis"),"dc_sweep") && m_eq(id,j_string(j_get(experiment,"dc_sweep"),"source_id")) {
        return cg_fail("Choose a comparison component other than the swept source.");
    }
    let elements=load64(plan+16);let target=0;let i=0;
    while i<load64(plan+24) {
        let entry=elements+i*40;
        if m_eq(id,j_string(load64(entry+32),"id")) {target=entry;}
        i=i+1;
    }
    if !target {return cg_fail("Choose a modeled component for comparison.");}
    let values=j_get(variation,"values");let count=0;
    if j_kind(values)==3 {count=cg_j_count(values);}
    if count<2 || count>5 {return cg_fail("Choose 2–5 distinct parameter values.");}
    let cases=m_take((count+2)*8);store64(cases,target);store64(cases+8,count);
    let row=load64(values+16);i=0;
    while row {
        let v=psc_number(row);
        if !psc_value_valid(load64(target+16),v) {return cg_fail("A comparison value exceeds the model range.");}
        let j=0;
        while j<i {
            if f64_eq(load64(cases+(j+2)*8),v) {return cg_fail("Choose distinct parameter values.");}
            j=j+1;
        }
        store64(cases+(i+2)*8,v);i=i+1;row=load64(row+24);
    }
    return cases;
}

fn psc_comparisons(plan,values) {
    let target=load64(values);let device=load64(target+32);
    let baseline=load64(target+24);let count=load64(values+8);
    let result=j_object();let cases=j_array();
    cg_j_text(result,"component_id",j_string(device,"id"));
    cg_j_text(result,"reference",j_string(device,"reference"));
    cg_j_text(result,"model_kind",j_string(device,"kind"));
    cg_j_text(result,"unit",psc_unit(load64(target+16)));
    cg_j_set(result,"baseline_value",psc_decimal(baseline));
    cg_j_set(result,"cases",cases);
    let i=0;
    while i<count {
        let value=load64(values+(i+2)*8);
        if !f64_eq(value,baseline) {
            store64(target+24,value);
            let variant=psc_run(plan);
            store64(target+24,baseline);
            if !variant {return 0;}
            let models=j_array();let model=load64(load64(plan+48)+16);
            while model {
                if model==device {
                    let changed=j_parse(j_encode(model));
                    cg_j_set(changed,"value",psc_decimal(value));j_add(models,0,changed);
                }else {ph_child(models,0,model);}
                model=load64(model+24);
            }
            cg_j_set(variant,"devices",models);
            let c=j_object();cg_j_set(c,"value",psc_decimal(value));
            cg_j_set(c,"result",variant);j_add(cases,0,c);
        }
        i=i+1;
    }
    return result;
}

fn pcad_circuit(document,experiment_id) {
    let plan=psc_plan(document,experiment_id);
    let out=0;
    if plan {
        let variation=j_get(load64(plan),"variation");let values=0;
        if variation {values=psc_case_values(plan,variation);}
        if !variation || values {
            out=psc_run(plan);
            if out && values {
                let comparison=psc_comparisons(plan,values);
                if comparison {cg_j_set(out,"comparison",comparison);}
                else {out=0;}
            }
        }
    }
    if out {return out;}
    let error=j_object();cg_j_text(error,"error",cg_error);return error;
}

fn pcad_circuit_write(result) {
    let text=j_encode(result);let n=m_len(text);
    if n>524288 {
        text="{\"error\":\"Circuit result exceeds 512 KiB. Reduce samples or comparison cases.\"}";
        n=m_len(text);
    }
    let offset=0;
    while offset<n {
        let size=n-offset;if size>4096 {size=4096;}
        m_assert(syscall(1,1,text+offset,size,0,0,0)==size,"Circuit result write was interrupted");
        offset=offset+size;
    }
    return 0;
}
