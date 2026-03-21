const std = @import("std");
const kan = @import("kan");

const KanNetwork = kan.KanNetwork;
const PointSample = kan.kan_dataloader.PointSample;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Load Model
    var net = try KanNetwork.loadModel(allocator, "model.kan");
    defer net.deinit();
    std.debug.print("Loaded KAN: {d} layers, {d} outputs\n", .{net.layers.len, net.out_dim});

    // 2. Sample Grid (100^3 = 1 million points)
    const res: usize = 100;
    var samples = try allocator.alloc(PointSample, res * res * res);
    defer allocator.free(samples);

    var activations = try allocator.alloc([]f32, net.layers.len + 1);
    defer allocator.free(activations);
    for (0..net.layers.len) |i| {
        activations[i] = try allocator.alloc(f32, net.layers[i].in_dim);
    }
    activations[net.layers.len] = try allocator.alloc(f32, net.out_dim);
    defer { for (activations) |a| allocator.free(a); }

    std.debug.print("Sampling KAN field on {d}^3 grid...\n", .{res});
    
    var idx: usize = 0;
    for (0..res) |z| {
        const fz = (@as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(res - 1))) * 2.0 - 1.0;
        for (0..res) |y| {
            const fy = (@as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(res - 1))) * 2.0 - 1.0;
            for (0..res) |x| {
                const fx = (@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(res - 1))) * 2.0 - 1.0;
                
                const input = [_]f32{ fx, fy, fz };
                net.forward(&input, activations, 1);
                
                const sdf = activations[net.layers.len][0];
                
                samples[idx] = PointSample{
                    .x = fx, .y = fy, .z = fz,
                    .sdf = sdf,
                    .r = 0.5, .g = 0.7, .b = 1.0,
                    .roughness = 0.5, .metallic = 0.0,
                };
                idx += 1;
            }
        }
    }

    // 3. Save to PCB
    const file = try std.fs.cwd().createFile("kan_debug.pcb", .{});
    defer file.close();
    try file.writeAll(std.mem.sliceAsBytes(samples));
    
    std.debug.print("Saved 1 million points to kan_debug.pcb\n", .{});
    std.debug.print("Use 'pcb_viewer' to validate the result.\n", .{});
}
