/* Independent system-header ABI checks; never part of the application. */
#include <stddef.h>
#include <wayland-cursor.h>
_Static_assert(sizeof(void *)==8,"The native backend targets LP64");
_Static_assert(sizeof(struct wl_cursor)==24,"wl_cursor size");
_Static_assert(offsetof(struct wl_cursor,image_count)==0,"image_count offset");
_Static_assert(offsetof(struct wl_cursor,images)==8,"images offset");
_Static_assert(sizeof(struct wl_cursor_image)==20,"wl_cursor_image size");
_Static_assert(offsetof(struct wl_cursor_image,width)==0,"width offset");
_Static_assert(offsetof(struct wl_cursor_image,height)==4,"height offset");
_Static_assert(offsetof(struct wl_cursor_image,hotspot_x)==8,"hotspot_x offset");
_Static_assert(offsetof(struct wl_cursor_image,hotspot_y)==12,"hotspot_y offset");
_Static_assert(offsetof(struct wl_cursor_image,delay)==16,"delay offset");
int main(void){return 0;}
