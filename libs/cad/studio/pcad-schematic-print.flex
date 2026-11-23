// Printable schematic presentation from the resolved electrical document.
// Chart positions use rounded diagram coordinates.
import "pcad-drawings.flex";
import "pcad-circuit-math.flex";
import "unicode/utf8.flex";

fn psp_coordinate(value) {
    let n=psc_number(value);
    if !f64_is_finite(n) || f64_magnitude(n)>f64_from_i64(10000) {
        return cg_fail("Schematic print needs coordinates within +/-10,000");
    }
    return f64_to_i64_nearest(n);
}

fn psp_point(value) {
    if j_kind(value)!=3 || cg_j_count(value)!=2 {return cg_fail("Invalid schematic point");}
    let row=load64(value+16);
    return cg_v(psp_coordinate(row),psp_coordinate(load64(row+24)),0);
}

fn psp_bounds(plot,x,y) {
    if x<load64(plot) {store64(plot,x);}
    if y<load64(plot+8) {store64(plot+8,y);}
    if x>load64(plot+16) {store64(plot+16,x);}
    if y>load64(plot+24) {store64(plot+24,y);}
    return 0;
}

fn psp_x(plot,x) {return load64(plot+40)+(x-load64(plot))*load64(plot+32)/1000;}
fn psp_y(plot,y) {return load64(plot+48)-(y-load64(plot+8))*load64(plot+32)/1000;}

fn psp_line(out,plot,x,y,u,v) {
    if x!=u || y!=v {pdd_pdf_line(out,psp_x(plot,x),psp_y(plot,y),psp_x(plot,u),psp_y(plot,v));}
    return 0;
}

fn psp_elbow(out,plot,x,y,u,v) {
    psp_line(out,plot,x,y,u,y);psp_line(out,plot,u,y,u,v);return 0;
}

fn psp_anchor(anchors,end) {
    let symbol=j_string(end,"symbol_id");let pin=j_string(end,"pin_id");
    if !m_len(symbol) || m_len(symbol)>129 || !ph_id(pin,64,1) {return 0;}
    return ph_get(anchors,m_cat(symbol,m_cat("@",pin)));
}

fn psp_wire(out,plot,a,b,bends,broken) {
    if !a && !b {return 0;}
    if broken {m_text(out,"q 0.68 0.20 0.14 RG 3 w [14 8] 0 d\n");}
    else {m_text(out,"q 0.10 0.37 0.29 RG 3 w\n");}
    let reverse=!a;
    if reverse {a=b;b=0;}
    let x=load64(a);let y=load64(a+8);let lead=x-18;
    psp_line(out,plot,x,y,lead,y);
    let points=load64(bends+16);
    if b && !points {
        let exit=load64(b)-18;
        if lead!=exit {
            let above=pdd_min(load64(a+32),load64(b+32))-20;
            psp_line(out,plot,lead,y,lead,above);psp_line(out,plot,lead,above,exit,above);
            psp_line(out,plot,exit,above,exit,load64(b+8));
        }else {psp_line(out,plot,lead,y,lead,load64(b+8));}
    }else {
        let previous_x=lead;let previous_y=y;
        let order=m_take(12*8);let count=0;
        while points && count<12 {
            store64(order+count*8,points);count=count+1;points=load64(points+24);
        }
        let index=0;
        while index<count && !cg_error {
            let at=index;if reverse {at=count-1-index;}
            let point=psp_point(load64(order+at*8));if cg_error {return 0;}
            let px=load64(point);let py=load64(point+8);
            if !index {psp_line(out,plot,lead,y,lead,py);previous_y=py;}
            psp_elbow(out,plot,previous_x,previous_y,px,py);
            previous_x=px;previous_y=py;index=index+1;
        }
        if b {
            let exit=load64(b)-18;
            psp_elbow(out,plot,previous_x,previous_y,exit,load64(b+8));
        }
    }
    if b {psp_line(out,plot,load64(b)-18,load64(b+8),load64(b),load64(b+8));}
    m_text(out,"S Q\n");
    return 1;
}

fn psp_dot(out,x,y,radius) {
    let control=(radius*552+500)/1000;
    m_text(out,"q 0.10 0.37 0.29 rg ");
    pdd_pdf_point(out,x+radius,y);m_text(out,"m\n");
    pdd_pdf_curve(out,x+radius,y+control,x+control,y+radius,x,y+radius);
    pdd_pdf_curve(out,x-control,y+radius,x-radius,y+control,x-radius,y);
    pdd_pdf_curve(out,x-radius,y-control,x-control,y-radius,x,y-radius);
    pdd_pdf_curve(out,x+control,y-radius,x+radius,y-control,x+radius,y);
    m_text(out,"f Q\n");
    return 0;
}

fn psp_glyph(out,plot,x,y,symbol) {
    let path=0;
    if m_eq(symbol,"resistor") {path="2 10 m 6 10 l 8 6 l 12 14 l 16 6 l 20 14 l 22 10 l 26 10 l ";}
    if m_eq(symbol,"capacitor") {path="2 10 m 11 10 l 11 4 m 11 16 l 15 4 m 15 16 l 15 10 m 26 10 l ";}
    if m_eq(symbol,"voltage") {
        path="2 10 m 6 10 l 22 10 m 26 10 l 22 10 m 22 14 18 18 14 18 c 10 18 6 14 6 10 c 6 6 10 2 14 2 c 18 2 22 6 22 10 c 10 8 m 14 8 l 12 6 m 12 10 l 15 12 m 19 12 l ";
    }
    if !path {return 0;}
    let scale=cg_decimal(load64(plot+32)*1000);
    m_text(out,"q 0.24 0.38 0.30 RG 1.1 w ");
    m_text(out,scale);m_text(out," 0 0 -");m_text(out,scale);m_text(out," ");
    pdd_pdf_point(out,psp_x(plot,x),psp_y(plot,y));m_text(out,"cm\n");
    m_text(out,path);m_text(out,"S Q\n");
    return 1;
}

// The basic PDF font uses ASCII text here. Preserve engineering units
// shown in component values by spelling their symbols in that alphabet.
fn psp_pdf_value(value) {
    let out=m_buffer();let at=0;let length=m_len(value);
    while at<length {
        let scalar=unicode_utf8_read(value,length,at);
        let width=1;let code=0;
        if scalar>=0 {width=scalar&7;code=scalar>>3;}
        if code==937 || code==8486 {m_text(out,"ohm");}
        else if code==181 || code==956 {m_text(out,"u");}
        else {m_append(out,value+at,width);}
        at=at+width;
    }
    return m_data(out);
}

fn psp_sheet(e,sheet,revision) {
    cg_begin();
    let id=j_string(sheet,"id");let title=j_string(sheet,"name");
    let components=j_get(e,"components");let nets=j_get(e,"nets");
    let placements=j_get(sheet,"placements");let links=j_get(sheet,"connections");let notes=j_get(sheet,"notes");
    if !ph_id(id,64,1) || !m_len(title) || m_len(title)>320 || j_kind(components)!=3 || j_kind(nets)!=3
        || cg_j_count(components)>96 || cg_j_count(nets)>128 || j_kind(placements)!=3 || cg_j_count(placements)>96
        || (links && (j_kind(links)!=3 || cg_j_count(links)>128))
        || (notes && (j_kind(notes)!=3 || cg_j_count(notes)>64)) {return cg_fail("Invalid schematic print inputs");}
    let plot=m_take(56);store64(plot,10000);store64(plot+8,10000);
    store64(plot+16,-10000);store64(plot+24,-10000);
    let anchors=j_object();let pin_rows=cg_array();let cards=cg_array();
    let seen=j_object();let placed=0;let row=load64(placements+16);
    while row && !cg_error {
        let key=j_string(row,"component_id");let comp=pnr_find(components,key);let pins=j_get(comp,"pins");
        let symbol=j_string(row,"id");
        if !j_get(row,"id") {symbol=m_cat(id,m_cat(":",key));}
        if !ph_id(key,64,1) || !m_len(symbol) || m_len(symbol)>129 || !ph_index(seen,symbol,1)
            || !ph_index(seen,m_cat("component@",key),1) || j_kind(pins)!=3 || cg_j_count(pins)>64 {
            return cg_fail("A schematic symbol needs a unique ID and an available component");
        }
        let x=psp_coordinate(j_get(row,"x"));let y=psp_coordinate(j_get(row,"y"));
        let height=cg_j_count(pins)*18+35;if height<58 {height=58;}
        psp_bounds(plot,x-26,y-30);psp_bounds(plot,x+165,y+height+12);
        let card=m_take(32);store64(card,x);store64(card+8,y);store64(card+16,height);store64(card+24,comp);
        cg_push(cards,card);placed=placed+1;
        let i=0;let pin=load64(pins+16);
        while pin && !cg_error {
            let identity=j_string(pin,"id");
            if !ph_id(identity,64,1) {return cg_fail("Invalid schematic pin ID");}
            let data=m_take(48);store64(data,x);store64(data+8,y+37+i*18);
            store64(data+16,pin);store64(data+24,pnr_assigned_net(e,comp,pin));store64(data+32,y);store64(data+40,0);
            if !ph_index(anchors,m_cat(symbol,m_cat("@",identity)),data) {return 0;}
            cg_push(pin_rows,data);i=i+1;pin=load64(pin+24);
        }
        row=load64(row+24);
    }
    let link=0;if links {link=load64(links+16);}
    while link && !cg_error {
        let bends=ph_rows(link,"bends",12);
        while bends && !cg_error {
            let at=psp_point(bends);
            if cg_error {return 0;}
            psp_bounds(plot,load64(at)-14,load64(at+8)-14);
            psp_bounds(plot,load64(at)+14,load64(at+8)+14);bends=load64(bends+24);
        }
        link=load64(link+24);
    }
    let note=0;if notes {note=load64(notes+16);}
    while note && !cg_error {
        let at=psp_point(j_get(note,"at"));
        if cg_error {return 0;}
        let text=j_string(note,"text");
        let pin=psp_anchor(anchors,j_get(note,"anchor"));
        if j_get(note,"anchor") {
            text="Unresolved net label";if pin && load64(pin+24) {text=j_string(load64(pin+24),"name");}
        }
        let width=m_len(text)*8;if width<144 {width=144;}
        psp_bounds(plot,load64(at)-14,load64(at+8)-22);
        psp_bounds(plot,load64(at)+width,load64(at+8)+18);note=load64(note+24);
    }
    if cg_error {return 0;}
    let width=load64(plot+16)-load64(plot);let height=load64(plot+24)-load64(plot+8);
    if width<=0 {width=1;}if height<=0 {height=1;}
    let fit=2400000/(width+1);
    if height>0 && 1410000/(height+1)<fit {fit=1410000/(height+1);}
    if fit>3000 {fit=3000;}
    if fit<=0 {return cg_fail("Schematic is too large to print");}
    store64(plot+32,fit);store64(plot+40,145+(2690-width*fit/1000)/2);
    store64(plot+48,1710-(1460-height*fit/1000)/2);
    let out=m_buffer();
    m_text(out,".283464567 0 0 .283464567 0 0 cm\n0.12 0.21 0.17 rg 0.24 0.35 0.28 RG 2.5 w 1 J 1 j\n");
    pdd_pdf_text(out,145,1936,21,pdd_pdf_short(title,65));
    pdd_pdf_text(out,145,1852,9,m_cat("SCHEMATIC   |   Sheet ",id));
    pdd_pdf_line(out,145,1798,2825,1798);m_text(out,"S\n");
    if !placed {pdd_pdf_text(out,145,1650,11,"No symbols placed");}
    let unresolved=0;
    if links {link=load64(links+16);}
    while link && !cg_error {
        let ends=j_get(link,"ends");
        let bends=j_get(link,"bends");
        if j_kind(ends)!=3 || cg_j_count(ends)!=2 || j_kind(bends)!=3 {return cg_fail("Schematic connection needs two pin references and bends");}
        let first=load64(ends+16);
        let a=psp_anchor(anchors,first);let b=psp_anchor(anchors,load64(first+24));
        let broken=!a || !b || a==b;
        if !broken {
            let left=load64(a+24);let right=load64(b+24);
            broken=!left || !right || !m_eq(j_string(left,"id"),j_string(right,"id"))
                || j_value(j_get(load64(a+16),"no_connect")) || j_value(j_get(load64(b+16),"no_connect"));
        }
        if broken {unresolved=unresolved+1;}
        else {store64(a+40,load64(a+40)+1);store64(b+40,load64(b+40)+1);}
        psp_wire(out,plot,a,b,bends,broken);
        link=load64(link+24);
    }
    let i=0;
    while i<cg_count(cards) {
        let card=cg_at(cards,i);let x=load64(card);let y=load64(card+8);let comp=load64(card+24);
        let bottom=psp_y(plot,y+load64(card+16));
        m_text(out,"q 1 1 1 rg 0.26 0.39 0.31 RG 2.3 w ");
        pdd_pdf_point(out,psp_x(plot,x),bottom);
        pdd_pdf_point(out,psp_x(plot,x+150)-psp_x(plot,x),psp_y(plot,y)-bottom);
        m_text(out,"re B Q\n");
        let glyph=psp_glyph(out,plot,x+115,y+10,j_string(pl_pinned(e,comp),"symbol"));
        let reference_limit=22;let value_limit=26;
        if glyph {reference_limit=16;value_limit=20;}
        let label=pdd_pdf_short(j_string(comp,"reference"),reference_limit);
        pdd_pdf_text(out,psp_x(plot,x+10),psp_y(plot,y+17),pdd_min(10,3+fit/380),label);
        let value=j_string(comp,"value");
        if m_len(value) {pdd_pdf_text(out,psp_x(plot,x+10),psp_y(plot,y+29),pdd_min(8,3+fit/480),pdd_pdf_short(psp_pdf_value(value),value_limit));}
        i=i+1;
    }
    i=0;
    while i<cg_count(pin_rows) {
        let pin=cg_at(pin_rows,i);let x=load64(pin);let y=load64(pin+8);let definition=load64(pin+16);
        let size=5;if load64(pin+40)>1 {size=9;}
        psp_dot(out,psp_x(plot,x),psp_y(plot,y),size);
        let label=j_string(load64(pin+24),"name");
        if j_value(j_get(definition,"no_connect")) {label="NC";}
        if !m_len(label) {label="?";}
        let number=pdd_pdf_short(j_string(definition,"number"),6);
        let name=j_string(definition,"name");
        if m_len(name) && m_len(label)<12 {number=m_cat(number,m_cat(" ",pdd_pdf_short(name,11)));}
        let text=m_cat(number,m_cat("  ",pdd_pdf_short(label,17)));
        pdd_pdf_text(out,psp_x(plot,x+10),psp_y(plot,y+4),pdd_min(9,3+fit/450),text);
        i=i+1;
    }
    if notes {note=load64(notes+16);}
    while note && !cg_error {
        let at=psp_point(j_get(note,"at"));if cg_error {return 0;}
        let x=load64(at);let y=load64(at+8);let text=j_string(note,"text");let anchor=j_get(note,"anchor");
        let pin=psp_anchor(anchors,anchor);
        if anchor {
            text="Unresolved net label";let net=0;
            if pin {net=load64(pin+24);}
            if net {
                text=j_string(net,"name");let px=load64(pin);let py=load64(pin+8);
                m_text(out,"q 0.12 0.35 0.31 RG 2 w [8 5] 0 d\n");
                psp_line(out,plot,px,py,px-18,py);psp_line(out,plot,px-18,py,px-18,y);
                psp_line(out,plot,px-18,y,x,y);m_text(out,"S Q\n");
            }else {unresolved=unresolved+1;}
        }
        pdd_pdf_text(out,psp_x(plot,x),psp_y(plot,y),pdd_min(10,4+fit/450),pdd_pdf_short(text,120));
        note=load64(note+24);
    }
    if cg_error {return 0;}
    pdd_pdf_line(out,145,222,2825,222);m_text(out,"S\n");
    pdd_pdf_text(out,145,158,9,m_cat("Unresolved connections or labels: ",m_int(unresolved)));
    pdd_pdf_text(out,145,103,8,revision);
    let result=j_object();
    cg_j_text(result,"id",id);cg_j_text(result,"name",title);
    cg_j_int(result,"unresolved",unresolved);cg_j_text(result,"schematic_body",m_data(out));
    return result;
}
