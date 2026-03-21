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

    // 2. Sample Grid (100^3 = 1 million points for high fidelity)
    const res: usize = 100;
    const total_points: usize = res * res * res;
    var samples = try allocator.alloc(PointSample, total_points);
    defer allocator.free(samples);

    // BATCH PROCESSING
    const batch_size: usize = 10000;
    var activations = try allocator.alloc([]f32, net.layers.len + 1);
    for (0..net.layers.len) |i| {
        activations[i] = try allocator.alloc(f32, batch_size * net.layers[i].in_dim);
    }
    activations[net.layers.len] = try allocator.alloc(f32, batch_size * net.out_dim);
    defer { for (activations) |a| allocator.free(a); allocator.free(activations); }

    std.debug.print("Sampling KAN field on {d}^3 grid (Batch Size: {d})...\n", .{res, batch_size});
    
    var p_idx: usize = 0;
    while (p_idx < total_points) {
        const current_batch = if (total_points - p_idx < batch_size) total_points - p_idx else batch_size;
        
        // 1. Fill Inputs
        for (0..current_batch) |i| {
            const global_idx = p_idx + i;
            const z = global_idx / (res * res);
            const y = (global_idx % (res * res)) / res;
            const x = global_idx % res;
            
            activations[0][i * 3 + 0] = (@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(res - 1))) * 2.0 - 1.0;
            activations[0][i * 3 + 1] = (@as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(res - 1))) * 2.0 - 1.0;
            activations[0][i * 3 + 2] = (@as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(res - 1))) * 2.0 - 1.0;
        }

        // 2. Forward Batch
        net.forward(activations[0], activations, current_batch);

        // 3. Extract
        for (0..current_batch) |i| {
            const global_idx = p_idx + i;
            samples[global_idx] = PointSample{
                .x = activations[0][i * 3 + 0],
                .y = activations[0][i * 3 + 1],
                .z = activations[0][i * 3 + 2],
                .sdf = activations[net.layers.len][i * net.out_dim],
                .r = 0.5, .g = 0.7, .b = 1.0,
                .roughness = 0.5, .metallic = 0.0,
            };
        }
        
        p_idx += current_batch;
        if ((p_idx / batch_size) % 10 == 0) std.debug.print("Progress: {d}%\r", .{(p_idx * 100) / total_points});
    }

    // 3. Save to PCB
    const file = try std.fs.cwd().createFile("kan_debug.pcb", .{});
    defer file.close();
    try file.writeAll(std.mem.sliceAsBytes(samples));
    
    std.debug.print("\nSaved 1 million points to kan_debug.pcb\n", .{});
}
