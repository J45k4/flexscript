import "cad/electrical/cad.flex";
import "cad/electrical/render.flex";

fn presentation_board() {
    return j_parse("{\"units\":\"mm\",\"board\":{\"size\":[30,20],\"thickness\":1.6,\"outline\":[[0,0],[30,0],[30,18],[28,20],[0,20]],\"holes\":[{\"at\":[4,4],\"diameter\":2}]},\"nets\":[\"SIGNAL\",\"RETURN\"],\"components\":[{\"ref\":\"C1\",\"value\":\"100n\",\"footprint\":\"SMD_1206_OVAL\",\"at\":[10,5],\"pins\":{\"1\":\"SIGNAL\",\"2\":\"RETURN\"}},{\"ref\":\"C2\",\"value\":\"100n\",\"footprint\":\"SMD_1206_OVAL\",\"at\":[18,5],\"side\":\"back\",\"pins\":{\"1\":\"SIGNAL\",\"2\":\"RETURN\"}}],\"tracks\":[],\"vias\":[]}");
}

fn presentation_color(pixels,width,x,y) {
    let pixel=pixels+(y*width+x)*3;
    return (load8(pixel)<<16) | (load8(pixel+1)<<8) | load8(pixel+2);
}

fn main() {
    let board=presentation_board();let before=j_encode(board);let mesh=pcb_mesh(board);
    m_assert(j_value(j_get(mesh,"closed")) && cg_j_count(j_get(mesh,"parts"))==3,"A drilled, outlined substrate and two mounted SMD bodies are closed solids");
    let part=load64(j_get(mesh,"parts")+16);let front=load64(part+24);let back=load64(front+24);
    m_assert(m_eq(j_encode(j_get(front,"bounds")),"[[9.900000,4.200000,1.600000],[13.100000,5.800000,2.200000]]"),"Front body rests on the upper board surface");
    m_assert(m_eq(j_encode(j_get(back,"bounds")),"[[14.900000,4.200000,-0.600000],[18.100000,5.800000,0.000000]]"),"Back body reflects about pad one and faces downward");

    let width=316;let height=216;
    let front_pixels=pcb_render_rgb(board,width,height,"F.Cu");m_assert(front_pixels,cg_error);
    let back_pixels=pcb_render_rgb(board,width,height,"B.Cu");m_assert(back_pixels,cg_error);
    m_assert(presentation_color(front_pixels,width,108,158)==0xf2b35c && presentation_color(back_pixels,width,108,158)==0x32775a,"Front SMD copper appears on the front snapshot");
    m_assert(presentation_color(back_pixels,width,188,158)==0x71c6e4 && presentation_color(front_pixels,width,188,158)==0x32775a,"Back SMD copper appears on the back snapshot");
    m_assert(presentation_color(front_pixels,width,303,10)==0xf7f7f2 && presentation_color(front_pixels,width,48,168)==0xf7f7f2,"The snapshot clears the chamfered corner and drilled opening");
    m_assert(m_eq(j_encode(board),before),"Presentation leaves the authored PCB intact");
    return 0;
}
