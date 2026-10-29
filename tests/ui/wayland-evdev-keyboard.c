/* Private-test virtual keyboard with an ordinary evdev XKB keymap. */
#define _GNU_SOURCE
#include <errno.h>
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

static const struct wl_interface keyboard_interface;
static const struct wl_interface *create_types[] = {&wl_seat_interface, &keyboard_interface};
static const struct wl_message manager_requests[] = {{"create_virtual_keyboard", "on", create_types}};
static const struct wl_interface manager_interface = {
    "zwp_virtual_keyboard_manager_v1", 1, 1, manager_requests, 0, NULL
};
static const struct wl_message keyboard_requests[] = {
    {"keymap", "uhu", NULL}, {"key", "uuu", NULL},
    {"modifiers", "uuuu", NULL}, {"destroy", "", NULL}
};
static const struct wl_interface keyboard_interface = {
    "zwp_virtual_keyboard_v1", 1, 4, keyboard_requests, 0, NULL
};
static struct wl_seat *seat;
static struct wl_proxy *manager;

static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    (void)data;
    (void)version;
    if (!seat && !strcmp(interface, "wl_seat"))
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (!manager && !strcmp(interface, "zwp_virtual_keyboard_manager_v1"))
        manager = wl_registry_bind(registry, name, &manager_interface, 1);
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}
static const struct wl_registry_listener registry_listener = {global, global_remove};

static void send_state(struct wl_display *display, struct wl_proxy *keyboard, uint32_t key, uint32_t state) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now)) exit(1);
    uint32_t ms = (uint32_t)((uint64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000);
    wl_proxy_marshal_flags(keyboard, 1, NULL, 1, 0, ms, key, state);
    if (wl_display_flush(display) < 0 && errno != EAGAIN) exit(1);
}
static void send_key(struct wl_display *display, struct wl_proxy *keyboard, uint32_t key) {
    send_state(display, keyboard, key, 1);
    send_state(display, keyboard, key, 0);
}
static void send_control_key(struct wl_display *display, struct wl_proxy *keyboard, uint32_t key, uint32_t mask) {
    send_state(display, keyboard, KEY_LEFTCTRL, 1);
    wl_proxy_marshal_flags(keyboard, 2, NULL, 1, 0, mask, 0u, 0u, 0u);
    send_key(display, keyboard, key);
    send_state(display, keyboard, KEY_LEFTCTRL, 0);
    wl_proxy_marshal_flags(keyboard, 2, NULL, 1, 0, 0u, 0u, 0u, 0u);
    if (wl_display_flush(display) < 0 && errno != EAGAIN) exit(1);
}

int main(int argc, char **argv) {
    int words = argc == 2 && !strcmp(argv[1], "--word-navigation");
    if (argc > 2 || (argc == 2 && !words)) return 8;
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 1;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !seat || !manager) return 2;
    struct wl_proxy *keyboard = wl_proxy_marshal_flags(manager, 0, &keyboard_interface, 1, 0, seat, NULL);
    if (!keyboard) return 3;
    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_rule_names names = {.rules = "evdev", .model = "pc105", .layout = "us"};
    struct xkb_keymap *keymap = context ? xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS) : NULL;
    char *text = keymap ? xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1) : NULL;
    if (!text) return 4;
    xkb_mod_index_t control = xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_CTRL);
    if (control == XKB_MOD_INVALID || control >= 32) return 9;
    uint32_t control_mask = 1u << control;
    size_t length = strlen(text) + 1;
    int fd = memfd_create("collie-test-keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, text, length) != (ssize_t)length || lseek(fd, 0, SEEK_SET) < 0) return 5;
    wl_proxy_marshal_flags(keyboard, 0, NULL, 1, 0, 1, fd, (uint32_t)length);
    close(fd);
    free(text);
    xkb_keymap_unref(keymap);
    xkb_context_unref(context);
    if (wl_display_roundtrip(display) < 0) return 6;
    usleep(250000); /* Let the private compositor deliver the keymap first. */
    if (words) {
        const uint32_t initial[] = {KEY_E, KEY_C, KEY_H, KEY_O, KEY_SPACE,
            KEY_A, KEY_L, KEY_P, KEY_H, KEY_A, KEY_SPACE,
            KEY_B, KEY_E, KEY_T, KEY_A, KEY_SPACE,
            KEY_G, KEY_A, KEY_M, KEY_M, KEY_A};
        for (size_t i = 0; i < sizeof(initial) / sizeof(initial[0]); ++i) {
            send_key(display, keyboard, initial[i]);
            usleep(50000);
        }
        usleep(180000); send_control_key(display, keyboard, KEY_LEFT, control_mask);
        usleep(180000); send_control_key(display, keyboard, KEY_LEFT, control_mask);
        usleep(180000); send_control_key(display, keyboard, KEY_RIGHT, control_mask);
        usleep(180000); send_control_key(display, keyboard, KEY_RIGHT, control_mask);
        usleep(180000); send_control_key(display, keyboard, KEY_LEFT, control_mask);
        usleep(180000); send_key(display, keyboard, KEY_N);
        usleep(60000); send_key(display, keyboard, KEY_E);
        usleep(60000); send_key(display, keyboard, KEY_W);
        usleep(180000); send_key(display, keyboard, KEY_ENTER);
    } else {
        const uint32_t initial[] = {KEY_E, KEY_C, KEY_H, KEY_O, KEY_SPACE, KEY_A, KEY_C};
        for (size_t i = 0; i < sizeof(initial) / sizeof(initial[0]); ++i) {
            send_key(display, keyboard, initial[i]);
            usleep(60000);
        }
        usleep(180000); send_key(display, keyboard, KEY_LEFT);
        usleep(180000); send_key(display, keyboard, KEY_B);
        usleep(180000); send_key(display, keyboard, KEY_RIGHT);
        usleep(180000); send_key(display, keyboard, KEY_D);
        usleep(180000); send_key(display, keyboard, KEY_ENTER);
    }
    if (wl_display_roundtrip(display) < 0) return 7;
    wl_proxy_marshal_flags(keyboard, 3, NULL, 1, WL_MARSHAL_FLAG_DESTROY);
    wl_proxy_destroy(manager);
    wl_seat_destroy(seat);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    return 0;
}
