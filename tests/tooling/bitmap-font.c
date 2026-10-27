/* Test-only independent FreeType metrics and unchanged scalable SDL_ttf oracle. */
#include <stdint.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <SDL_ttf.h>
#include <hb-ft.h>
int oracle_font_size(const char *path, int px, const char *text, int64_t *out, int native) {
    FT_Library library = NULL;
    FT_Face face = NULL;
    if (FT_Init_FreeType(&library)) return 0;
    if (FT_New_Face(library, path, 0, &face)) { FT_Done_FreeType(library); return 0; }
    int okay = 1;
    out[4] = face->num_fixed_sizes;
    out[5] = FT_IS_SCALABLE(face) != 0;
    if (FT_IS_SCALABLE(face) && native) {
        if (FT_Set_Pixel_Sizes(face, 0, px)) okay = 0;
        else {
            hb_font_t *font = hb_ft_font_create_referenced(face);
            hb_ft_font_set_load_flags(font, FT_LOAD_COLOR);
            hb_buffer_t *buffer = hb_buffer_create();
            hb_buffer_add_utf8(buffer, text, -1, 0, -1);
            hb_buffer_guess_segment_properties(buffer);
            hb_shape(font, buffer, NULL, 0);
            unsigned count = 0;
            hb_glyph_position_t *positions = hb_buffer_get_glyph_positions(buffer, &count);
            long advance = 0;
            for (unsigned i = 0; i < count; ++i) advance += positions[i].x_advance;
            out[0] = (face->size->metrics.height + 63) / 64;
            out[1] = (face->size->metrics.ascender + 63) / 64;
            out[2] = (advance + 63) / 64; out[3] = px;
            hb_buffer_destroy(buffer); hb_font_destroy(font);
        }
    } else if (FT_IS_SCALABLE(face)) {
        /* Only the SDL case uses an already-loaded SDL_ttf. Do not introduce
           SDL into a native fixture through the independent test library. */
        void *ttf = dlopen("libSDL2_ttf-2.0.so.0", RTLD_NOW | RTLD_NOLOAD);
        if (!ttf) okay = 0;
        else {
            TTF_Font *(*open_font)(const char *, int) = dlsym(ttf, "TTF_OpenFont");
            void (*close_font)(TTF_Font *) = dlsym(ttf, "TTF_CloseFont");
            int (*size_font)(TTF_Font *, const char *, int *, int *) = dlsym(ttf, "TTF_SizeUTF8");
            int (*height_font)(const TTF_Font *) = dlsym(ttf, "TTF_FontHeight");
            int (*ascent_font)(const TTF_Font *) = dlsym(ttf, "TTF_FontAscent");
            if (!open_font || !close_font || !size_font || !height_font || !ascent_font) okay = 0;
            else {
                TTF_Font *font = open_font(path, px);
                int width = 0, height = 0;
                if (!font) okay = 0;
                else {
                    okay = size_font(font, text, &width, &height) == 0;
                    out[0] = height_font(font); out[1] = ascent_font(font);
                    out[2] = width; out[3] = px;
                    close_font(font);
                }
            }
            dlclose(ttf);
        }
    } else {
        long distance = 0x7fffffff;
        int best = -1;
        for (int i = 0; i < face->num_fixed_sizes; ++i) {
            long d = labs(face->available_sizes[i].y_ppem - px * 64L);
            if (d < distance) { best = i; distance = d; }
        }
        if (best < 0 || FT_Select_Size(face, best) ||
            FT_Load_Char(face, 0x1f44b, FT_LOAD_COLOR)) okay = 0;
        else {
            long raster = face->size->metrics.y_ppem;
            out[0] = (face->size->metrics.height * px / raster + 63) / 64;
            out[1] = (face->size->metrics.ascender * px / raster + 63) / 64;
            out[2] = (face->glyph->advance.x * px / raster + 63) / 64;
            out[3] = raster;
        }
    }
    FT_Done_Face(face); FT_Done_FreeType(library);
    return okay;
}
