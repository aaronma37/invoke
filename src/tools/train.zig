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
    const epochs = if (args.len > 2) try std.fmt.parseInt(usize, args[2], 10) else 10000;
    const batch_size = if (args.len > 3) try std.fmt.parseInt(usize, args[3], 10) else 10000;
    const lr = if (args.len > 4) try std.fmt.parseFloat(f32, args[4]) else 0.001;

    var use_eikonal = true;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--no-eikonal")) use_eikonal = false;
    }

    std.debug.print("Loading dataset: {s}...\n", .{pcb_path});
    var loader = try DataLoader.init(allocator, pcb_path);
    defer loader.deinit();

    // High Capacity for Bunny: 3 -> 32 -> 32 -> 1
    const dims = [_]usize{ 3, 32, 32, 1 }; 
    const num_coeffs = 16;
    
    // Resume if model exists, otherwise init fresh
    var trainer: KanTrainer = undefined;
    const model_exists = if (std.fs.cwd().access("model.kan", .{})) |_| true else |_| false;
    
    if (model_exists) {
        std.debug.print("Resuming from existing model.kan...\n", .{});
        const net = try KanNetwork.loadModel(allocator, "model.kan");
        trainer = try KanTrainer.initWithNet(allocator, net, batch_size);
    } else {
        std.debug.print("Initializing new KAN: 3 -> 32 -> 32 -> 1\n", .{});
        trainer = try KanTrainer.initFixed(allocator, &dims, num_coeffs, batch_size);
    }
    defer trainer.deinit();
    
    trainer.optimizer.learning_rate = lr;

    const inputs = try allocator.alloc(f32, batch_size * 3);
    const targets = try allocator.alloc(f32, batch_size * 1);
    defer { allocator.free(inputs); allocator.free(targets); }

    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
    var best_loss: f32 = 1e10;

    std.debug.print("Starting training for {d} epochs (batch size: {d}, lr: {d:0.5})...\n", .{epochs, batch_size, lr});
    
    for (0..epochs) |epoch| {
        loader.getBatch(batch_size, 1, &prng, inputs, targets);
        const batch = TrainingBatch{ .inputs = inputs, .targets = targets, .batch_size = batch_size };
        const loss = try trainer.trainStep(batch);
        
        if (epoch % 100 == 0 or epoch == epochs - 1) {
            // MULTI-PROBE: Check center and corners
            var acts = try allocator.alloc([]f32, trainer.net.layers.len + 1);
            for (0..trainer.net.layers.len) |i| acts[i] = try allocator.alloc(f32, 3 * trainer.net.layers[i].in_dim);
            acts[trainer.net.layers.len] = try allocator.alloc(f32, 3 * trainer.net.out_dim);
            defer { for (acts) |a| allocator.free(a); allocator.free(acts); }
            
            const probe_pts = [_]f32{ 
                0, 0, 0,    // Center
                1, 1, 1,    // Far Corner
                -1, -1, -1, // Near Corner
            };
            trainer.net.forward(&probe_pts, acts, 3);
            
            std.debug.print("Epoch {d:5}: Loss = {d:0.6} | Center: {d:0.3} | Corners: {d:0.3}, {d:0.3}\n", 
                .{epoch, loss, acts[trainer.net.layers.len][0], acts[trainer.net.layers.len][1], acts[trainer.net.layers.len][2]});
            
            if (loss < best_loss) {
                best_loss = loss;
                try trainer.net.saveModel("model.kan");
            }
        }
    }
    std.debug.print("\nTraining complete. Best loss: {d:0.6}. Model saved to model.kan\n", .{best_loss});
}
