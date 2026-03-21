#version 450
layout(location = 0) in vec3 inPos;
layout(location = 1) in float inSdf;
layout(location = 2) in vec3 inColor;

layout(location = 0) out vec3 outColor;

layout(push_constant) uniform PC {
    mat4 mvp;
    float threshold;
    float is_aabb;
    float discard_blue; // 1.0 = hide blue, 0.0 = show all
} pc;

void main() {
    gl_Position = pc.mvp * vec4(inPos, 1.0);
    gl_PointSize = 2.0;

    // Discard Blue Logic (Move off-screen)
    if (pc.is_aabb < 0.5 && pc.discard_blue > 0.5 && inSdf > 0.01) {
        gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
    }

    if (pc.is_aabb > 0.5) {
        outColor = vec3(0.3, 0.3, 0.4);
    } else if (abs(inSdf) < 0.01) {
        outColor = vec3(0.0, 1.0, 0.0); // Surface Green
    } else if (inSdf > 0.0) {
        outColor = vec3(0.0, 0.0, 1.0); // Outside Blue
    } else {
        outColor = vec3(1.0, 0.0, 0.0); // Inside Red
    }
}
