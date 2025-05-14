#version 460

layout(set=1, binding=0) uniform UBO {
	mat4 model;
	mat4 view;
	mat4 projection;
};

layout(location=0) in vec3 position;
layout(location=1) in vec4 uv;

layout(location=0) out vec4 out_color;
layout(location=1) out vec2 out_uv;

void main() {
	gl_Position = projection * view * model  * vec4(position, 1);
	out_color = vec4(position , 1.0);
	out_uv = uv;
}
