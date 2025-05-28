#version 460
// ViewProj uniform buffer (set 0, binding 0)
layout(set = 1, binding = 0) uniform ViewProj {
    mat4 view;
    mat4 projection;
};

layout(set = 0, binding = 0) readonly buffer ObjectBuffer {
    vec4 colors[];
} objectBuffer;


layout(location=0) in vec3 position;

layout(location=0) out vec4 out_color;

void main() {
	gl_Position = 
    projection * view *
     vec4(position.x + gl_InstanceIndex * 1.5 , position.y ,position.z,1.0);
	out_color = objectBuffer.colors[gl_InstanceIndex];
}
