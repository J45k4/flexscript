#include <stddef.h>
#include <stdio.h>
#include <libdrm/drm.h>

#define CHECK(value, expected) _Static_assert((value) == (expected), #value)
CHECK(DRM_IOCTL_VERSION, 0xc0406400UL);
CHECK(DRM_IOCTL_GET_CAP, 0xc010640cUL);
CHECK(DRM_IOCTL_MODE_GETRESOURCES, 0xc04064a0UL);
CHECK(DRM_IOCTL_MODE_GETCONNECTOR, 0xc05064a7UL);
CHECK(DRM_IOCTL_MODE_CREATE_DUMB, 0xc02064b2UL);
CHECK(DRM_IOCTL_MODE_MAP_DUMB, 0xc01064b3UL);
CHECK(DRM_IOCTL_PRIME_HANDLE_TO_FD, 0xc00c642dUL);
CHECK(DRM_IOCTL_PRIME_FD_TO_HANDLE, 0xc00c642eUL);
CHECK(DRM_IOCTL_GEM_CLOSE, 0x40086409UL);
CHECK(DRM_IOCTL_MODE_ADDFB2, 0xc06864b8UL);
CHECK(DRM_IOCTL_MODE_SETCRTC, 0xc06864a2UL);
CHECK(DRM_IOCTL_MODE_GETCRTC, 0xc06864a1UL);
CHECK(DRM_IOCTL_MODE_DIRTYFB, 0xc01864b1UL);
CHECK(sizeof(struct drm_mode_modeinfo), 68);
CHECK(offsetof(struct drm_mode_modeinfo, hdisplay), 4);
CHECK(offsetof(struct drm_mode_modeinfo, vdisplay), 14);
CHECK(offsetof(struct drm_mode_card_res, count_fbs), 32);
CHECK(offsetof(struct drm_mode_card_res, count_encoders), 44);
CHECK(offsetof(struct drm_mode_get_connector, modes_ptr), 8);
CHECK(offsetof(struct drm_mode_get_connector, count_modes), 32);
CHECK(offsetof(struct drm_mode_get_connector, count_props), 36);
CHECK(offsetof(struct drm_mode_get_connector, count_encoders), 40);
CHECK(offsetof(struct drm_mode_get_connector, connector_id), 48);
CHECK(offsetof(struct drm_mode_create_dumb, handle), 16);
CHECK(offsetof(struct drm_mode_create_dumb, pitch), 20);
CHECK(offsetof(struct drm_mode_create_dumb, size), 24);
CHECK(offsetof(struct drm_mode_map_dumb, offset), 8);
CHECK(offsetof(struct drm_prime_handle, fd), 8);
CHECK(offsetof(struct drm_mode_fb_cmd2, handles), 20);
CHECK(offsetof(struct drm_mode_fb_cmd2, pitches), 36);
CHECK(offsetof(struct drm_mode_crtc, mode_valid), 32);
CHECK(offsetof(struct drm_mode_crtc, mode), 36);

int main(void) {
    puts("PASS: Linux DRM diagnostic ioctl values and structure offsets");
    return 0;
}
