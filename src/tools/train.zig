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
        std.debug.print("Usage: {s} <dataset.pcb> [epochs] [batch_size] [learning_rate]\n", .{args[0]});
        return;
    }

    const pcb_path = args[1];
    const epochs = if (args.len > 2) try std.fmt.parseInt(usize, args[2], 10) else 1000;
    const batch_size = if (args.len > 3) try std.fmt.parseInt(usize, args[3], 10) else 10000;
    const lr = if (args.len > 4) try std.fmt.parseFloat(f32, args[4]) else 0.001;

    var use_eikonal = true;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--no-eikonal")) use_eikonal = false;
    }

    std.debug.print("Loading dataset: {s}...\n", .{pcb_path});
    var loader = try DataLoader.init(allocator, pcb_path);
    defer loader.deinit();

    const dims = [_]usize{ 3, 32, 32, 6 }; // Reverted back to 6 outputs
    const num_coeffs = 16;
    
    std.debug.print("Initializing KAN: 3 -> 32 -> 32 -> 6 (coeffs: {d}, eikonal: {s})\n", .{num_coeffs, if (use_eikonal) "ON" else "OFF"});
    var trainer = try KanTrainer.initFixed(allocator, &dims, num_coeffs, batch_size);
    defer trainer.deinit();
    
    trainer.lambda_eikonal = if (use_eikonal) 0.1 else 0.0;
    trainer.optimizer.learning_rate = lr;

    const inputs = try allocator.alloc(f32, batch_size * 3);
    const targets = try allocator.alloc(f32, batch_size * 6);
    defer { allocator.free(inputs); allocator.free(targets); }

    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
    
    var best_loss: f32 = 1e10;

    std.debug.print("Starting training for {d} epochs (batch size: {d}, lr: {d:0.4})...\n", .{epochs, batch_size, lr});
    
    for (0..epochs) |epoch| {
        loader.getBatch(batch_size, &prng, inputs, targets);
        const batch = TrainingBatch{ .inputs = inputs, .targets = targets, .batch_size = batch_size };
        
        const loss = try trainer.trainStep(batch);
        
        if (epoch % 100 == 0 or epoch == epochs - 1) {
            std.debug.print("Epoch {d:5}: Loss = {d:0.6}\n", .{epoch, loss});
            
            if (loss < best_loss) {
                best_loss = loss;
                try trainer.net.saveModel("model.kan");
            }
        }
    }

    std.debug.print("\nTraining complete. Best loss: {d:0.6}. Model saved to model.kan\n", .{best_loss});
}
