#version 450
layout(location = 0) in vec4 inPos;
layout(location = 1) in vec4 inNormal;
layout(location = 2) in vec4 inColor;

layout(location = 0) out vec3 outNormal;
layout(location = 1) out vec3 outColor;
layout(location = 2) out vec3 outViewVec;

layout(push_constant) uniform PC {
    mat4 mvp;
    mat4 model;
} pc;

void main() {
    gl_Position = pc.mvp * inPos;
    outNormal = mat3(pc.model) * inNormal.xyz;
    outColor = inColor.rgb;
    outViewVec = (pc.model * inPos).xyz;
}
