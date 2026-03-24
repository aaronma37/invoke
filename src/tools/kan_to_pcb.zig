const std = @import("std");
const kan = @import("kan");

const KanNetwork = kan.KanNetwork;
const PointSample = kan.kan_dataloader.PointSample;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <model.kan> [resolution]\n", .{args[0]});
        return;
    }

    // 1. Load Model
    var net = try KanNetwork.loadModel(allocator, args[1]);
    defer net.deinit();
    
    const res = if (args.len > 2) try std.fmt.parseInt(usize, args[2], 10) else 100;
    const total_points: usize = res * res;
    var samples = try allocator.alloc(PointSample, total_points);
    defer allocator.free(samples);

    // BATCH PROCESSING
    const batch_size: usize = 1024;
    var activations = try allocator.alloc([]f32, net.layers.len + 1);
    for (0..net.layers.len) |i| {
        activations[i] = try allocator.alloc(f32, batch_size * net.layers[i].in_dim);
    }
    activations[net.layers.len] = try allocator.alloc(f32, batch_size * net.out_dim);
    defer { for (activations) |a| allocator.free(a); allocator.free(activations); }

    var p_idx: usize = 0;
    while (p_idx < total_points) {
        const current_batch = @min(total_points - p_idx, batch_size);
        
        for (0..current_batch) |i| {
            const global_idx = p_idx + i;
            const v_idx = global_idx / res;
            const u_idx = global_idx % res;
            
            const u = @as(f32, @floatFromInt(u_idx)) / @as(f32, @floatFromInt(res - 1));
            const v = @as(f32, @floatFromInt(v_idx)) / @as(f32, @floatFromInt(res - 1));
            
            activations[0][i * net.layers[0].in_dim + 0] = u;
            activations[0][i * net.layers[0].in_dim + 1] = v;
        }

        net.forward(activations[0], activations, current_batch);

        for (0..current_batch) |i| {
            const global_idx = p_idx + i;
            const out = activations[net.layers.len][i * net.out_dim .. (i + 1) * net.out_dim];
            
            samples[global_idx] = PointSample{
                .u = activations[0][i * net.layers[0].in_dim + 0],
                .v = activations[0][i * net.layers[0].in_dim + 1],
                .x = out[0],
                .y = out[1],
                .z = out[2],
                .c1 = if (out.len > 3) out[3] else 0,
                .c2 = if (out.len > 4) out[4] else 0,
                .c3 = if (out.len > 5) out[5] else 0,
            };
        }
        
        p_idx += current_batch;
    }

    const file = try std.fs.cwd().createFile("output.pcb", .{});
    defer file.close();
    try file.writeAll(std.mem.sliceAsBytes(samples));
    
    std.debug.print("Saved {d} points to output.pcb\n", .{total_points});
}
