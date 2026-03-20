const std = @import("std");
const kan_trainer = @import("../core/kan_trainer.zig");
const TrainingBatch = kan_trainer.TrainingBatch;
const KanTrainer = kan_trainer.KanTrainer;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // 1. Initialize KAN for 3D SDF (XYZ -> 16 -> 1)
    const dims = [_]usize{ 3, 16, 1 };
    var trainer = try KanTrainer.init(allocator, &dims, 8); // 8 control points per edge
    defer trainer.deinit();

    trainer.lambda_eikonal = 0.5; // Strong Eikonal enforcement
    trainer.optimizer.learning_rate = 0.01;

    const batch_size = 64;
    const inputs = try allocator.alloc(f32, batch_size * 3);
    const targets = try allocator.alloc(f32, batch_size * 1);
    defer allocator.free(inputs);
    defer allocator.free(targets);

    var prng = std.rand.DefaultPrng.init(42);
    const rand = prng.random();

    std.debug.print("Training KAN to fit a Unit Sphere...\n", .{});

    var last_loss: f32 = 0.0;
    for (0..200) |epoch| {
        // Generate batch: random points in [-1.5, 1.5]
        for (0..batch_size) |b| {
            const x = (rand.float(f32) * 3.0) - 1.5;
            const y = (rand.float(f32) * 3.0) - 1.5;
            const z = (rand.float(f32) * 3.0) - 1.5;
            
            inputs[b * 3 + 0] = x;
            inputs[b * 3 + 1] = y;
            inputs[b * 3 + 2] = z;
            
            // True SDF for sphere: sqrt(x^2 + y^2 + z^2) - 1.0
            const dist = @sqrt(x*x + y*y + z*z);
            targets[b] = dist - 1.0;
        }

        const batch = TrainingBatch{
            .inputs = inputs,
            .targets = targets,
            .batch_size = batch_size,
        };

        const loss = try trainer.trainStep(batch);
        last_loss = loss;
        if (epoch % 20 == 0) {
            std.debug.print("Epoch {d:03}: Loss = {d:0.6}\n", .{ epoch, loss });
        }
    }

    // 2. Final Verification
    // At x=1.0, y=0.0, z=0.0, SDF should be 0.0
    const test_input = [_]f32{ 1.0, 0.0, 0.0 };
    const activations = try allocator.alloc([]f32, trainer.net.layers.len + 1);
    for (0..activations.len) |i| {
        const dim = if (i == 0) trainer.net.layers[0].in_dim else trainer.net.layers[i-1].out_dim;
        activations[i] = try allocator.alloc(f32, 1 * dim);
    }
    defer {
        for (activations) |a| allocator.free(a);
        allocator.free(activations);
    }

    trainer.net.forward(&test_input, activations, 1);
    const final_sdf = activations[activations.len-1][0];

    std.debug.print("\nVerification at (1, 0, 0):\n", .{});
    std.debug.print("  Target SDF: 0.0\n", .{});
    std.debug.print("  Pred SDF:   {d:0.6}\n", .{ final_sdf });
    std.debug.print("  Final Loss: {d:0.6}\n", .{ last_loss });

    if (@abs(final_sdf) < 0.2) {
        std.debug.print("\nSUCCESS: KAN successfully learned the sphere geometry!\n", .{});
    } else {
        std.debug.print("\nFAILURE: KAN did not converge on the sphere.\n", .{});
    }
}
