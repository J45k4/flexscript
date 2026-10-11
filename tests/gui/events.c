/* Independent test-only ABI oracle. Production is entirely Flexscript. */
#include <SDL2/SDL.h>
#include <dlfcn.h>
#include <string.h>
#include <X11/Xlib.h>
#include <stdint.h>

/* Test-only helpers for the nine-argument Xlib calls, outside integer FFI's
 * six-argument surface. They let acceptance restore the desktop pointer. */
uint64_t gui_fixture_pointer(Display *display, Window root) {
    void *x11 = dlopen("libX11.so.6", RTLD_NOW);
    Bool (*query)(Display *, Window, Window *, Window *, int *, int *, int *, int *, unsigned *) = dlsym(x11, "XQueryPointer");
    Window returned_root, child; int x=0, y=0, local_x, local_y; unsigned mask;
    query(display, root, &returned_root, &child, &x, &y, &local_x, &local_y, &mask);
    dlclose(x11);
    return ((uint64_t)(uint32_t)y << 32) | (uint32_t)x;
}
int gui_fixture_warp(Display *display, Window destination, int x, int y) {
    void *x11 = dlopen("libX11.so.6", RTLD_NOW);
    int (*warp)(Display *, Window, Window, int, int, unsigned, unsigned, int, int) = dlsym(x11, "XWarpPointer");
    int result = warp(display, None, destination, 0, 0, 0, 0, x, y);
    dlclose(x11); return result;
}

/* Feed native SDL_Event structures directly to the decoder. SDL2 compatibility
 * layers do not consistently support SDL_PushEvent for text/drop events. */
static SDL_Event pending[128];
static unsigned read_at, write_at;
int gui_fixture_poll(SDL_Event *event) {
    if (read_at == write_at) return 0;
    *event = pending[read_at++ % 128];
    return 1;
}

int gui_fixture_event(int kind, unsigned window, int a, int b, int c, int d) {
    void *sdl = dlopen("libSDL2-2.0.so.0", RTLD_NOW);
    if (!sdl) return -2;
    void *(*allocate)(size_t) = dlsym(sdl, "SDL_malloc");
    if (!allocate || write_at - read_at == 128) { dlclose(sdl); return -3; }
    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = kind;
    switch (kind) {
    case SDL_WINDOWEVENT:
        event.window.windowID = window;
        event.window.event = a;
        event.window.data1 = b;
        event.window.data2 = c;
        break;
    case SDL_KEYDOWN: case SDL_KEYUP:
        event.key.windowID = window;
        event.key.keysym.scancode = a;
        event.key.keysym.sym = b;
        event.key.keysym.mod = c;
        event.key.repeat = d;
        break;
    case SDL_TEXTINPUT:
        event.text.windowID = window;
        memcpy(event.text.text, "\xe4\xbd\xa0\xe5\xa5\xbd", 7);
        break;
    case SDL_MOUSEMOTION:
        event.motion.windowID = window;
        event.motion.state = SDL_BUTTON_LMASK;
        event.motion.x = a; event.motion.y = b;
        event.motion.xrel = c; event.motion.yrel = d;
        break;
    case SDL_MOUSEBUTTONDOWN: case SDL_MOUSEBUTTONUP:
        event.button.windowID = window;
        event.button.button = a;
        event.button.x = b; event.button.y = c;
        break;
    case SDL_MOUSEWHEEL:
        event.wheel.windowID = window;
        event.wheel.x = a; event.wheel.y = b;
        event.wheel.direction = c;
        break;
    case SDL_DROPFILE: case SDL_DROPTEXT:
        event.drop.windowID = window;
        event.drop.file = allocate(8);
        memcpy(event.drop.file, "ignored", 8);
        break;
    case SDL_TEXTEDITING_EXT:
        event.editExt.windowID = window;
        event.editExt.text = allocate(8);
        memcpy(event.editExt.text, "ignored", 8);
        break;
    }
    pending[write_at++ % 128] = event;
    dlclose(sdl);
    return 1;
}
