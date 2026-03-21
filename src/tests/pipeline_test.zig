const std = @import("std");
const kan = @import("../core/kan_network.zig");
const kan_trainer = @import("../core/kan_trainer.zig");
const TrainingBatch = kan_trainer.TrainingBatch;
const KanTrainer = kan_trainer.KanTrainer;

test "Pipeline: Basic SDF Sphere Training" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 3, 16, 16, 1 };
    var trainer = try KanTrainer.initFixed(allocator, &dims, 4, 1000, .sdf);
    defer trainer.deinit();

    const batch_size = 1000;
    const inputs = try allocator.alloc(f32, batch_size * 3);
    const targets = try allocator.alloc(f32, batch_size * 1);
    defer { allocator.free(inputs); allocator.free(targets); }

    var prng = std.Random.DefaultPrng.init(42);
    const rand = prng.random();
    trainer.optimizer.learning_rate = 1.0;

    // Train for 5000 steps on a sphere of radius 0.5
    for (0..5000) |_| {
        for (0..batch_size) |b| {
            const x = rand.float(f32) * 2.0 - 1.0;
            const y = rand.float(f32) * 2.0 - 1.0;
            const z = rand.float(f32) * 2.0 - 1.0;
            inputs[b * 3 + 0] = x;
            inputs[b * 3 + 1] = y;
            inputs[b * 3 + 2] = z;
            targets[b * 1 + 0] = @sqrt(x*x + y*y + z*z) - 0.5;
        }
        const batch = TrainingBatch{ .inputs = inputs, .targets = targets, .batch_size = batch_size };
        _ = try trainer.trainStep(batch);
    }

    const probe_in_aos = [_]f32{ 
        0, 0, 0, 
        0.5, 0, 0, 
        1.0, 0, 0 
    };

    const probe_out = try allocator.alloc(f32, 3 * trainer.net.out_dim);
    defer allocator.free(probe_out);
    
    const probe_acts = try allocator.alloc([]f32, trainer.net.layers.len + 1);
    for (0..trainer.net.layers.len) |i| probe_acts[i] = try allocator.alloc(f32, 3 * trainer.net.layers[i].in_dim);
    probe_acts[trainer.net.layers.len] = probe_out;
    defer { for (probe_acts[0..trainer.net.layers.len]) |a| allocator.free(a); allocator.free(probe_acts); }

    trainer.net.forward(&probe_in_aos, probe_acts, 3);
    
    std.debug.print("\nSDF Sphere Test Results:\n", .{});
    std.debug.print("  Center (0,0,0): {d:0.4} (expected -0.5)\n", .{probe_out[0]});
    std.debug.print("  Surface (0.5,0,0): {d:0.4} (expected 0.0)\n", .{probe_out[1]});
    std.debug.print("  Outside (1,0,0): {d:0.4} (expected 0.5)\n", .{probe_out[2]});
    
    try std.testing.expect(probe_out[0] < -0.3);
}

test "Pipeline: Basic UV Displacement Training" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 2, 16, 16, 1 };
    var trainer = try KanTrainer.initFixed(allocator, &dims, 4, 1000, .displacement);
    defer trainer.deinit();

    const batch_size = 1000;
    const inputs = try allocator.alloc(f32, batch_size * 2);
    const targets = try allocator.alloc(f32, batch_size * 1);
    defer { allocator.free(inputs); allocator.free(targets); }

    var prng = std.Random.DefaultPrng.init(42);
    const rand = prng.random();
    trainer.optimizer.learning_rate = 1.0;

    // Train on a "constant displacement" sphere (radius 0.7)
    for (0..5000) |_| {
        for (0..batch_size) |b| {
            inputs[b * 2 + 0] = rand.float(f32); // u
            inputs[b * 2 + 1] = rand.float(f32); // v
            targets[b * 1 + 0] = 0.7;
        }
        const batch = TrainingBatch{ .inputs = inputs, .targets = targets, .batch_size = batch_size };
        _ = try trainer.trainStep(batch);
    }

    const test_uv_aos = [_]f32{ 0.5, 0.5 };
    const test_out = try allocator.alloc(f32, 1);
    defer allocator.free(test_out);

    const test_acts = try allocator.alloc([]f32, trainer.net.layers.len + 1);
    for (0..trainer.net.layers.len) |i| test_acts[i] = try allocator.alloc(f32, 1 * trainer.net.layers[i].in_dim);
    test_acts[trainer.net.layers.len] = test_out;
    defer { for (test_acts[0..trainer.net.layers.len]) |a| allocator.free(a); allocator.free(test_acts); }

    trainer.net.forward(&test_uv_aos, test_acts, 1);
    
    std.debug.print("UV Displacement Test - Disp at (0.5, 0.5): {d:0.4} (expected 0.7)\n", .{test_out[0]});
    try std.testing.expect(test_out[0] > 0.6 and test_out[0] < 0.8);
}
