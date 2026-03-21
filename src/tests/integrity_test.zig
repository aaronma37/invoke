const std = @import("std");
const kan_layer = @import("../core/kan_layer.zig");
const kan_spline = @import("../core/kan_spline.zig");

/// Naive scalar implementation of the KAN Forward pass for parity checking.
fn naiveForward(layer: kan_layer.KanLayer, inputs: []const f32, outputs: []f32, batch_size: usize) void {
    @memset(outputs, 0.0);
    
    const h = layer.knots[1] - layer.knots[0];
    const inv_h = 1.0 / h;
    const safe_min = layer.knots[3];
    const safe_max = layer.knots[layer.num_coeffs];

    for (0..batch_size) |b| {
        for (0..layer.in_dim) |i| {
            const x_raw = inputs[b * layer.in_dim + i];
            
            // Use the same fast_exp as optimized version
            const silu = x_raw / (1.0 + kan_spline.fast_exp(-x_raw));

            const x = std.math.clamp(x_raw, safe_min, safe_max - 1e-5);
            const span_float = (x - layer.knots[0]) * inv_h;
            const span_idx = @as(isize, @intFromFloat(@floor(span_float)));
            const u = span_float - @as(f32, @floatFromInt(span_idx));

            const b_vals = kan_spline.basisAll(u);
            const k_base = @as(usize, @intCast(@max(0, span_idx - 3)));

            for (0..layer.out_dim) |j| {
                var val = silu;
                for (0..4) |a| {
                    const k_u = k_base + a;
                    if (k_u < layer.num_coeffs) {
                        val += b_vals[a] * layer.coeffs[(i * layer.num_coeffs + k_u) * layer.out_dim_padded + j];
                    }
                }
                outputs[b * layer.out_dim + j] += val;
            }
        }
    }
}

test "Integrity: SIMD vs Scalar Parity" {
    const allocator = std.testing.allocator;
    const in_dim = 3;
    const out_dim = 16; // One full vector
    const num_coeffs = 8;
    const batch_size = 32;

    var layer = try kan_layer.KanLayer.init(allocator, in_dim, out_dim, num_coeffs);
    defer layer.deinit();

    // Random inputs and weights
    var prng = std.Random.DefaultPrng.init(42);
    const rand = prng.random();
    
    const inputs = try allocator.alloc(f32, batch_size * in_dim);
    defer allocator.free(inputs);
    for (inputs) |*in| in.* = rand.float(f32) * 2.0 - 1.0;

    const opt_out = try allocator.alloc(f32, batch_size * out_dim);
    const naive_out = try allocator.alloc(f32, batch_size * out_dim);
    defer { allocator.free(opt_out); allocator.free(naive_out); }

    // Run optimized pass
    layer.forward(inputs, opt_out, batch_size);

    // Run naive pass
    naiveForward(layer, inputs, naive_out, batch_size);

    // Compare with tolerance (allowing for fast_exp vs std.math.exp difference)
    var max_diff: f32 = 0.0;
    for (0..opt_out.len) |idx| {
        const diff = @abs(opt_out[idx] - naive_out[idx]);
        if (diff > max_diff) max_diff = diff;
    }

    std.debug.print("\nSIMD vs Scalar Parity - Max Difference: {d:0.8}\n", .{max_diff});
    // fast_exp is an approximation, so we expect some error (usually < 1e-3)
    try std.testing.expect(max_diff < 1e-3);
}
