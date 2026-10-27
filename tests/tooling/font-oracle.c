/* Independent result oracle, built only by the test harness. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <hb-ft.h>
int main(int argc, char **argv) {
    if (argc != 5) return 1;
    FT_Library library; FT_Face face;
    int px = atoi(argv[2]), direction = atoi(argv[4]);
    if (FT_Init_FreeType(&library) || FT_New_Face(library, argv[1], 0, &face)) return 2;
    if (FT_Set_Pixel_Sizes(face, 0, px)) {
        int best = -1; long distance = 0x7fffffff;
        for (int i = 0; i < face->num_fixed_sizes; ++i) {
            long d = labs(face->available_sizes[i].y_ppem - px * 64);
            if (d < distance) { best = i; distance = d; }
        }
        if (best < 0 || FT_Select_Size(face, best)) return 3;
    }
    int raster = face->size->metrics.y_ppem;
    hb_font_t *font = hb_ft_font_create_referenced(face);
    hb_ft_font_set_load_flags(font, FT_LOAD_COLOR);
    hb_buffer_t *buffer = hb_buffer_create();
    hb_buffer_add_utf8(buffer, argv[3], -1, 0, -1);
    if (direction) hb_buffer_set_direction(buffer, direction);
    hb_buffer_guess_segment_properties(buffer); hb_shape(font, buffer, NULL, 0);
    unsigned count; hb_glyph_info_t *info = hb_buffer_get_glyph_infos(buffer, &count);
    hb_glyph_position_t *position = hb_buffer_get_glyph_positions(buffer, NULL);
    printf("{\"height\":%ld,\"ascent\":%ld,\"raster_px\":%d,\"direction\":%d,\"glyphs\":[",
           (face->size->metrics.height * px / raster + 63) / 64,
           (face->size->metrics.ascender * px / raster + 63) / 64,
           raster, hb_buffer_get_direction(buffer));
    for (unsigned i = 0; i < count; ++i) {
        if (FT_Load_Glyph(face, info[i].codepoint, FT_LOAD_COLOR) || FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL)) return 4;
        FT_Bitmap *b = &face->glyph->bitmap;
        unsigned channels = b->pixel_mode == FT_PIXEL_MODE_BGRA ? 4 : 1;
        uint32_t sum = 0;
        for (unsigned y = 0; y < b->rows; ++y) {
            unsigned char *p = b->buffer + (long)y * b->pitch;
            unsigned n = b->pixel_mode == FT_PIXEL_MODE_MONO ? (b->width + 7) / 8 : b->width * channels;
            for (unsigned x = 0; x < n; ++x) sum = (sum * 33 + p[x]) & 0x7fffffff;
        }
        printf("%s[%u,%u,%d,%d,%d,%d,%u,%u,%d,%d,%u,%u]", i ? "," : "",
               info[i].codepoint, info[i].cluster,
               position[i].x_advance * px / raster, position[i].y_advance * px / raster,
               position[i].x_offset * px / raster, position[i].y_offset * px / raster,
               b->width, b->rows, face->glyph->bitmap_left, face->glyph->bitmap_top, b->pixel_mode, sum);
    }
    puts("]}"); hb_buffer_destroy(buffer); hb_font_destroy(font);
    FT_Done_Face(face); FT_Done_FreeType(library); return 0;
}
