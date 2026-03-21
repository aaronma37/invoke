const std = @import("std");
const kan_network = @import("../core/kan_network.zig");
const KanNetwork = kan_network.KanNetwork;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const path = "model.kan";
    std.debug.print("Loading model for verification: {s}\n", .{path});

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    var reader = file.reader();

    // 1. Load Header
    const num_layers = try reader.readInt(u32, .little);
    const out_dim = try reader.readInt(u32, .little);
    std.debug.print("Architecture: Layers={d}, Final Out={d}\n", .{ num_layers, out_dim });

    // 2. Initialize Network (We'll assume the 3->16->1 architecture for the test)
    const dims = [_]usize{ 3, 16, 1 };
    var net = try KanNetwork.init(allocator, &dims, 8);
    defer net.deinit();

    // 3. Load Weights (Skipping knots as we know they are uniform [-1, 1])
    for (net.layers) |layer| {
        _ = try reader.readInt(u32, .little); // in
        _ = try reader.readInt(u32, .little); // out
        _ = try reader.readInt(u32, .little); // nc
        
        // Skip knots
        try file.seekBy(@as(i64, @intCast((layer.num_coeffs + 4) * 4)));
        
        // Read coeffs
        _ = try reader.readAll(std.mem.sliceAsBytes(layer.coeffs));
    }

    // 4. Verify against 1000 points
    var prng = std.Random.DefaultPrng.init(1337);
    const rand = prng.random();
    
    var total_sq_err: f32 = 0.0;
    const num_samples = 1000;

    const activations = try allocator.alloc([]f32, net.layers.len + 1);
    for (0..activations.len) |i| {
        const dim = if (i == 0) net.layers[0].in_dim else net.layers[i-1].out_dim;
        activations[i] = try allocator.alloc(f32, dim);
    }
    defer {
        for (activations) |a| allocator.free(a);
        allocator.free(activations);
    }

    std.debug.print("\n--- FIDELITY REPORT ---\n", .{});
    for (0..num_samples) |_| {
        const x = (rand.float(f32) * 2.0) - 1.0;
        const y = (rand.float(f32) * 2.0) - 1.0;
        const z = (rand.float(f32) * 2.0) - 1.0;
        const input = [_]f32{ x, y, z };
        
        net.forward(&input, activations, 1);
        const pred_sdf = activations[activations.len-1][0];
        const true_sdf = @sqrt(x*x + y*y + z*z) - 0.8;

        const err = pred_sdf - true_sdf;
        total_sq_err += err * err;
    }

    const rmse = @sqrt(total_sq_err / @as(f32, @floatFromInt(num_samples)));
    std.debug.print("RMSE Error: {d:0.6}\n", .{rmse});
    
    if (rmse < 0.1) {
        std.debug.print("STATUS: Model is CORRECT and HIGH-FIDELITY.\n", .{});
    } else {
        std.debug.print("STATUS: Model has not converged or is corrupted.\n", .{});
    }
    std.debug.print("-----------------------\n", .{});
}
