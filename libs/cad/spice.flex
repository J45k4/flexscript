// Runnable ngspice projection of a checked native circuit. Authored display
// strings never become solver tokens. Only stable IDs appear in comments.
import "circuit.flex";

fn psx_node(index) {
    if index<0 {return "0";}
    return m_cat("n",m_int(index+1));
}

fn psx_header(out,id,manifest_hash,source_hash) {
    m_text(out,"Biscuit PCAD ideal linear circuit\n* Experiment ");
    m_text(out,id);
    if m_len(manifest_hash) {m_text(out,"\n* Manifest SHA-256 ");m_text(out,manifest_hash);}
    m_text(out,"\n* Source SHA-256 ");m_text(out,source_hash);m_text(out,"\n");
    m_text(out,"* Intended connectivity; ideal R, C and voltage sources\n");
}

fn psx_deck(id,report,manifest_hash,source_hash) {
    let out=m_buffer();psx_header(out,id,manifest_hash,source_hash);
    let nodes=j_object();let names=j_object();let probes=load64(j_get(report,"nets")+16);
    let saved=m_buffer();
    while probes {
        let net=j_string(probes,"id");let index=j_integer(probes,"node");let name=psx_node(index);
        cg_j_text(nodes,net,name);
        m_text(out,"* Node ");m_text(out,name);m_text(out," = net ");m_text(out,net);m_text(out,"\n");
        if index>=0 {m_text(saved," v(");m_text(saved,name);m_text(saved,")");}
        probes=load64(probes+24);
    }
    let analysis=j_string(report,"analysis");
    let transient=m_eq(analysis,"transient");let ac=m_eq(analysis,"ac");
    let ac_source=j_string(j_get(report,"stimulus"),"component_id");
    let devices=load64(j_get(report,"devices")+16);let index=1;
    while devices {
        let kind=j_string(devices,"kind");let prefix="V";
        if m_eq(kind,"resistor") {prefix="R";}
        if m_eq(kind,"capacitor") {prefix="C";}
        let device=j_string(devices,"id");let name=m_cat(prefix,m_int(index));
        cg_j_text(names,device,name);
        m_text(out,"* Device ");m_text(out,name);m_text(out," = component ");m_text(out,device);
        m_text(out," pins ");m_text(out,j_string(devices,"positive_pin_id"));m_text(out," ");
        m_text(out,j_string(devices,"negative_pin_id"));m_text(out,"\n");
        m_text(out,name);m_text(out," ");m_text(out,j_string(nodes,j_string(devices,"positive_net_id")));
        m_text(out," ");m_text(out,j_string(nodes,j_string(devices,"negative_net_id")));m_text(out," ");
        if m_eq(prefix,"V") {m_text(out,"DC ");}
        m_text(out,j_encode(j_get(devices,"value")));
        if ac && m_eq(device,ac_source) {m_text(out," AC 1");}
        if transient && m_eq(prefix,"C") {m_text(out," IC=0");}
        m_text(out,"\n");devices=load64(devices+24);index=index+1;
    }
    let first=load64(j_get(report,"samples")+16);let last=first;
    while load64(last+24) {last=load64(last+24);}
    if transient {
        let dt=j_encode(j_get(report,"integration_step_s"));
        m_text(out,"* Zero initial capacitor voltage; ngspice uses adaptive steps\n.tran ");
        m_text(out,dt);m_text(out," ");m_text(out,j_encode(j_get(last,"time_s")));
        m_text(out," 0 ");m_text(out,dt);m_text(out," UIC\n");
    }else if ac {
        // Exactly evaluate the recorded frequencies; .ac dec specifies points
        // per decade and cannot reproduce arbitrary start/stop/sample counts.
        m_text(out,".control\nalias pcad_sample print frequency");
        m_text(out,m_data(saved));m_text(out,"\n");
        while first {
            let hz=j_encode(j_get(first,"frequency_hz"));
            m_text(out,"ac lin 1 ");m_text(out,hz);m_text(out," ");m_text(out,hz);
            m_text(out,"\npcad_sample\n");first=load64(first+24);
        }
        m_text(out,".endc\n");
    }else if m_eq(analysis,"dc_sweep") {
        let start=j_get(first,"input_v");let end=j_get(last,"input_v");
        let count=cg_j_count(j_get(report,"samples"));
        let spacing=f64_div(f64_sub(psc_number(end),psc_number(start)),f64_from_i64(count-1));
        m_text(out,".dc ");m_text(out,j_string(names,j_string(j_get(report,"swept_source"),"id")));
        m_text(out," ");m_text(out,j_encode(start));m_text(out," ");m_text(out,j_encode(end));
        m_text(out," ");m_text(out,j_encode(psc_decimal(spacing)));m_text(out,"\n");
    }else {m_text(out,".op\n");}
    m_text(out,".end\n");return m_data(out);
}

fn psx_error(message) {
    let error=j_object();cg_j_text(error,"error",message);return error;
}

fn pcad_spice(document,id,case_index,manifest_hash,source_hash) {
    let result=pcad_circuit(document,id);
    if m_len(j_string(result,"error")) {return result;}
    if case_index {
        let cases=j_get(j_get(result,"comparison"),"cases");let row=0;
        if j_kind(cases)==3 {row=load64(cases+16);}
        let i=1;
        while row && i<case_index {row=load64(row+24);i=i+1;}
        if !row {return psx_error("The requested SPICE comparison case is unavailable.");}
        result=j_get(row,"result");
    }
    let out=j_object();cg_j_text(out,"format","biscuit-pcad-ngspice-1");
    cg_j_text(out,"experiment_id",id);cg_j_int(out,"case_index",case_index);
    cg_j_text(out,"source_sha256",source_hash);
    cg_j_text(out,"deck",psx_deck(id,result,manifest_hash,source_hash));
    return out;
}

fn pcad_spice_write(input) {
    let out=pcad_spice(j_get(input,"document"),j_string(input,"experiment_id"),
        j_integer(input,"case_index"),"",j_string(input,"source_sha256"));
    if m_len(j_encode(out))>32768 {
        out=psx_error("SPICE deck exceeds the export size limit.");
    }
    return pcad_circuit_write(out);
}
