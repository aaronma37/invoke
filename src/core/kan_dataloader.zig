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
        for (0..batch_size) |i| {
            const s = self.samples[rand.uintLessThan(usize, self.samples.len)];
            
            // Map inputs to AoS: [batch][dim]
            if (in_dim == 3) {
                inputs[i * 3 + 0] = s.x;
                inputs[i * 3 + 1] = s.y;
                inputs[i * 3 + 2] = s.z;
            } else if (in_dim == 2) {
                inputs[i * 2 + 0] = s.x;
                inputs[i * 2 + 1] = s.y;
            }
            
            // Map targets to AoS: [batch][dim]
            if (out_dim >= 1) targets[i * out_dim + 0] = s.sdf;
            if (out_dim >= 2) targets[i * out_dim + 1] = s.r;
            if (out_dim >= 3) targets[i * out_dim + 2] = s.g;
            if (out_dim >= 4) targets[i * out_dim + 3] = s.b;
            if (out_dim >= 5) targets[i * out_dim + 4] = s.roughness;
            if (out_dim >= 6) targets[i * out_dim + 5] = s.metallic;
        }
    }
};
