#version 460

struct ObjectData {
    mat4 model;
    vec4 color;
};

// ViewProj uniform buffer (set 0, binding 0)
layout(set = 0, binding = 0) uniform ViewProj {
    mat4 view;
    mat4 projection;
};

// SSBO for object data (set 1, binding 0)
layout(set = 1, binding = 0) readonly buffer ObjectBuffer {
    ObjectData objects[];
} objectBuffer;

// Vertex input
layout(location = 0) in vec3 position;

// Output to fragment shader
layout(location = 0) out vec4 color;

void main() {
    // Use gl_InstanceIndex for proper instancing
    uint instanceIndex = gl_InstanceIndex;
    
    // Transform vertex position
    gl_Position = projection * view * objectBuffer.objects[instanceIndex].model * vec4(position, 1.0);
    
    // Pass color to fragment shader
    color = objectBuffer.objects[instanceIndex].color;
}
