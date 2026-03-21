#version 450
layout(location = 0) in vec3 inPos;
layout(location = 1) in float inSdf;
layout(location = 2) in vec3 inColor;

layout(location = 0) out vec3 outColor;

layout(push_constant) uniform PC {
    mat4 mvp;
    float threshold;
    float padding[3];
} pc;

void main() {
    if (abs(inSdf) > pc.threshold) {
        gl_Position = vec4(2.0, 2.0, 2.0, 1.0); // Move off-screen
    } else {
        gl_Position = pc.mvp * vec4(inPos, 1.0);
    }
    gl_PointSize = 2.0;
    
    // Color by SDF: White at 0 (surface), Blue for outside, Red for inside (if signed)
    if (abs(inSdf) < 0.01) {
        outColor = vec3(1.0);
    } else if (inSdf > 0.0) {
        outColor = vec3(0.2, 0.4, 1.0) * (1.0 - clamp(inSdf * 2.0, 0.0, 0.8));
    } else {
        outColor = vec3(1.0, 0.2, 0.2);
    }
}
