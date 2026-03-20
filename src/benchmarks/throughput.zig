const std = @import("std");
const mem = std.mem;
const kan_trainer = @import("../core/kan_trainer.zig");
const KanTrainer = kan_trainer.KanTrainer;
const TrainingBatch = kan_trainer.TrainingBatch;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // 1. Initialize a "Production-Sized" KAN
    // [XYZ] -> [128] -> [128] -> [SDF+PBR]
    const dims = [_]usize{ 3, 128, 128, 6 };
    const num_coeffs = 8;
    
    std.debug.print("Initializing Stress Test KAN: 3 -> 128 -> 128 -> 6 (coeffs: {d})\n", .{num_coeffs});
    var trainer = try KanTrainer.initFixed(allocator, &dims, num_coeffs);
    defer trainer.deinit();

    // 2. Prepare massive synthetic data (1 million points)
    const batch_size = 1_000_000;
    std.debug.print("Allocating 1,000,000 training points (~48MB)...\n", .{});
    
    const inputs = try allocator.alloc(f32, batch_size * 3);
    const targets = try allocator.alloc(f32, batch_size * 6);
    defer allocator.free(inputs);
    defer allocator.free(targets);

    @memset(inputs, 0.5);
    @memset(targets, 0.1);

    const batch = TrainingBatch{
        .inputs = inputs,
        .targets = targets,
        .batch_size = batch_size,
    };

    // 3. Warm-up
    std.debug.print("Warming up cache...\n", .{});
    _ = try trainer.trainStep(batch);

    // 4. Benchmark loop
    const num_iterations = 10;
    std.debug.print("Starting Benchmark ({d} steps of 1M points)...\n", .{num_iterations});
    
    const start_time = std.time.nanoTimestamp();
    
    for (0..num_iterations) |i| {
        _ = try trainer.trainStep(batch);
        std.debug.print("Step {d} complete...\n", .{i + 1});
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_s = @as(f64, @floatFromInt(duration_ns)) / 1e9;
    
    const total_points = @as(f64, @floatFromInt(batch_size * num_iterations));
    const points_per_sec = total_points / duration_s;
    const million_points_per_sec = points_per_sec / 1e6;

    std.debug.print("\n--- RESULTS ---\n", .{});
    std.debug.print("Total Time:   {d:0.3} seconds\n", .{duration_s});
    std.debug.print("Throughput:   {d:0.2} Million Points/Sec (GPS)\n", .{million_points_per_sec});
    std.debug.print("Per-Step:     {d:0.3} ms\n", .{(duration_s / @as(f64, @floatFromInt(num_iterations))) * 1000.0});
    std.debug.print("---------------\n", .{});
}
