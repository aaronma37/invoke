const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const kan_trainer = @import("kan_trainer.zig");
const TrainingBatch = kan_trainer.TrainingBatch;

/// A single point sample in our high-performance binary format.
/// 9 floats = 36 bytes per point.
pub const PointSample = extern struct {
    x: f32,
    y: f32,
    z: f32,
    sdf: f32,
    r: f32,
    g: f32,
    b: f32,
    roughness: f32,
    metallic: f32,
};

/// High-performance data loader using memory-mapped files.
/// This allows us to handle datasets larger than RAM and stream data at NVMe speeds.
pub const DataLoader = struct {
    file: fs.File,
    samples: []const PointSample,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, path: []const u8) !DataLoader {
        const file = try fs.cwd().openFile(path, .{});
        const stat = try file.stat();
        
        // Memory map the file for zero-copy access
        // Note: In Zig 0.14, std.posix.mmap is used for linux
        const ptr = try std.posix.mmap(
            null,
            stat.size,
            std.posix.PROT.READ,
            .{ .TYPE = .SHARED },
            file.handle,
            0,
        );

        const samples = mem.bytesAsSlice(PointSample, ptr);

        return DataLoader{
            .file = file,
            .samples = samples,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DataLoader) void {
        const bytes = mem.sliceAsBytes(self.samples);
        // Assert page alignment for munmap
        const aligned_bytes: []align(4096) const u8 = @alignCast(bytes);
        std.posix.munmap(aligned_bytes);
        self.file.close();
    }

    /// Fetches a random batch of points for training.
    pub fn getBatch(self: DataLoader, batch_size: usize, prng: *std.Random.DefaultPrng, inputs: []f32, targets: []f32) void {
        const rand = prng.random();
        for (0..batch_size) |i| {
            const idx = rand.uintLessThan(usize, self.samples.len);
            const s = self.samples[idx];
            
            inputs[i * 3 + 0] = s.x;
            inputs[i * 3 + 1] = s.y;
            inputs[i * 3 + 2] = s.z;
            
            targets[i * 6 + 0] = s.sdf;
            targets[i * 6 + 1] = s.r;
            targets[i * 6 + 2] = s.g;
            targets[i * 6 + 3] = s.b;
            targets[i * 6 + 4] = s.roughness;
            targets[i * 6 + 5] = s.metallic;
        }
    }
};

test "DataLoader: Write and Read Check" {
    const allocator = std.testing.allocator;
    const test_path = "test_samples.pcb";

    // 1. Create a dummy dataset
    {
        const file = try fs.cwd().createFile(test_path, .{});
        defer file.close();
        var writer = file.writer();
        for (0..100) |i| {
            const s = PointSample{
                .x = @as(f32, @floatFromInt(i)),
                .y = 0, .z = 0, .sdf = 0,
                .r = 1, .g = 1, .b = 1,
                .roughness = 0.5, .metallic = 0.5,
            };
            try writer.writeStruct(s);
        }
    }
    defer fs.cwd().deleteFile(test_path) catch {};

    // 2. Load and verify
    var loader = try DataLoader.init(allocator, test_path);
    defer loader.deinit();

    try std.testing.expectEqual(@as(usize, 100), loader.samples.len);
    try std.testing.expectEqual(@as(f32, 10.0), loader.samples[10].x);
}
