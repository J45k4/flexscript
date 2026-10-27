/* Test-only oracle, linked with wayland-scanner's independent metadata. */
#include <ctype.h>
#include <stddef.h>
#include <stdio.h>
#include <wayland-client.h>
#include <wayland-cursor.h>
static void messages(const struct wl_message *m,int count) {
    putchar('[');
    for(int i=0;i<count;i++) {
        printf("%s{\"name\":\"%s\",\"signature\":\"%s\",\"types\":[",i?",":"",m[i].name,m[i].signature);
        int n=0;const char *s=m[i].signature;
        while(*s){if(!isdigit((unsigned char)*s) && *s!='?')n++;s++;}
        for(int j=0;j<n;j++)printf("%s\"%s\"",j?",":"",m[i].types && m[i].types[j]?m[i].types[j]->name:"");
        printf("]}");
    }
    putchar(']');
}
static void interface(const struct wl_interface *p) {
    printf("{\"name\":\"%s\",\"version\":%d,\"requests\":",p->name,p->version);
    messages(p->methods,p->method_count);printf(",\"events\":");messages(p->events,p->event_count);putchar('}');
}
/* The driver appends declarations and main for the canonical protocol XML. */
