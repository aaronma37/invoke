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
            
            // Map inputs to AoS: [batch][dim]
            if (in_dim == 3) {
                inputs[b * 3 + 0] = s.x;
                inputs[b * 3 + 1] = s.y;
                inputs[b * 3 + 2] = s.z;
            } else if (in_dim == 2) {
                inputs[b * 2 + 0] = s.x; // maps to u
                inputs[b * 2 + 1] = s.y; // maps to v
            }
            
            // Map targets to AoS: [batch][dim]
            if (in_dim == 2 and out_dim == 3) {
                // VECTOR DISPLACEMENT: UV -> (DX, DY, DZ)
                targets[b * 3 + 0] = s.r;
                targets[b * 3 + 1] = s.g;
                targets[b * 3 + 2] = s.b;
            } else {
                if (out_dim >= 1) targets[b * out_dim + 0] = s.sdf;
                if (out_dim >= 2) targets[b * out_dim + 1] = s.r;
                if (out_dim >= 3) targets[b * out_dim + 2] = s.g;
                if (out_dim >= 4) targets[b * out_dim + 3] = s.b;
                if (out_dim >= 5) targets[b * out_dim + 4] = s.roughness;
                if (out_dim >= 6) targets[b * out_dim + 5] = s.metallic;
            }
        }
    }
};

pub const MultiDataLoader = struct {
    const Model = struct {
        file: fs.File,
        samples: []const PointSample,
        label: []f32,
    };

    models: []Model,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, pcb_dir_path: []const u8, latents_json_path: []const u8) !MultiDataLoader {
        // 1. Parse Latents JSON
        const json_content = try fs.cwd().readFileAlloc(allocator, latents_json_path, 10 * 1024 * 1024);
        defer allocator.free(json_content);

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
        defer parsed.deinit();

        const root = parsed.value.object;
        
        // 2. Iterate Directory and Load Models
        var dir = try fs.cwd().openDir(pcb_dir_path, .{ .iterate = true });
        var it = dir.iterate();
        
        var models_list = std.ArrayList(Model).init(allocator);
        errdefer {
            for (models_list.items) |m| {
                std.posix.munmap(@alignCast(mem.sliceAsBytes(m.samples)));
                m.file.close();
                allocator.free(m.label);
            }
            models_list.deinit();
        }

        while (try it.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".pcb")) {
                const name_no_ext = entry.name[0 .. entry.name.len - 4];
                if (root.get(name_no_ext)) |latent_val| {
                    const file = try dir.openFile(entry.name, .{});
                    const stat = try file.stat();
                    const ptr = try std.posix.mmap(null, stat.size, std.posix.PROT.READ, .{ .TYPE = .SHARED }, file.handle, 0);
                    
                    const latent_arr = latent_val.array;
                    const label = try allocator.alloc(f32, latent_arr.items.len);
                    for (latent_arr.items, 0..) |v, i| label[i] = @as(f32, @floatCast(v.float));

                    try models_list.append(.{
                        .file = file,
                        .samples = mem.bytesAsSlice(PointSample, ptr),
                        .label = label,
                    });
                }
            }
        }

        std.debug.print("MultiDataLoader: Loaded {d} models from {s}\n", .{models_list.items.len, pcb_dir_path});
        return MultiDataLoader{ .models = try models_list.toOwnedSlice(), .allocator = allocator };
    }

    pub fn deinit(self: *MultiDataLoader) void {
        for (self.models) |m| {
            std.posix.munmap(@alignCast(mem.sliceAsBytes(m.samples)));
            m.file.close();
            self.allocator.free(m.label);
        }
        self.allocator.free(self.models);
    }

    pub fn getBatch(self: MultiDataLoader, batch_size: usize, in_dim: usize, out_dim: usize, prng: *std.Random.DefaultPrng, inputs: []f32, targets: []f32) void {
        const rand = prng.random();
        const latent_dim = if (in_dim > 2) in_dim - 2 else 0;

        for (0..batch_size) |b| {
            // Pick a random model
            const m = self.models[rand.uintLessThan(usize, self.models.len)];
            // Pick a random point in that model
            const s = m.samples[rand.uintLessThan(usize, m.samples.len)];
            
            // Input: [U, V, Latents...]
            inputs[b * in_dim + 0] = s.x; // U
            inputs[b * in_dim + 1] = s.y; // V
            for (0..latent_dim) |i| {
                inputs[b * in_dim + 2 + i] = m.label[i];
            }
            
            // Output: [dX, dY, dZ]
            if (out_dim == 3) {
                targets[b * 3 + 0] = s.r;
                targets[b * 3 + 1] = s.g;
                targets[b * 3 + 2] = s.b;
            } else {
                targets[b * out_dim + 0] = s.sdf;
            }
        }
    }
};
