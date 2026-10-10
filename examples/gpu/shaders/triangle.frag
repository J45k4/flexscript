#version 450 core
layout(binding=0) uniform sampler2D paint;
layout(location=0) out vec4 color;
void main() {color=texelFetch(paint,ivec2(0),0);}
