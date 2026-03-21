const std = @import("std");
const mem = std.mem;
const kan_layer = @import("kan_layer.zig");
const KanLayer = kan_layer.KanLayer;

pub const kan_trainer = @import("kan_trainer.zig");
pub const kan_dataloader = @import("kan_dataloader.zig");

pub const KanNetwork = struct {
    layers: []KanLayer,
    out_dim: usize,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, layer_dims: []const usize, num_coeffs: usize) !KanNetwork {
        const layers = try allocator.alloc(KanLayer, layer_dims.len - 1);
        errdefer allocator.free(layers);

        for (0..layers.len) |i| {
            layers[i] = try KanLayer.init(allocator, layer_dims[i], layer_dims[i + 1], num_coeffs);
        }

        return KanNetwork{
            .layers = layers,
            .out_dim = layer_dims[layer_dims.len - 1],
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *KanNetwork) void {
        for (self.layers) |*layer| {
            layer.deinit();
        }
        self.allocator.free(self.layers);
    }

    pub fn forward(
        self: KanNetwork,
        inputs: []const f32,
        activations: [][]f32,
        batch_size: usize,
    ) void {
        var current_input = inputs;
        for (0..self.layers.len) |i| {
            self.layers[i].forward(current_input, activations[i + 1], batch_size);
            current_input = activations[i + 1];
        }
    }

    pub fn forwardWithJacobians(
        self: KanNetwork,
        inputs: []const f32,
        activations: [][]f32,
        jacobians: [][]f32,
        batch_size: usize,
    ) void {
        var current_input = inputs;
        for (0..self.layers.len) |i| {
            self.layers[i].forwardWithDeriv(
                current_input,
                activations[i + 1],
                jacobians[i],
                batch_size,
            );
            current_input = activations[i+1];
        }
    }

    pub fn backward(
        self: KanNetwork,
        activations: [][]const f32,
        out_grad: []const f32,
        layer_coeff_grads: [][]f32,
        scratch_grads: [][]f32,
        batch_size: usize,
        bucket_scratch: []f32,
    ) void {
        var current_grad = out_grad;
        var i: usize = self.layers.len;
        while (i > 0) : (i -= 1) {
            const layer_idx = i - 1;
            const layer = self.layers[layer_idx];
            const next_grad = scratch_grads[layer_idx];
            layer.backward(
                activations[layer_idx],
                current_grad,
                next_grad,
                layer_coeff_grads[layer_idx],
                batch_size,
                bucket_scratch,
            );
            current_grad = next_grad;
        }
    }

    pub fn saveModel(self: KanNetwork, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        var writer = file.writer();

        try writer.writeInt(u32, @intCast(self.layers.len), .little);
        try writer.writeInt(u32, @intCast(self.out_dim), .little);

        for (self.layers) |layer| {
            try writer.writeInt(u32, @intCast(layer.in_dim), .little);
            try writer.writeInt(u32, @intCast(layer.out_dim), .little);
            try writer.writeInt(u32, @intCast(layer.num_coeffs), .little);
            try writer.writeAll(mem.sliceAsBytes(layer.knots));
            try writer.writeAll(mem.sliceAsBytes(layer.coeffs));
        }
    }

    pub fn loadModel(allocator: mem.Allocator, path: []const u8) !KanNetwork {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        var reader = file.reader();

        const num_layers = try reader.readInt(u32, .little);
        const out_dim = try reader.readInt(u32, .little);
        _ = out_dim;

        const layers = try allocator.alloc(KanLayer, num_layers);
        for (0..num_layers) |i| {
            const in_d = try reader.readInt(u32, .little);
            const out_d = try reader.readInt(u32, .little);
            const n_coeffs = try reader.readInt(u32, .little);

            layers[i] = try KanLayer.init(allocator, in_d, out_d, n_coeffs);
            _ = try reader.readAll(mem.sliceAsBytes(layers[i].knots));
            _ = try reader.readAll(mem.sliceAsBytes(layers[i].coeffs));
        }

        return KanNetwork{
            .layers = layers,
            .out_dim = layers[num_layers - 1].out_dim,
            .allocator = allocator,
        };
    }
};
