const std = @import("std");
const mem = std.mem;
const kan = @import("kan");

const KanNetwork = kan.KanNetwork;
const KanTrainer = kan.kan_trainer.KanTrainer;
const DataLoader = kan.kan_dataloader.DataLoader;
const TrainingBatch = kan.kan_trainer.TrainingBatch;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <dataset.pcb> [epochs] [batch_size] [lr] [--topology 2,32,32,6] [--output model.kan]\n", .{args[0]});
        return;
    }

    const pcb_path = args[1];
    const epochs = if (args.len > 2) try std.fmt.parseInt(usize, args[2], 10) else 1000;
    const batch_size = if (args.len > 3) try std.fmt.parseInt(usize, args[3], 10) else 1024;
    const lr = if (args.len > 4) try std.fmt.parseFloat(f32, args[4]) else 0.001;

    var topology_list = std.ArrayList(usize).init(allocator);
    defer topology_list.deinit();
    
    var output_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--topology")) {
            i += 1;
            var it = std.mem.splitSequence(u8, args[i], ",");
            while (it.next()) |part| {
                try topology_list.append(try std.fmt.parseInt(usize, part, 10));
            }
        }
        if (std.mem.eql(u8, args[i], "--output")) {
            i += 1;
            output_path = args[i];
        }
    }

    if (topology_list.items.len == 0) {
        try topology_list.appendSlice(&[_]usize{ 2, 32, 32, 6 });
    }

    const model_path = output_path orelse "manifold.kan";

    std.debug.print("--- Universal Manifold Trainer ---\n", .{});
    std.debug.print("Dataset: {s}\n", .{pcb_path});
    std.debug.print("Topology: {any}\n", .{topology_list.items});
    std.debug.print("Output: {s}\n", .{model_path});

    var loader = try DataLoader.init(allocator, pcb_path);
    defer loader.deinit();

    try runTraining(allocator, loader, topology_list.items, epochs, batch_size, lr, model_path);
}

fn runTraining(allocator: mem.Allocator, loader: DataLoader, dims: []const usize, epochs: usize, batch_size: usize, lr: f32, model_path: []const u8) !void {
    const num_coeffs = 32;
    const trainer = try KanTrainer.initFixed(allocator, dims, num_coeffs, batch_size, .displacement);
    defer trainer.deinit();
    
    trainer.optimizer.learning_rate = lr;
    trainer.lambda_l2 = 0.0001;

    const inputs = try allocator.alloc(f32, batch_size * dims[0]);
    const targets = try allocator.alloc(f32, batch_size * dims[dims.len-1]);
    defer { allocator.free(inputs); allocator.free(targets); }

    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
    var best_loss: f32 = 1e10;

    for (0..epochs) |epoch| {
        loader.getBatch(batch_size, dims[0], dims[dims.len-1], &prng, inputs, targets);
        const batch = TrainingBatch{ .inputs = inputs, .targets = targets, .batch_size = batch_size };
        const loss = try trainer.trainStep(batch);
        
        if (epoch % 100 == 0 or epoch == epochs - 1) {
            std.debug.print("Step {d:5}: Loss = {d:0.6}\r", .{epoch, loss});
            if (loss < best_loss) {
                best_loss = loss;
                try trainer.net.saveModel(model_path);
            }
        }
    }
    std.debug.print("\nForge Training Complete. Best Loss: {d:0.6}\n", .{best_loss});
}
