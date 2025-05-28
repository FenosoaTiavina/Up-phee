#version 460 core

struct ObjectData{
  mat4 model;
  vec4 color;
};

layout(set = 0, binding = 0) buffer ObjectBuffer {
    ObjectData objects[];
} objectBuffer;


layout(set = 1, binding = 0) uniform ViewProj {
    mat4 view;
    mat4 projection;
};

layout(location=0) in vec3 position;

layout(location=0) out vec4 out_color;

void main() {
	gl_Position = projection * view *
    objectBuffer.objects[gl_InstanceIndex].model *
    vec4(position, 1.0);
	out_color = objectBuffer.objects[gl_InstanceIndex].color;
}
