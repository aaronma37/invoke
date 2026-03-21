#version 450
layout(location = 0) in vec3 inPos;
layout(location = 1) in float inSdf;
layout(location = 2) in vec3 inColor;

layout(location = 0) out vec3 outColor;

layout(push_constant) uniform PC {
    mat4 mvp;
    float threshold;
} pc;

void main() {
    gl_Position = pc.mvp * vec4(inPos, 1.0);
    gl_PointSize = 2.0;

    // Use GREEN for surface points (exactly 0 or very close)
    if (abs(inSdf) < 0.001) {
        outColor = vec3(0.0, 1.0, 0.0); // Neon Green
    } else if (inSdf > 0.0) {
        outColor = vec3(0.0, 0.0, 1.0); // Blue Outside
    } else {
        outColor = vec3(1.0, 0.0, 0.0); // Red Inside
    }
}
