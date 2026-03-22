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

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <dataset.pcb> [epochs] [batch_size] [learning_rate] [--task sdf|displacement]\n", .{args[0]});
        return;
    }

    const pcb_path = args[1];
    const epochs = if (args.len > 2) try std.fmt.parseInt(usize, args[2], 10) else 10000;
    const batch_size = if (args.len > 3) try std.fmt.parseInt(usize, args[3], 10) else 10000;
    const lr = if (args.len > 4) try std.fmt.parseFloat(f32, args[4]) else 0.001;

    var task: kan.kan_trainer.TaskType = .sdf;
    var use_eikonal = true;
    var custom_model_path: ?[]const u8 = null;

    var arg_i: usize = 0;
    while (arg_i < args.len) : (arg_i += 1) {
        const arg = args[arg_i];
        if (std.mem.eql(u8, arg, "--no-eikonal")) use_eikonal = false;
        if (std.mem.eql(u8, arg, "displacement")) task = .displacement;
        if (std.mem.eql(u8, arg, "--output")) {
            if (arg_i + 1 < args.len) {
                arg_i += 1;
                custom_model_path = args[arg_i];
            }
        }
    }

    const model_path = custom_model_path orelse if (task == .sdf) "model_sdf.kan" else "model_disp.kan";

    std.debug.print("Task: {s}\n", .{@tagName(task)});
    std.debug.print("Model Path: {s}\n", .{model_path});
    std.debug.print("Loading dataset: {s}...\n", .{pcb_path});
    var loader = try DataLoader.init(allocator, pcb_path);
    defer loader.deinit();

    const dims_sdf = [_]usize{ 3, 32, 32, 1 };
    const dims_disp = [_]usize{ 2, 32, 1 };
    const dims: []const usize = if (task == .sdf) &dims_sdf else &dims_disp;
    const num_coeffs = 8;
    
    // Resume if model exists, otherwise init fresh
    var trainer: *KanTrainer = undefined;
    const model_exists = if (std.fs.cwd().access(model_path, .{})) |_| true else |_| false;
    
    if (model_exists) {
        std.debug.print("Resuming from existing {s}...\n", .{model_path});
        const net = try KanNetwork.loadModel(allocator, model_path);
        trainer = try KanTrainer.initWithNet(allocator, net, batch_size, task);
    } else {
        std.debug.print("Initializing new KAN: {d} -> ... -> {d}\n", .{dims[0], dims[dims.len-1]});
        trainer = try KanTrainer.initFixed(allocator, dims, num_coeffs, batch_size, task);
    }
    defer trainer.deinit();
    
    trainer.lambda_shape = 10.0;
    trainer.optimizer.learning_rate = lr;

    const inputs = try allocator.alloc(f32, batch_size * dims[0]);
    const targets = try allocator.alloc(f32, batch_size * dims[dims.len-1]);
    defer { allocator.free(inputs); allocator.free(targets); }

    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
    var best_loss: f32 = 1e10;

    std.debug.print("Starting training for {d} epochs (batch size: {d}, lr: {d:0.5})...\n", .{epochs, batch_size, lr});
    
    for (0..epochs) |epoch| {
        loader.getBatch(batch_size, dims[0], dims[dims.len-1], &prng, inputs, targets);
        const batch = TrainingBatch{ .inputs = inputs, .targets = targets, .batch_size = batch_size };
        const loss = try trainer.trainStep(batch);
        
        if (epoch % 100 == 0 or epoch == epochs - 1) {
            std.debug.print("Epoch {d:5}: Loss = {d:0.6}\r", .{epoch, loss});
            
            if (loss < best_loss) {
                best_loss = loss;
                try trainer.net.saveModel(model_path);
            }
        }
    }
    std.debug.print("\nTraining complete. Best loss: {d:0.6}. Model saved to {s}\n", .{best_loss, model_path});
}
