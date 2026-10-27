/* Independent public SDL/Wayland ABI oracle. Not application/library code. */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <SDL2/SDL.h>
#include <SDL2/SDL_syswm.h>
#include <wayland-client.h>
int observer_fields(SDL_Window *window,uint64_t *out) {
    SDL_SysWMinfo info;SDL_VERSION(&info.version);
    if(!SDL_GetWindowWMInfo(window,&info) || info.subsystem!=SDL_SYSWM_WAYLAND)return 0;
    out[0]=(uintptr_t)info.info.wl.display;out[1]=(uintptr_t)info.info.wl.surface;
    out[2]=wl_display_get_fd(info.info.wl.display);return 1;
}
int observer_push(SDL_Window *window) {
    SDL_Event e={0};e.type=SDL_KEYDOWN;e.key.windowID=SDL_GetWindowID(window);
    e.key.keysym.scancode=SDL_SCANCODE_F6;return SDL_PushEvent(&e);
}
#ifdef SDL_OBSERVER_MAIN
int main(void) {
    printf("%zu %zu %zu %zu %d\n",sizeof(SDL_SysWMinfo),
        offsetof(SDL_SysWMinfo,subsystem),offsetof(SDL_SysWMinfo,info.wl.display),
        offsetof(SDL_SysWMinfo,info.wl.surface),SDL_SYSWM_WAYLAND);return 0;
}
#endif
