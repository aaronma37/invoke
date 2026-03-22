#version 450
layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec3 in_color;

layout(location = 0) out vec3 v_normal;
layout(location = 1) out vec3 v_color;
layout(location = 2) out vec3 v_world_pos;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
} pc;

void main() {
    v_normal = in_normal;
    v_color = in_color;
    v_world_pos = in_pos;
    gl_Position = pc.mvp * vec4(in_pos, 1.0);
}
