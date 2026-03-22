#version 450
layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec3 v_color;
layout(location = 2) in vec3 v_world_pos;

layout(location = 0) out vec4 out_color;

void main() {
    vec3 light_dir = normalize(vec3(1.0, 1.0, 1.0));
    float diff = max(dot(normalize(v_normal), light_dir), 0.0);
    vec3 ambient = 0.2 * v_color;
    vec3 diffuse = 0.8 * diff * v_color;
    
    // Grid floor pattern based on world pos (optional flair)
    // float grid = 1.0;
    // if (abs(v_world_pos.y) < 0.01) {
    //     grid = (mod(v_world_pos.x, 1.0) < 0.02 || mod(v_world_pos.z, 1.0) < 0.02) ? 0.5 : 1.0;
    // }

    out_color = vec4(ambient + diffuse, 1.0);
}
