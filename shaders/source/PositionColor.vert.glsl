#version 450
layout(location = 0) in vec3 inPosition;  // x, y, z
layout(location = 1) in vec4 inColor;     // r, g, b, a

layout(location = 0) out vec4 fragColor;

void main() {
    gl_Position = vec4(inPosition, 1.0);
    fragColor = inColor;
}
