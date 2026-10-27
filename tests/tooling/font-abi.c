/* Independent Linux LP64 ABI oracle; never linked into the application. */
#include <stddef.h>
#include <stdio.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <hb.h>
#define FIELD(t, f) printf("%s.%s=%zu\n", #t, #f, offsetof(t, f))
int main(void) {
    FIELD(FT_FaceRec, face_flags); FIELD(FT_FaceRec, num_fixed_sizes);
    FIELD(FT_FaceRec, available_sizes); FIELD(FT_FaceRec, glyph);
    FIELD(FT_FaceRec, size); FIELD(FT_SizeRec, metrics);
    FIELD(FT_Size_Metrics, y_ppem); FIELD(FT_Size_Metrics, ascender);
    FIELD(FT_Size_Metrics, descender); FIELD(FT_Size_Metrics, height);
    FIELD(FT_Bitmap_Size, y_ppem); printf("FT_Bitmap_Size.sizeof=%zu\n", sizeof(FT_Bitmap_Size));
    FIELD(FT_GlyphSlotRec, bitmap); FIELD(FT_GlyphSlotRec, bitmap_left);
    FIELD(FT_GlyphSlotRec, bitmap_top); FIELD(FT_Bitmap, rows);
    FIELD(FT_Bitmap, width); FIELD(FT_Bitmap, pitch); FIELD(FT_Bitmap, buffer);
    FIELD(FT_Bitmap, pixel_mode); FIELD(hb_glyph_info_t, cluster);
    FIELD(hb_glyph_position_t, x_advance); FIELD(hb_glyph_position_t, y_advance);
    FIELD(hb_glyph_position_t, x_offset); FIELD(hb_glyph_position_t, y_offset);
    printf("hb_glyph_info_t.sizeof=%zu\nhb_glyph_position_t.sizeof=%zu\n",
           sizeof(hb_glyph_info_t), sizeof(hb_glyph_position_t));
    return 0;
}
