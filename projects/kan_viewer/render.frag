#version 450
layout(location = 0) in vec3 inNormal;
layout(location = 1) in vec3 inColor;
layout(location = 2) in vec3 inViewVec;

layout(location = 0) out vec4 outColor;

void main() {
    vec3 N = normalize(inNormal);
    vec3 L = normalize(vec3(1.0, 1.0, 1.0));
    vec3 V = normalize(-inViewVec);
    vec3 R = reflect(-L, N);

    float diff = max(dot(N, L), 0.0);
    float spec = pow(max(dot(R, V), 0.0), 32.0);
    
    vec3 ambient = vec3(0.1) * inColor;
    vec3 diffuse = diff * inColor;
    vec3 specular = vec3(0.5) * spec;

    outColor = vec4(ambient + diffuse + specular, 1.0);
}
