/* Test-only Finnish keymap producer and independent compose/client oracle. */
#include <stdio.h>
#include <stdlib.h>
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-compose.h>
static void text(struct xkb_state *s, struct xkb_compose_state *c, int key) {
    char out[64] = {0};
    xkb_compose_state_feed(c, xkb_state_key_get_one_sym(s, key + 8));
    enum xkb_compose_status status = xkb_compose_state_get_status(c);
    if (status == XKB_COMPOSE_COMPOSED) {
        xkb_compose_state_get_utf8(c, out, sizeof out); xkb_compose_state_reset(c);
    } else if (status == XKB_COMPOSE_NOTHING) xkb_state_key_get_utf8(s, key + 8, out, sizeof out);
    printf("\"%s\"", out);
}
int main(int argc, char **argv) {
    if (argc != 2) return 1;
    struct xkb_context *ctx = xkb_context_new(0);
    struct xkb_rule_names names = {.layout="fi"};
    struct xkb_keymap *map = xkb_keymap_new_from_names(ctx, &names, 0);
    if (!map) return 2;
    char *source = xkb_keymap_get_as_string(map, XKB_KEYMAP_FORMAT_TEXT_V1);
    FILE *file = fopen(argv[1], "w"); if (!file) return 3;
    fputs(source, file); fclose(file); free(source);
    struct xkb_state *state = xkb_state_new(map);
    struct xkb_compose_table *table = xkb_compose_table_new_from_locale(ctx, "C.UTF-8", 0);
    struct xkb_compose_state *compose = xkb_compose_state_new(table, 0);
    unsigned shift = 1u << xkb_keymap_mod_get_index(map, XKB_MOD_NAME_SHIFT);
    unsigned altgr = 1u << xkb_keymap_mod_get_index(map, "Mod5");
    printf("{\"shift_mask\":%u,\"altgr_mask\":%u,\"text\":[", shift, altgr);
    int keys[] = {30,39,40,26};
    for (unsigned i=0;i<4;++i) { if (i) putchar(','); text(state,compose,keys[i]); }
    xkb_state_update_mask(state,shift,0,0,0,0,0); putchar(','); text(state,compose,30);
    xkb_state_update_mask(state,altgr,0,0,0,0,0); putchar(','); text(state,compose,3);
    xkb_state_update_mask(state,0,0,0,0,0,0); putchar(','); text(state,compose,13); putchar(','); text(state,compose,30);
    puts("]}"); xkb_compose_state_unref(compose); xkb_compose_table_unref(table);
    xkb_state_unref(state); xkb_keymap_unref(map); xkb_context_unref(ctx); return 0;
}
