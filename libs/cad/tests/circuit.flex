import "../spice.flex";

fn pct_sample(report,index) {
    let row=load64(j_get(report,"samples")+16);
    while row && index>0 {row=load64(row+24);index=index-1;}
    return row;
}

fn pct_million(value) {
    return f64_to_i64_nearest(f64_mul(psc_number(value),f64_from_i64(1000000)));
}

fn pct_contains(text,part) {
    let size=m_len(text);let length=m_len(part);let at=0;
    while at+length<=size {
        if m_eq(m_slice(text+at,length),part) {return 1;}
        at=at+1;
    }
    return 0;
}

fn pct_transient(document,id,net) {
    let result=pcad_circuit(document,id);
    m_assert(m_eq(j_string(result,"engine"),"pcad-native-linear-1") && !m_len(j_string(result,"error")),j_string(result,"error"));
    m_assert(cg_j_count(j_get(result,"samples"))==501,"An RC step retains all 501 authored times");
    m_assert(pct_million(j_get(j_get(pct_sample(result,1),"voltages"),net))==49505
        && pct_million(j_get(j_get(pct_sample(result,100),"voltages"),net))==3151444
        && pct_million(j_get(j_get(pct_sample(result,500),"voltages"),net))==4965463,
        "Backward-Euler RC samples agree with V=5(1-1.01^-n) to the nearest microvolt");
    return result;
}

fn pct_deck(document,id,index) {
    let result=pcad_spice(document,id,index,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    m_assert(m_eq(j_string(result,"format"),"biscuit-pcad-ngspice-1"),j_string(result,"error"));
    let text=j_string(result,"deck");
    m_assert(pct_contains(text,"* Manifest SHA-256 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n")
        && pct_contains(text,"* Source SHA-256 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n"),
        "A SPICE deck retains the caller's frozen provenance");
    return text;
}

fn pct_analysis(source) {
    let document=j_parse(source);let e=j_get(document,"electrical");
    let experiment=load64(j_get(e,"experiments")+16);
    cg_j_set(experiment,"analysis",j_text("ac"));
    cg_j_set(experiment,"ac",j_parse("{\"source_id\":\"V1\",\"start_hz\":1.591549430918953,\"stop_hz\":15915.49430918953,\"points\":3}"));
    cg_j_set(experiment,"variation",j_parse("{\"component_id\":\"R1\",\"values\":[1000,2000]}"));
    let result=pcad_circuit(document,"rc");
    m_assert(cg_j_count(j_get(result,"samples"))==3,j_string(result,"error"));
    let response=j_get(j_get(pct_sample(result,1),"response"),"out");
    m_assert(pct_million(j_get(response,"real"))==500000 && pct_million(j_get(response,"imaginary"))==-500000,
        "The complex response at the first-order cutoff is 0.5-j0.5");
    let variant=load64(j_get(j_get(result,"comparison"),"cases")+16);
    response=j_get(j_get(pct_sample(j_get(variant,"result"),1),"response"),"out");
    m_assert(pct_million(j_get(response,"gain"))==447214,"Doubling the resistance changes comparison gain");
    let deck=pct_deck(document,"rc",1);
    m_assert(pct_contains(deck,"V1 n1 0 DC 5 AC 1\n") && pct_contains(deck,"R2 n1 n2 2000000000000000e-12\n")
        && pct_contains(deck,"ac lin 1 "),"The comparison deck carries the selected resistance and AC stimulus");
    m_assert(m_len(j_string(pcad_spice(document,"rc",2,"",""),"error")),"Invalid comparison selections are rejected");

    document=j_parse(source);e=j_get(document,"electrical");experiment=load64(j_get(e,"experiments")+16);
    j_add(j_get(e,"components"),0,j_parse("{\"id\":\"R2\",\"reference\":\"R2\",\"simulation\":{\"kind\":\"resistor\",\"value\":1000},\"pins\":[{\"id\":\"plus\",\"number\":\"1\"},{\"id\":\"minus\",\"number\":\"2\"}]}"));
    j_add(j_get(psc_find(j_get(e,"nets"),"out"),"endpoints"),0,j_parse("{\"component_id\":\"R2\",\"pin_id\":\"plus\"}"));
    j_add(j_get(psc_find(j_get(e,"nets"),"gnd"),"endpoints"),0,j_parse("{\"component_id\":\"R2\",\"pin_id\":\"minus\"}"));
    cg_j_set(experiment,"analysis",j_text("dc"));
    result=pcad_circuit(document,"rc");
    m_assert(cg_j_count(j_get(result,"samples"))==1,j_string(result,"error"));
    let sample=pct_sample(result,0);
    m_assert(pct_million(j_get(j_get(sample,"voltages"),"out"))==2500000
        && pct_million(j_get(j_get(sample,"currents"),"V1"))==-2500,"DC divider keeps the signed source current");
    m_assert(pct_contains(pct_deck(document,"rc",0),"\n.op\n"),"DC export uses an operating point");
    cg_j_set(experiment,"analysis",j_text("dc_sweep"));
    cg_j_set(experiment,"dc_sweep",j_parse("{\"source_id\":\"V1\",\"start_v\":4,\"stop_v\":-4,\"points\":5}"));
    result=pcad_circuit(document,"rc");
    m_assert(cg_j_count(j_get(result,"samples"))==5,j_string(result,"error"));
    sample=pct_sample(result,4);
    m_assert(pct_million(j_get(sample,"input_v"))==-4000000
        && pct_million(j_get(j_get(sample,"voltages"),"out"))==-2000000,"A descending source sweep preserves signed voltage");
    m_assert(pct_contains(pct_deck(document,"rc",0),"\n.dc V1 "),"SPICE export preserves the planned source sweep");
}

fn main(argc,argv) {
    let source=m_read_file("libs/cad/tests/fixtures/circuit-rc.pcad");
    let document=j_parse(source);
    m_assert(document,"Read the ideal RC fixture");
    pct_transient(document,"rc","out");
    let long=j_parse(source);
    let experiment=psc_find(j_get(j_get(long,"electrical"),"experiments"),"rc");
    cg_j_set(experiment,"stop_s",j_number(3600));
    cg_j_set(experiment,"step_s",j_new(6,"1200.000000001"));
    let expected=psc_final_timing(experiment);
    let report=pcad_circuit(long,"rc");
    let time=psc_number(j_get(pct_sample(report,3),"time_s"));
    m_assert(j_integer(expected,"sample_count")==4 && j_integer(expected,"time_ps")==3600000000003000
        && j_integer(expected,"time_ps")==f64_to_i64_nearest(f64_mul(time,f64_from_i64(1000000000000))),
        "Release timing follows the valid last sample near the solver's maximum duration");
    let resistor=psc_find(j_get(j_get(document,"electrical"),"components"),"R1");
    cg_j_set(resistor,"reference",j_text("Filter\n.control INJECT"));
    let deck=pct_deck(document,"rc",0);
    m_assert(pct_contains(deck,"C3 n2 0 1e-6 IC=0\n") && pct_contains(deck," UIC\n")
        && !pct_contains(deck,"INJECT"),"Transient export uses zero initial voltage and encoded identifiers only");
    cg_j_set(j_get(resistor,"simulation"),"value",j_number(0));
    m_assert(m_len(j_string(pcad_circuit(document,"rc"),"error")),"A zero-valued resistor fails model validation");
    pct_analysis(source);
    if argc==2 {
        document=j_parse(m_read_file(load64(argv+8)));
        let report=pct_transient(document,"sensor-response","analog");
        resistor=psc_find(j_get(report,"devices"),"m_filter-r");
        m_assert(m_eq(j_encode(j_get(j_get(resistor,"module_occurrence"),"path")),"[\"filter\"]"),
            "The authored sensor resistor keeps its resolved occurrence identity");
        deck=pct_deck(document,"sensor-response",0);
        m_assert(pct_contains(deck,"* Node n2 = net analog\n")
            && pct_contains(deck,"* Device R2 = component m_filter-r pins plus minus\n"),"The exact sensor source maps the authored RC module to the deck");
    }
    return 0;
}
