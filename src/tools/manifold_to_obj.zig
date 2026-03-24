const std = @import("std");
const mem = std.mem;
const core = @import("core");
const TensorSurface = core.tensor_spline.TensorSurface;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <model.kan> <output.obj> [resolution]\n", .{args[0]});
        return;
    }

    const model_path = args[1];
    const out_path = args[2];
    const res = if (args.len > 3) try std.fmt.parseInt(usize, args[3], 10) else 32;

    // 1. Load the KAN model
    // Note: In our hardened architecture, the last layer is the TensorSurface.
    // For this mesher, we assume we are evaluating a single manifold primitive.
    var net = try core.KanNetwork.loadModel(allocator, model_path);
    defer net.deinit();

    // 2. Setup output file
    const out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    var writer = out_file.writer();
    try writer.print("# Manifold Composer Silicon Export\n", .{});

    // 3. Evaluate Grid
    const batch_size = 1024;
    var activations = try allocator.alloc([]f32, net.layers.len + 1);
    for (0..net.layers.len) |i| activations[i] = try allocator.alloc(f32, batch_size * net.layers[i].in_dim);
    activations[net.layers.len] = try allocator.alloc(f32, batch_size * net.out_dim);
    defer { for (activations) |a| allocator.free(a); allocator.free(activations); }

    // Export Vertices
    for (0..res) |v_idx| {
        for (0..res) |u_idx| {
            const u = @as(f32, @floatFromInt(u_idx)) / @as(f32, @floatFromInt(res - 1));
            const v = @as(f32, @floatFromInt(v_idx)) / @as(f32, @floatFromInt(res - 1));
            
            // We use the first point in the batch for simplicity in this loop
            activations[0][0] = u;
            activations[0][1] = v;
            
            net.forward(activations[0], activations, 1);
            
            const out = activations[net.layers.len];
            try writer.print("v {d:0.6} {d:0.6} {d:0.6}\n", .{out[0], out[1], out[2]});
        }
    }

    // 4. Export Faces (Standard Grid Topology)
    for (0..res - 1) |v| {
        for (0..res - 1) |u| {
            const v1 = v * res + u + 1;
            const v2 = v * res + (u + 1) + 1;
            const v3 = (v + 1) * res + (u + 1) + 1;
            const v4 = (v + 1) * res + u + 1;
            try writer.print("f {d} {d} {d}\n", .{v1, v2, v3});
            try writer.print("f {d} {d} {d}\n", .{v1, v3, v4});
        }
    }

    std.debug.print("Successfully exported manifold mesh to {s}\n", .{out_path});
}
