#version 460

layout(set=1, binding=0) uniform UBO {
	mat4 view;
	mat4 projection;
};

layout(location=0) in vec3 position;

layout(location=0) out vec4 out_color;

void main() {
	gl_Position = projection * view * vec4(position.x + gl_InstanceIndex ,
                                        position.y , position.z, 1.0);
	out_color = vec4( position.r,position.g ,gl_InstanceIndex , 1.0);
}
