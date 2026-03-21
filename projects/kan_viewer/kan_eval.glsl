// Moontide KAN GPU Evaluator (GLSL)
// Optimized for Real-time Raymarching

float kan_basis(float t) {
    if (t < 0.0 || t >= 4.0) return 0.0;
    if (t < 1.0) return 0.16666667 * t * t * t;
    if (t < 2.0) { float t1 = t - 1.0; return 0.16666667 * (-3.0 * t1 * t1 * t1 + 3.0 * t1 * t1 + 3.0 * t1 + 1.0); }
    if (t < 3.0) { float t2 = t - 2.0; return 0.16666667 * (3.0 * t2 * t2 * t2 - 6.0 * t2 * t2 + 4.0); }
    float t3 = t - 3.0; return 0.16666667 * (1.0 - t3) * (1.0 - t3) * (1.0 - t3);
}

struct KanLayerMeta {
    uint in_dim;
    uint out_dim;
    uint num_coeffs;
};

// Coefficients are stored in a flat float array
layout(set = 0, binding = 0) buffer KanWeights { float coeffs[]; } kan;

float evaluate_kan_sdf(vec3 p) {
    // Current implementation assumes fixed 3 -> 32 -> 32 -> 1 architecture for simplicity
    // Points are in range [-1, 1], shifted to [0, 1] for knots
    vec3 x = (p + 1.0) * 0.5;
    
    // Layer 1 (3 -> 32)
    float hidden1[32];
    for(int j=0; j<32; j++) {
        float sum = 0.0;
        for(int i=0; i<3; i++) {
            float val = (i == 0) ? x.x : (i == 1 ? x.y : x.z);
            // SiLU
            sum += val / (1.0 + exp(-val));
            // Spline
            float h = 1.0 / 7.0; // Assuming 8 knots for 4 coeffs
            float t = val / h;
            int k_base = int(floor(t));
            for(int k=k_base-3; k<=k_base; k++) {
                if(k < 0 || k >= 4) continue;
                float b = kan_basis((val - float(k)*h)/h);
                // Coeff indexing: (i * num_coeffs + k) * out_dim + j
                sum += b * kan.coeffs[(i * 4 + k) * 32 + j];
            }
        }
        hidden1[j] = sum;
    }

    // Layer 2 (32 -> 1)
    float final_sdf = 0.0;
    for(int i=0; i<32; i++) {
        float val = hidden1[i];
        final_sdf += val / (1.0 + exp(-val));
        // ... second layer splines ...
    }

    return final_sdf;
}
