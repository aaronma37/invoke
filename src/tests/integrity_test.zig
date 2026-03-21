const std = @import("std");
const kan_layer = @import("../core/kan_layer.zig");
const kan_trainer = @import("../core/kan_trainer.zig");
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

    // Compare with tolerance
    var max_diff: f32 = 0.0;
    for (0..opt_out.len) |idx| {
        const diff = @abs(opt_out[idx] - naive_out[idx]);
        if (diff > max_diff) max_diff = diff;
    }

    try std.testing.expect(max_diff < 1e-4);
}

test "Integrity: Training Determinism (1 vs 16 threads)" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 2, 8, 8, 1 };
    const num_coeffs = 8;
    const batch_size = 1024;

    // 1. Setup fixed dataset
    const inputs_aos = try allocator.alloc(f32, batch_size * 2);
    const targets_aos = try allocator.alloc(f32, batch_size * 1);
    defer { allocator.free(inputs_aos); allocator.free(targets_aos); }
    
    var prng = std.Random.DefaultPrng.init(42);
    const rand = prng.random();
    for (inputs_aos) |*in| in.* = rand.float(f32);
    for (targets_aos) |*t| t.* = rand.float(f32);

    // Transpose to SoA for the trainer
    const inputs = try allocator.alloc(f32, batch_size * 2);
    const targets = try allocator.alloc(f32, batch_size * 1);
    defer { allocator.free(inputs); allocator.free(targets); }
    for (0..2) |i| {
        for (0..batch_size) |b| {
            inputs[i * batch_size + b] = inputs_aos[b * 2 + i];
        }
    }
    for (0..1) |i| {
        for (0..batch_size) |b| {
            targets[i * batch_size + b] = targets_aos[b * 1 + i];
        }
    }

    // 2. Train with 1 thread
    var trainer1 = try kan_trainer.KanTrainer.initWithThreads(allocator, &dims, num_coeffs, batch_size, .sdf, 1);
    defer trainer1.deinit();
    
    // Set fixed weights for both
    for (0..trainer1.net.layers.len) |l| {
        for (trainer1.net.layers[l].coeffs) |*c| c.* = 0.1;
    }

    const batch = kan_trainer.TrainingBatch{ .inputs = inputs, .targets = targets, .batch_size = batch_size };
    _ = try trainer1.trainStep(batch);

    // 3. Train with 16 threads
    var trainer16 = try kan_trainer.KanTrainer.initWithThreads(allocator, &dims, num_coeffs, batch_size, .sdf, 16);
    defer trainer16.deinit();
    
    for (0..trainer16.net.layers.len) |l| {
        for (trainer16.net.layers[l].coeffs) |*c| c.* = 0.1;
    }

    _ = try trainer16.trainStep(batch);

    // 4. Compare resulting weights
    for (0..trainer1.net.layers.len) |l| {
        const c1 = trainer1.net.layers[l].coeffs;
        const c16 = trainer16.net.layers[l].coeffs;
        for (0..c1.len) |i| {
            // Should be exactly identical if reduction is correct
            try std.testing.expectEqual(c1[i], c16[i]);
        }
    }
}

/// Naive scalar backward pass for parity checking.
fn naiveBackward(layer: kan_layer.KanLayer, inputs: []const f32, out_grad: []const f32, in_grad: []f32, coeff_grads: []f32, batch_size: usize) void {
    @memset(in_grad[0 .. batch_size * layer.in_dim], 0.0);
    const h = layer.knots[1] - layer.knots[0];
    const inv_h = 1.0 / h;
    const safe_min = layer.knots[3];
    const safe_max = layer.knots[layer.num_coeffs];

    for (0..batch_size) |b| {
        for (0..layer.in_dim) |i| {
            const x_raw = inputs[b * layer.in_dim + i];
            const sigmoid = 1.0 / (1.0 + kan_spline.fast_exp(-x_raw));
            const silu_prime = sigmoid * (1.0 + x_raw * (1.0 - sigmoid));

            const x = std.math.clamp(x_raw, safe_min, safe_max - 1e-5);
            const span_float = (x - layer.knots[0]) * inv_h;
            const span_idx = @as(isize, @intFromFloat(@floor(span_float)));
            const u = span_float - @as(f32, @floatFromInt(span_idx));

            const b_vals = kan_spline.basisAll(u);
            const bp_vals = kan_spline.derivativeAll(u, inv_h);
            const k_base = @as(usize, @intCast(@max(0, span_idx - 3)));

            for (0..layer.out_dim) |j| {
                const og = out_grad[b * layer.out_dim + j];
                var total_in_grad = og * silu_prime;
                for (0..4) |a| {
                    const k_u = k_base + a;
                    if (k_u < layer.num_coeffs) {
                        const c_idx = (i * layer.num_coeffs + k_u) * layer.out_dim_padded + j;
                        coeff_grads[c_idx] += og * b_vals[a];
                        total_in_grad += og * bp_vals[a] * layer.coeffs[c_idx];
                    }
                }
                in_grad[b * layer.in_dim + i] += total_in_grad;
            }
        }
    }
}

test "Integrity: Bucket Sort Backward Parity" {
    const allocator = std.testing.allocator;
    const in_dim = 3;
    const out_dim = 16;
    const num_coeffs = 8;
    const batch_size = 32;

    var layer = try kan_layer.KanLayer.init(allocator, in_dim, out_dim, num_coeffs);
    defer layer.deinit();

    var prng = std.Random.DefaultPrng.init(42);
    const rand = prng.random();
    
    const inputs = try allocator.alloc(f32, batch_size * in_dim);
    const out_grad = try allocator.alloc(f32, batch_size * out_dim);
    defer { allocator.free(inputs); allocator.free(out_grad); }
    for (inputs) |*v| v.* = rand.float(f32) * 2.0 - 1.0;
    for (out_grad) |*v| v.* = rand.float(f32) * 0.1;

    const opt_in_grad = try allocator.alloc(f32, batch_size * in_dim);
    const opt_cg = try allocator.alloc(f32, layer.coeffs.len);
    const naive_in_grad = try allocator.alloc(f32, batch_size * in_dim);
    const naive_cg = try allocator.alloc(f32, layer.coeffs.len);
    defer { allocator.free(opt_in_grad); allocator.free(opt_cg); allocator.free(naive_in_grad); allocator.free(naive_cg); }

    @memset(opt_cg, 0.0);
    @memset(naive_cg, 0.0);

    const scratch = try allocator.alloc(f32, batch_size * 2);
    defer allocator.free(scratch);

    // Run optimized (Sorted) backward
    layer.backward(inputs, out_grad, opt_in_grad, opt_cg, batch_size, scratch);

    // Run naive backward
    naiveBackward(layer, inputs, out_grad, naive_in_grad, naive_cg, batch_size);

    // Compare Coeff Gradients
    for (0..opt_cg.len) |i| {
        try std.testing.expectApproxEqAbs(naive_cg[i], opt_cg[i], 1e-5);
    }

    // Compare Input Gradients
    for (0..opt_in_grad.len) |i| {
        try std.testing.expectApproxEqAbs(naive_in_grad[i], opt_in_grad[i], 1e-5);
    }
    
    std.debug.print("\nBackward Bucket Sort Parity Test - PASSED\n", .{});
}

test "Integrity: Serialization (Save/Load) Parity" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 3, 16, 16, 6 };
    const num_coeffs = 8;

    // 1. Create original network and set random weights
    var original_net = try @import("../core/kan_network.zig").KanNetwork.init(allocator, &dims, num_coeffs);
    defer original_net.deinit();

    var prng = std.Random.DefaultPrng.init(1234);
    const rand = prng.random();
    for (original_net.layers) |layer| {
        for (layer.coeffs) |*c| c.* = rand.float(f32);
    }

    // 2. Run inference on original
    const input = [_]f32{ 0.1, -0.5, 0.8 };
    var orig_acts = try allocator.alloc([]f32, original_net.layers.len + 1);
    for (0..original_net.layers.len) |i| orig_acts[i] = try allocator.alloc(f32, original_net.layers[i].in_dim);
    orig_acts[original_net.layers.len] = try allocator.alloc(f32, original_net.out_dim);
    defer { for (orig_acts) |a| allocator.free(a); allocator.free(orig_acts); }

    original_net.forward(&input, orig_acts, 1);
    
    // Copy result to compare later
    const expected_out = try allocator.alloc(f32, original_net.out_dim);
    defer allocator.free(expected_out);
    @memcpy(expected_out, orig_acts[original_net.layers.len]);

    // 3. Save to disk
    const tmp_path = "test_model_serialization.kan";
    try original_net.saveModel(tmp_path);
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    // 4. Load from disk
    var loaded_net = try @import("../core/kan_network.zig").KanNetwork.loadModel(allocator, tmp_path);
    defer loaded_net.deinit();

    // 5. Run inference on loaded
    var load_acts = try allocator.alloc([]f32, loaded_net.layers.len + 1);
    for (0..loaded_net.layers.len) |i| load_acts[i] = try allocator.alloc(f32, loaded_net.layers[i].in_dim);
    load_acts[loaded_net.layers.len] = try allocator.alloc(f32, loaded_net.out_dim);
    defer { for (load_acts) |a| allocator.free(a); allocator.free(load_acts); }

    loaded_net.forward(&input, load_acts, 1);

    // 6. Assert results are bit-identical
    for (0..original_net.out_dim) |i| {
        try std.testing.expectEqual(expected_out[i], load_acts[loaded_net.layers.len][i]);
    }

    std.debug.print("\nSerialization Integrity Test - PASSED (Original vs Loaded output matches exactly)\n", .{});
}

test "Integrity: Memory Leakage Check" {
    // std.testing.allocator automatically checks for leaks on deinit!
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 3, 16, 16, 1 };
    const num_coeffs = 8;
    const batch_size = 1024;

    // Allocate fixed data
    const inputs = try allocator.alloc(f32, batch_size * 3);
    const targets = try allocator.alloc(f32, batch_size * 1);
    defer { allocator.free(inputs); allocator.free(targets); }
    @memset(inputs, 0.1);
    @memset(targets, 0.5);

    // Full Init/Train/Deinit cycle
    var trainer = try kan_trainer.KanTrainer.initWithThreads(allocator, &dims, num_coeffs, batch_size, .sdf, 4);
    
    const batch = kan_trainer.TrainingBatch{ .inputs = inputs, .targets = targets, .batch_size = batch_size };
    _ = try trainer.trainStep(batch);
    
    trainer.deinit();
    
    std.debug.print("\nMemory Leak Integrity Test - PASSED (Zero bytes leaked)\n", .{});
}
