import re

NEW_BODY = """float evaluate_kan_sdf(vec3 p) {
    const float h = 2.0 / 13.0;
    float box = max(max(abs(p.x), abs(p.y)), abs(p.z));
    float fade = smoothstep(1.1, 1.0, box);
    vec3 x = clamp(p, vec3(-1.0), vec3(1.0));
    
    // --- Layer 1 Pre-calculation ---
    float l1_silu[3];
    float l1_b_vals[3][4];
    int l1_k_idx[3][4];
    
    for (int i=0; i<3; i++) {
        float val = (i == 0) ? x.x : (i == 1 ? x.y : x.z);
        l1_silu[i] = (val / (1.0 + exp(-val))) * fade;
        float t_val = (val + 1.0) / h + 3.0;
        int k_base = int(floor(t_val));
        for (int a=0; a<4; a++) {
            int k = k_base - 3 + a;
            if (k >= 0 && k < 16) {
                float knots_k = (float(k) - 3.0) * h - 1.0;
                l1_b_vals[i][a] = kan_basis((val - knots_k) / h);
                l1_k_idx[i][a] = k;
            } else {
                l1_b_vals[i][a] = 0.0;
                l1_k_idx[i][a] = -1;
            }
        }
    }

    // --- Layer 1 FMA Accumulation ---
    float hidden1[32];
    for (int j=0; j<32; j++) hidden1[j] = 0.0;
    
    for (int i=0; i<3; i++) {
        float s = l1_silu[i];
        for (int j=0; j<32; j++) hidden1[j] += s;
        for (int a=0; a<4; a++) {
            int k = l1_k_idx[i][a];
            if (k >= 0) {
                float b = l1_b_vals[i][a];
                int coeff_offset = (i * 16 * 32) + (k * 32);
                for (int j=0; j<32; j++) {
                    hidden1[j] += b * kan.coeffs[coeff_offset + j];
                }
            }
        }
    }

    // --- Layer 2 Pre-calculation ---
    uint l2_offset = 3 * 16 * 32;
    float l2_silu[32];
    float l2_b_vals[32][4];
    int l2_k_idx[32][4];
    
    for (int i=0; i<32; i++) {
        float val = hidden1[i];
        l2_silu[i] = (val / (1.0 + exp(-val)));
        float t_val = (val + 1.0) / h + 3.0;
        int k_base = int(floor(t_val));
        for (int a=0; a<4; a++) {
            int k = k_base - 3 + a;
            if (k >= 0 && k < 16) {
                float knots_k = (float(k) - 3.0) * h - 1.0;
                l2_b_vals[i][a] = kan_basis((val - knots_k) / h);
                l2_k_idx[i][a] = k;
            } else {
                l2_b_vals[i][a] = 0.0;
                l2_k_idx[i][a] = -1;
            }
        }
    }

    // --- Layer 2 FMA Accumulation ---
    float hidden2[32];
    for (int j=0; j<32; j++) hidden2[j] = 0.0;

    for (int i=0; i<32; i++) {
        float s = l2_silu[i];
        for (int j=0; j<32; j++) hidden2[j] += s;
        for (int a=0; a<4; a++) {
            int k = l2_k_idx[i][a];
            if (k >= 0) {
                float b = l2_b_vals[i][a];
                int coeff_offset = l2_offset + (i * 16 * 32) + (k * 32);
                for (int j=0; j<32; j++) {
                    hidden2[j] += b * kan.coeffs[coeff_offset + j];
                }
            }
        }
    }

    // --- Layer 3 Pre-calculation & Accumulation ---
    uint l3_offset = l2_offset + (32 * 16 * 32);
    float final_sdf = 0.0;
    
    float l3_silu[32];
    float l3_b_vals[32][4];
    int l3_k_idx[32][4];

    for (int i=0; i<32; i++) {
        float val = hidden2[i];
        l3_silu[i] = (val / (1.0 + exp(-val)));
        float t_val = (val + 1.0) / h + 3.0;
        int k_base = int(floor(t_val));
        for (int a=0; a<4; a++) {
            int k = k_base - 3 + a;
            if (k >= 0 && k < 16) {
                float knots_k = (float(k) - 3.0) * h - 1.0;
                l3_b_vals[i][a] = kan_basis((val - knots_k) / h);
                l3_k_idx[i][a] = k;
            } else {
                l3_b_vals[i][a] = 0.0;
                l3_k_idx[i][a] = -1;
            }
        }
    }

    for (int i=0; i<32; i++) {
        final_sdf += l3_silu[i];
        for (int a=0; a<4; a++) {
            int k = l3_k_idx[i][a];
            if (k >= 0) {
                final_sdf += l3_b_vals[i][a] * kan.coeffs[l3_offset + (i * 16 * 1) + (k * 1) + 0];
            }
        }
    }
"""

def process_file(filepath, ret_stmt):
    with open(filepath, 'r') as f:
        content = f.read()

    # Find float evaluate_kan_sdf(vec3 p) { ... }
    pattern = r"float evaluate_kan_sdf\(vec3 p\)\s*\{.*?(return .*?;)\s*\}"
    
    def replacer(match):
        ret = match.group(1)
        # return final_sdf ...
        return NEW_BODY + "    " + ret + "\n}"

    new_content = re.sub(pattern, replacer, content, flags=re.DOTALL)
    
    with open(filepath, 'w') as f:
        f.write(new_content)

process_file("projects/kan_viewer/render.comp", "return final_sdf;")
process_file("projects/kan_viewer/slice.comp", "return final_sdf + pc.bias;")
process_file("projects/kan_viewer/field.comp", "return final_sdf + pc.grid_bias;")
