const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const kan_trainer = @import("kan_trainer.zig");
const TrainingBatch = kan_trainer.TrainingBatch;

pub const PointSample = extern struct {
    x: f32, y: f32, z: f32,
    sdf: f32,
    r: f32, g: f32, b: f32,
    roughness: f32,
    metallic: f32,
};

pub const DataLoader = struct {
    file: fs.File,
    samples: []const PointSample,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, path: []const u8) !DataLoader {
        const file = try fs.cwd().openFile(path, .{});
        const stat = try file.stat();
        const ptr = try std.posix.mmap(null, stat.size, std.posix.PROT.READ, .{ .TYPE = .SHARED }, file.handle, 0);
        return DataLoader{ .file = file, .samples = mem.bytesAsSlice(PointSample, ptr), .allocator = allocator };
    }

    pub fn deinit(self: *DataLoader) void {
        std.posix.munmap(@alignCast(mem.sliceAsBytes(self.samples)));
        self.file.close();
    }

    pub fn getBatch(self: DataLoader, batch_size: usize, in_dim: usize, out_dim: usize, prng: *std.Random.DefaultPrng, inputs: []f32, targets: []f32) void {
        const rand = prng.random();
        for (0..batch_size) |b| {
            const s = self.samples[rand.uintLessThan(usize, self.samples.len)];
            
            // Map inputs to SoA: [dim][batch]
            if (in_dim == 3) {
                inputs[0 * batch_size + b] = s.x;
                inputs[1 * batch_size + b] = s.y;
                inputs[2 * batch_size + b] = s.z;
            } else if (in_dim == 2) {
                inputs[0 * batch_size + b] = s.x; // maps to u
                inputs[1 * batch_size + b] = s.y; // maps to v
            }
            
            // Map targets to SoA: [dim][batch]
            if (out_dim >= 1) targets[0 * batch_size + b] = s.sdf;
            if (out_dim >= 2) targets[1 * batch_size + b] = s.r;
            if (out_dim >= 3) targets[2 * batch_size + b] = s.g;
            if (out_dim >= 4) targets[3 * batch_size + b] = s.b;
            if (out_dim >= 5) targets[4 * batch_size + b] = s.roughness;
            if (out_dim >= 6) targets[5 * batch_size + b] = s.metallic;
        }
    }
};
