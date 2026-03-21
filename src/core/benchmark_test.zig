const std = @import("std");
const kan_trainer = @import("kan_trainer.zig");
const kan_dataloader = @import("kan_dataloader.zig");
const TrainingBatch = kan_trainer.TrainingBatch;
const KanTrainer = kan_trainer.KanTrainer;
const DataLoader = kan_dataloader.DataLoader;

test "Benchmark: Objaverse Real-World Train" {
    const allocator = std.testing.allocator;
    const pcb_path = "bunny_sample.pcb";
    
    var loader = DataLoader.init(allocator, pcb_path) catch {
        std.debug.print("PCB not found at {s}, skipping real-world test.\n", .{pcb_path});
        return;
    };

    const dims = [_]usize{ 3, 32, 32, 6 };
    var trainer = try KanTrainer.initFixed(allocator, &dims, 8, 10000, .sdf);
    defer trainer.deinit();

    const batch_size = 10000;
    const inputs = try allocator.alloc(f32, batch_size * 3);
    const targets = try allocator.alloc(f32, batch_size * 6);
    defer { allocator.free(inputs); allocator.free(targets); }

    var prng = std.Random.DefaultPrng.init(42);
    loader.getBatch(batch_size, 3, 6, &prng, inputs, targets);

    const batch = TrainingBatch{ .inputs = inputs, .targets = targets, .batch_size = batch_size };
    _ = try trainer.trainStep(batch);
    
    std.debug.print("\nSUCCESS: Successfully trained one step using GPU-generated data!\n", .{});
}

test "Benchmark: Production-Sized Stress Test" {
    const allocator = std.testing.allocator;

    const dims = [_]usize{ 3, 32, 32, 6 };
    const num_coeffs = 8;
    
    std.debug.print("\nInitializing Production KAN: 3 -> 32 -> 32 -> 6 (coeffs: {d})\n", .{num_coeffs});
    var trainer = try KanTrainer.initFixed(allocator, &dims, num_coeffs, 100_000, .sdf);
    defer trainer.deinit();

    const batch_size = 32_768;
    
    // Allocate SoA buffers directly
    const inputs_soa = try allocator.alloc(f32, batch_size * 3);
    const targets_soa = try allocator.alloc(f32, batch_size * 6);
    defer allocator.free(inputs_soa);
    defer allocator.free(targets_soa);

    @memset(inputs_soa, 0.5);
    @memset(targets_soa, 0.1);

    const batch = TrainingBatch{
        .inputs = inputs_soa,
        .targets = targets_soa,
        .batch_size = batch_size,
    };

    std.debug.print("Starting Benchmark (100 steps of 32k points)...\n", .{});
    
    const start_time = std.time.nanoTimestamp();
    const num_iterations = 100;
    
    for (0..num_iterations) |_| {
        _ = try trainer.trainStep(batch);
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
