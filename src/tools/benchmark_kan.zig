const std = @import("std");
const kan = @import("kan");

const KanNetwork = kan.KanNetwork;
const KanTrainer = kan.kan_trainer.KanTrainer;
const DataLoader = kan.kan_dataloader.DataLoader;
const TrainingBatch = kan.kan_trainer.TrainingBatch;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const dims = [_]usize{ 3, 32, 32, 1 };
    const num_coeffs = 16;
    const batch_size = 10000;
    
    std.debug.print("Initializing KAN Benchmark: 3 -> 32 -> 32 -> 1 (coeffs: {d})\n", .{num_coeffs});
    var trainer = try KanTrainer.initFixed(allocator, &dims, num_coeffs, batch_size);
    defer trainer.deinit();

    const inputs = try allocator.alloc(f32, batch_size * 3);
    const targets = try allocator.alloc(f32, batch_size * 1);
    defer { allocator.free(inputs); allocator.free(targets); }
    @memset(inputs, 0.5);
    @memset(targets, 0.0);

    const batch = TrainingBatch{ .inputs = inputs, .targets = targets, .batch_size = batch_size };

    // 1. Full Train Step (with Eikonal)
    {
        trainer.lambda_eikonal = 0.1;
        const start = std.time.nanoTimestamp();
        const iters = 10;
        for (0..iters) |_| {
            _ = try trainer.trainStep(batch);
        }
        const end = std.time.nanoTimestamp();
        const elapsed = @as(f64, @floatFromInt(end - start)) / 1e9;
        std.debug.print("Full Step (w/ Eikonal): {d:0.3} ms per step ({d:0.2} Mpts/s)\n", .{ (elapsed / iters) * 1000.0, (@as(f64, @floatFromInt(batch_size * iters)) / elapsed) / 1e6 });
    }

    // 2. Step without Eikonal
    {
        trainer.lambda_eikonal = 0.0;
        const start = std.time.nanoTimestamp();
        const iters = 100;
        for (0..iters) |_| {
            _ = try trainer.trainStep(batch);
        }
        const end = std.time.nanoTimestamp();
        const elapsed = @as(f64, @floatFromInt(end - start)) / 1e9;
        std.debug.print("Step (No Eikonal):     {d:0.3} ms per step ({d:0.2} Mpts/s)\n", .{ (elapsed / iters) * 1000.0, (@as(f64, @floatFromInt(batch_size * iters)) / elapsed) / 1e6 });
    }
}
