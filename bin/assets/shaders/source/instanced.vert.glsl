#version 460

layout(set=1, binding=0) uniform UBO {
	mat4 view;
	mat4 projection;
};

layout(location=0) in vec3 position;
struct ObjectData{
	mat4 model;
  vec4 color;
};

//all object matrices
layout(std140,set = 1, binding = 0) readonly buffer ObjectBuffer{
	ObjectData objects[];
} objectBuffer;

layout(location=0) out vec4 out_color;

void main() {
	gl_Position = projection * view * objectBuffer.objects[gl_BaseInstance].model  * vec4(position, 1.0);
	out_color = objectBuffer.objects[gl_BaseInstance].color;
}
