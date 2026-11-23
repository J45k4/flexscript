import "cad/sketch-value.flex";

fn expect_value(text,kind,bindings,micro) {
    cg_begin();let q=pcv_evaluate(text,kind,bindings,0);m_assert(q,cg_error);
    m_assert(f64_to_i64_round(f64_mul(load64(q),f64_from_i64(1000000)))==micro,text);
}
fn reject_value(text,kind,bindings) {
    cg_begin();m_assert(!pcv_evaluate(text,kind,bindings,0) && cg_error,text);
}
fn main() {
    cg_begin();let vars=j_parse("[{\"name\":\"half\",\"kind\":\"length\",\"expression\":\"#width / #count\"},{\"name\":\"count\",\"kind\":\"scalar\",\"expression\":\"2\"},{\"name\":\"width\",\"kind\":\"length\",\"expression\":\"1 IN\"}]");
    let bindings=pcv_bind(vars);m_assert(bindings,cg_error);
    expect_value("#half * 2 + (4.6) mm",1,bindings,30000000);
    expect_value("0.001 m + 2 cm + 1 ft",1,bindings,325800000);
    expect_value("1e3 µm + 500 μm - 10 um",1,bindings,1490000);
    expect_value("PI rad - 90°",2,bindings,90000000);
    expect_value("-(1 inch / 2.54 cm) + +1.5e2",0,bindings,149000000);
    reject_value("2 mm + 1",1,bindings);reject_value("1 in * 2 cm",1,bindings);
    reject_value("1 deg / 2 cm",1,bindings);reject_value("1 mm mm",1,bindings);
    reject_value("(1+2",1,bindings);reject_value("#absent",1,bindings);
    reject_value("1e12345",1,bindings);reject_value("1/0",1,bindings);
    reject_value("1 deg",1,bindings);reject_value("2**3",0,bindings);
    cg_begin();let cycle=j_parse("[{\"name\":\"a\",\"kind\":\"length\",\"expression\":\"#b\"},{\"name\":\"b\",\"kind\":\"length\",\"expression\":\"#a\"}]");
    m_assert(!pcv_bind(cycle) && cg_error,"Variable cycle");
    return 0;
}
