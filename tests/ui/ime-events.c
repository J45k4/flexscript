/* Independent SDL event ABI producer for normalized IME tests only. */
#include "../gui/events.c"
int ime_fixture_preedit(unsigned window,const char *text,int start,int length,int extended) {
    void *sdl=dlopen("libSDL2-2.0.so.0",RTLD_NOW);
    if(!sdl)return 0;
    if(write_at-read_at==128){dlclose(sdl);return 0;}
    char *(*copy)(const char *)=dlsym(sdl,"SDL_strdup");
    void (*release)(void *)=dlsym(sdl,"SDL_free");
    SDL_Event event;memset(&event,0,sizeof event);char *owned=NULL;
    if(extended){
        if(!copy || !release){dlclose(sdl);return 0;}
        owned=copy(text);if(!owned){dlclose(sdl);return 0;}
        event.type=SDL_TEXTEDITING_EXT;event.editExt.windowID=window;
        event.editExt.text=owned;event.editExt.start=start;event.editExt.length=length;
    }else{
        if(strlen(text)>=sizeof event.edit.text){dlclose(sdl);return 0;}
        event.type=SDL_TEXTEDITING;event.edit.windowID=window;
        strcpy(event.edit.text,text);event.edit.start=start;event.edit.length=length;
    }
    pending[write_at++ % 128]=event;
    dlclose(sdl);return 1;
}
