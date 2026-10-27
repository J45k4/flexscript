/* Independent public EGL oracle. Enumerates configs instead of choosing by ID. */
#include <EGL/egl.h>
#include <stdint.h>
#include <stdlib.h>
int oracle_egl_config(int64_t *out) {
    EGLDisplay display = eglGetCurrentDisplay();
    EGLContext context = eglGetCurrentContext();
    EGLSurface surface = eglGetCurrentSurface(EGL_DRAW);
    EGLint id = 0, count = 0;
    if (display == EGL_NO_DISPLAY || context == EGL_NO_CONTEXT || surface == EGL_NO_SURFACE ||
        !eglQueryContext(display, context, EGL_CONFIG_ID, &id) ||
        !eglGetConfigs(display, NULL, 0, &count) || count < 1 || count > 4096) return 0;
    EGLConfig *configs = calloc((size_t)count, sizeof(*configs));
    if (!configs) return 0;
    if (!eglGetConfigs(display, configs, count, &count)) { free(configs); return 0; }
    EGLConfig selected = NULL;
    for (int i = 0; i < count; ++i) {
        EGLint candidate = 0;
        if (eglGetConfigAttrib(display, configs[i], EGL_CONFIG_ID, &candidate) && candidate == id) selected = configs[i];
    }
    free(configs);
    if (!selected) return 0;
    const EGLint attrs[] = {EGL_CONFIG_ID, EGL_RED_SIZE, EGL_GREEN_SIZE, EGL_BLUE_SIZE,
        EGL_ALPHA_SIZE, EGL_DEPTH_SIZE, EGL_STENCIL_SIZE, EGL_BUFFER_SIZE,
        EGL_SAMPLE_BUFFERS, EGL_SAMPLES, EGL_SURFACE_TYPE, EGL_RENDERABLE_TYPE,
        EGL_NATIVE_VISUAL_ID, EGL_MIN_SWAP_INTERVAL, EGL_MAX_SWAP_INTERVAL, EGL_CONFIG_CAVEAT};
    int n = 0;
    for (unsigned i = 0; i < sizeof(attrs)/sizeof(attrs[0]); ++i) {
        EGLint value = 0;
        if (!eglGetConfigAttrib(display, selected, attrs[i], &value)) return 0;
        out[n++] = value;
    }
    const EGLint surface_attrs[] = {EGL_WIDTH, EGL_HEIGHT, EGL_RENDER_BUFFER, EGL_SWAP_BEHAVIOR, EGL_CONFIG_ID};
    for (unsigned i = 0; i < sizeof(surface_attrs)/sizeof(surface_attrs[0]); ++i) {
        EGLint value = 0;
        if (!eglQuerySurface(display, surface, surface_attrs[i], &value)) return 0;
        out[n++] = value;
    }
    EGLint api = 0;
    if (!eglQueryContext(display, context, EGL_CONTEXT_CLIENT_TYPE, &api)) return 0;
    out[n++] = api;
    return n == 22 && eglGetError() == EGL_SUCCESS;
}
