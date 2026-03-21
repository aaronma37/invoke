const std = @import("std");
const kan = @import("kan");
const KanNetwork = kan.KanNetwork;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Load Model
    var net = try KanNetwork.loadModel(allocator, "model.kan");
    defer net.deinit();
    std.debug.print("Loaded KAN Model: {d} layers\\n", .{net.layers.len});

    // 2. Open OBJ for output
    const file = try std.fs.cwd().createFile("bunny_reconstructed.obj", .{});
    defer file.close();
    var writer = file.writer();

    // 3. March through the volume and find the surface (SDF near 0)
    const res: usize = 128; 
    std.debug.print("Extracting surface on {d}^3 grid...\\n", .{res});

    var activations = try allocator.alloc([]f32, net.layers.len + 1);
    for (0..net.layers.len) |i| {
        activations[i] = try allocator.alloc(f32, net.layers[i].in_dim);
    }
    activations[net.layers.len] = try allocator.alloc(f32, net.out_dim);
    defer { for (activations) |a| allocator.free(a); allocator.free(activations); }

    var vertex_count: usize = 0;
    for (0..res) |z| {
        const fz = (@as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(res - 1))) * 2.0 - 1.0;
        for (0..res) |y| {
            const fy = (@as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(res - 1))) * 2.0 - 1.0;
            for (0..res) |x| {
                const fx = (@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(res - 1))) * 2.0 - 1.0;
                
                const input = [_]f32{ fx, fy, fz };
                net.forward(&input, activations, 1);
                
                const sdf = activations[net.layers.len][0];
                
                // If we are very close to the surface, save a vertex
                if (@abs(sdf) < 0.01) {
                    try writer.print("v {d:0.4} {d:0.4} {d:0.4}\\n", .{ fx, fy, fz });
                    vertex_count += 1;
                }
            }
        }
    }

    std.debug.print("Done! Extracted {d} surface points to bunny_reconstructed.obj\\n", .{vertex_count});
}
