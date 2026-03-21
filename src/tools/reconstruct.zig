const std = @import("std");
const kan_network = @import("../core/kan_network.zig");
const KanNetwork = kan_network.KanNetwork;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const path = "model.kan";
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    var reader = file.reader();

    // 1. Load Header
    _ = try reader.readInt(u32, .little); // num_layers
    _ = try reader.readInt(u32, .little); // out_dim

    const dims = [_]usize{ 3, 16, 1 };
    var net = try KanNetwork.init(allocator, &dims, 8);
    defer net.deinit();

    // 2. Load Weights
    for (net.layers) |layer| {
        _ = try reader.readInt(u32, .little);
        _ = try reader.readInt(u32, .little);
        _ = try reader.readInt(u32, .little);
        try file.seekBy(@as(i64, @intCast((layer.num_coeffs + 4) * 4)));
        _ = try reader.readAll(std.mem.sliceAsBytes(layer.coeffs));
    }

    // 3. Dense Grid Reconstruction
    const out_file = try std.fs.cwd().createFile("reconstructed_sphere.obj", .{});
    defer out_file.close();
    var writer = out_file.writer();

    std.debug.print("Reconstructing 3D surface to reconstructed_sphere.obj...\n", .{});

    const res = 128;
    const activations = try allocator.alloc([]f32, net.layers.len + 1);
    for (0..activations.len) |i| {
        const dim = if (i == 0) net.layers[0].in_dim else net.layers[i-1].out_dim;
        activations[i] = try allocator.alloc(f32, dim);
    }
    defer { for (activations) |a| allocator.free(a); allocator.free(activations); }

    var vertex_count: usize = 0;
    var x: usize = 0;
    while (x < res) : (x += 1) {
        const fx = (@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(res))) * 2.0 - 1.0;
        var y: usize = 0;
        while (y < res) : (y += 1) {
            const fy = (@as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(res))) * 2.0 - 1.0;
            var z: usize = 0;
            while (z < res) : (z += 1) {
                const fz = (@as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(res))) * 2.0 - 1.0;
                
                const input = [_]f32{ fx, fy, fz };
                net.forward(&input, activations, 1);
                const sdf = activations[activations.len-1][0];

                if (@abs(sdf) < 0.015) {
                    try writer.print("v {d:0.4} {d:0.4} {d:0.4}\n", .{ fx, fy, fz });
                    vertex_count += 1;
                }
            }
        }
    }

    std.debug.print("SUCCESS: Reconstructed surface with {d} points.\n", .{vertex_count});
}
