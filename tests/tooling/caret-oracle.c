/* Independent HarfBuzz/FreeType glyph and GDEF oracle; test-only. */
#include <stdio.h>
#include <stdlib.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <hb-ft.h>
#include <hb-ot.h>
int main(int argc,char **argv){
    if(argc!=4 && argc!=5)return 1;int px=atoi(argv[2]);FT_Library library;FT_Face face;
    if(FT_Init_FreeType(&library)||FT_New_Face(library,argv[1],0,&face))return 2;
    if(FT_Set_Pixel_Sizes(face,0,px)){
        int best=-1;long distance=0x7fffffff;
        for(int i=0;i<face->num_fixed_sizes;i++){long d=labs(face->available_sizes[i].y_ppem-px*64);if(d<distance){best=i;distance=d;}}
        if(best<0||FT_Select_Size(face,best))return 3;
    }
    int raster=face->size->metrics.y_ppem;hb_font_t *font=hb_ft_font_create_referenced(face);hb_ft_font_set_load_flags(font,FT_LOAD_COLOR);
    hb_buffer_t *buffer=hb_buffer_create();hb_buffer_add_utf8(buffer,argv[3],-1,0,-1);if(argc==5)hb_buffer_set_direction(buffer,atoi(argv[4]));hb_buffer_guess_segment_properties(buffer);hb_shape(font,buffer,NULL,0);
    unsigned count;hb_glyph_info_t *info=hb_buffer_get_glyph_infos(buffer,&count);hb_glyph_position_t *pos=hb_buffer_get_glyph_positions(buffer,NULL);
    printf("{\"direction\":%d,\"glyphs\":[",hb_buffer_get_direction(buffer));
    for(unsigned i=0;i<count;i++){
        hb_position_t carets[64];unsigned n=64;hb_ot_layout_get_ligature_carets(font,hb_buffer_get_direction(buffer),info[i].codepoint,0,&n,carets);
        printf("%s{\"id\":%u,\"cluster\":%u,\"advance\":%d,\"unshaped\":%d,\"carets\":[",i?",":"",info[i].codepoint,info[i].cluster,pos[i].x_advance*px/raster,hb_font_get_glyph_h_advance(font,info[i].codepoint)*px/raster);
        for(unsigned j=0;j<n;j++)printf("%s%d",j?",":"",carets[j]*px/raster);printf("]}");
    }
    puts("]}");hb_buffer_destroy(buffer);hb_font_destroy(font);FT_Done_Face(face);FT_Done_FreeType(library);return 0;
}
