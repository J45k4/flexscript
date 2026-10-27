/* Independent driver state oracle, never application implementation. */
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glext.h>
#include <stdint.h>
int oracle_renderer_state(const uint32_t *expected) {
    GLint value = 0, viewport[2] = {0,0};
    glGetIntegerv(GL_CURRENT_PROGRAM, &value);
    if ((uint32_t)value != expected[0]) return 0;
    glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &value);
    if ((uint32_t)value != expected[1]) return 0;
    glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &value);
    if ((uint32_t)value != expected[2]) return 0;
    glGetIntegerv(GL_ACTIVE_TEXTURE, &value);
    if (value != GL_TEXTURE0) return 0;
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &value);
    if ((uint32_t)value != expected[3]) return 0;
    glGetUniformiv(expected[0], glGetUniformLocation(expected[0], "uTexture"), &value);
    if (value != 0) return 0;
    glGetUniformiv(expected[0], glGetUniformLocation(expected[0], "uViewport"), viewport);
    return viewport[0] == (GLint)expected[4] && viewport[1] == (GLint)expected[5] && glGetError() == GL_NO_ERROR;
}
