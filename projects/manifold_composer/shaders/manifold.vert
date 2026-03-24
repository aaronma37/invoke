#version 450

layout(location = 0) in vec3 inPos;

layout(push_constant) uniform PushConstants {
    mat4 viewProj;
} pc;

void main() {
    gl_Position = pc.viewProj * vec4(inPos, 1.0);
    gl_PointSize = 4.0;
}
