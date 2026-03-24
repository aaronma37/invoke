const std = @import("std");
const mem = std.mem;

/// Point Sample Layout (Consistent with established high-performance AoS kernels).
/// [u, v, x, y, z, c1, c2, c3]
pub const PointSample = struct {
    u: f32, v: f32,
    x: f32, y: f32, z: f32,
    c1: f32, c2: f32, c3: f32,
};

pub const DataLoader = struct {
    file: std.fs.File,
    samples: []const PointSample,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, path: []const u8) !DataLoader {
        const file = try std.fs.cwd().openFile(path, .{});
        const stat = try file.stat();
        const ptr = try std.posix.mmap(null, stat.size, std.posix.PROT.READ, .{ .TYPE = .SHARED }, file.handle, 0);
        
        return DataLoader{
            .file = file,
            .samples = mem.bytesAsSlice(PointSample, ptr),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DataLoader) void {
        std.posix.munmap(@alignCast(mem.sliceAsBytes(self.samples)));
        self.file.close();
    }

    pub fn getBatch(self: DataLoader, batch_size: usize, in_dim: usize, out_dim: usize, prng: *std.Random.DefaultPrng, inputs: []f32, targets: []f32) void {
        const rand = prng.random();
        for (0..batch_size) |i| {
            const s = self.samples[rand.uintLessThan(usize, self.samples.len)];
            
            // Input: Interleaved (u, v, latents...)
            inputs[i * in_dim + 0] = s.u;
            inputs[i * in_dim + 1] = s.v;
            // (Hidden latents would go here)

            // Output: Interleaved (x, y, z, c1, c2, c3)
            targets[i * out_dim + 0] = s.x;
            targets[i * out_dim + 1] = s.y;
            targets[i * out_dim + 2] = s.z;
            if (out_dim >= 4) targets[i * out_dim + 3] = s.c1;
            if (out_dim >= 5) targets[i * out_dim + 4] = s.c2;
            if (out_dim >= 6) targets[i * out_dim + 5] = s.c3;
        }
    }
};
