/* Independent SDL ABI oracle; no production C widget/layout implementation. */
#include "../gui/events.c"
#include <SDL2/SDL_syswm.h>
int ui_fixture_text(unsigned window, const char *text) {
    if (strlen(text) >= sizeof(pending[0].text.text) || write_at-read_at==128) return 0;
    SDL_Event event; memset(&event,0,sizeof(event)); event.type=SDL_TEXTINPUT;
    event.text.windowID=window; strcpy(event.text.text,text);
    pending[write_at++ % 128]=event; return 1;
}
int ui_fixture_native(SDL_Window *window,int x,int y,int send) {
    void *sdl=dlopen("libSDL2-2.0.so.0",RTLD_NOW), *x11=dlopen("libX11.so.6",RTLD_NOW);
    SDL_bool (*info_fn)(SDL_Window *,SDL_SysWMinfo *)=dlsym(sdl,"SDL_GetWindowWMInfo");
    SDL_SysWMinfo info; memset(&info,0,sizeof(info)); SDL_VERSION(&info.version);
    if (!info_fn || !info_fn(window,&info) || info.subsystem!=SDL_SYSWM_X11) return -1;
    Display *display=info.info.x11.display; Window native=info.info.x11.window;
    int (*sync_fn)(Display *,Bool)=dlsym(x11,"XSync");sync_fn(display,False);
    XWindowAttributes attr;
    int (*attributes)(Display *,Window,XWindowAttributes *)=dlsym(x11,"XGetWindowAttributes");
    int mapped=attributes(display,native,&attr) && attr.map_state==IsViewable;
    if (send && mapped) {
        void *xtest=dlopen("libXtst.so.6",RTLD_NOW);
        int (*focus)(Display *,Window,int,Time)=dlsym(x11,"XSetInputFocus");
        KeyCode (*code)(Display *,KeySym)=dlsym(x11,"XKeysymToKeycode");
        int (*key)(Display *,unsigned,Bool,unsigned long)=dlsym(xtest,"XTestFakeKeyEvent");
        int (*button)(Display *,unsigned,Bool,unsigned long)=dlsym(xtest,"XTestFakeButtonEvent");
        int (*warp)(Display *,Window,Window,int,int,unsigned,unsigned,int,int)=dlsym(x11,"XWarpPointer");
        if (!key || !button) return -2;
        focus(display,native,RevertToParent,CurrentTime);sync_fn(display,False);
        if (send==2) { key(display,code(display,'a'),True,0);key(display,code(display,'a'),False,0); }
        if (send==3) { warp(display,None,native,0,0,0,0,x,y);button(display,1,True,0);button(display,1,False,0); }
        sync_fn(display,False);
        dlclose(xtest);
    }
    dlclose(x11);dlclose(sdl);return mapped;
}
