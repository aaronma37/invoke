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

    /// Forward pass through the entire network.
    /// Returns intermediate activations for the backward pass.
    pub fn forward(
        self: KanNetwork,
        inputs: []const f32,
        activations: [][]f32, // [num_layers + 1][batch_size * dim]
        batch_size: usize,
    ) void {
        @memcpy(activations[0], inputs[0..(batch_size * self.layers[0].in_dim)]);
        for (0..self.layers.len) |i| {
            self.layers[i].forward(activations[i], activations[i + 1], batch_size);
        }
    }

    /// Forward pass that also stores Jacobians for each layer.
    /// jacobians: [num_layers][batch_size * out_dim * in_dim]
    pub fn forwardWithJacobians(
        self: KanNetwork,
        inputs: []const f32,
        activations: [][]f32,
        jacobians: [][]f32,
        batch_size: usize,
    ) void {
        @memcpy(activations[0], inputs[0..(batch_size * self.layers[0].in_dim)]);
        for (0..self.layers.len) |i| {
            self.layers[i].forwardWithDeriv(
                activations[i],
                activations[i + 1],
                jacobians[i],
                batch_size,
            );
        }
    }

    /// Backward pass through the entire network.
    /// out_grad: Gradient w.r.t the final output.
    /// grads: Gradient buffers for each layer's coefficients.
    /// scratch_grads: Pre-allocated buffers for backpropagating input gradients.
    pub fn backward(
        self: KanNetwork,
        activations: [][]const f32,
        out_grad: []const f32,
        layer_coeff_grads: [][]f32,
        scratch_grads: [][]f32, // [num_layers][batch_size * dim]
        batch_size: usize,
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
            );
            
            current_grad = next_grad;
        }
    }

    /// Serializes the trained network to a binary file.
    pub fn saveModel(self: KanNetwork, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        var writer = file.writer();

        // 1. Header: [num_layers, out_dim]
        try writer.writeInt(u32, @intCast(self.layers.len), .little);
        try writer.writeInt(u32, @intCast(self.out_dim), .little);

        for (self.layers) |layer| {
            // 2. Layer Meta: [in_dim, out_dim, num_coeffs]
            try writer.writeInt(u32, @intCast(layer.in_dim), .little);
            try writer.writeInt(u32, @intCast(layer.out_dim), .little);
            try writer.writeInt(u32, @intCast(layer.num_coeffs), .little);

            // 3. Knots
            try writer.writeAll(std.mem.sliceAsBytes(layer.knots));

            // 4. Coefficients
            try writer.writeAll(std.mem.sliceAsBytes(layer.coeffs));
        }
    }

    /// Loads a trained network from a binary file.
    pub fn loadModel(allocator: mem.Allocator, path: []const u8) !KanNetwork {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        var reader = file.reader();

        // 1. Header
        const num_layers = try reader.readInt(u32, .little);
        const out_dim = try reader.readInt(u32, .little);
        _ = out_dim;

        const layers = try allocator.alloc(KanLayer, num_layers);
        errdefer allocator.free(layers);

        for (0..num_layers) |i| {
            // 2. Layer Meta
            const in_d = try reader.readInt(u32, .little);
            const out_d = try reader.readInt(u32, .little);
            const n_coeffs = try reader.readInt(u32, .little);

            layers[i] = try KanLayer.init(allocator, in_d, out_d, n_coeffs);
            
            // 3. Knots
            _ = try reader.readAll(std.mem.sliceAsBytes(layers[i].knots));

            // 4. Coefficients
            _ = try reader.readAll(std.mem.sliceAsBytes(layers[i].coeffs));
        }

        return KanNetwork{
            .layers = layers,
            .out_dim = layers[num_layers - 1].out_dim,
            .allocator = allocator,
        };
    }
};

test "KanNetwork: Basic Forward/Backward" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 3, 8, 4 };
    var net = try KanNetwork.init(allocator, &dims, 4);
    defer net.deinit();

    const batch_size = 1;
    
    // Allocate activation buffers
    const activations = try allocator.alloc([]f32, dims.len);
    defer allocator.free(activations);
    for (0..dims.len) |i| {
        activations[i] = try allocator.alloc(f32, batch_size * dims[i]);
    }
    defer {
        for (activations) |act| allocator.free(act);
    }

    const inputs = [_]f32{ 0.1, 0.2, 0.3 };
    net.forward(&inputs, activations, batch_size);

    // Verify output dimension
    try std.testing.expectEqual(@as(usize, 4), activations[2].len);

    // Prepare backward pass buffers
    const out_grad = try allocator.alloc(f32, batch_size * dims[2]);
    defer allocator.free(out_grad);
    @memset(out_grad, 1.0);

    const layer_coeff_grads = try allocator.alloc([]f32, net.layers.len);
    defer allocator.free(layer_coeff_grads);
    for (0..net.layers.len) |i| {
        layer_coeff_grads[i] = try allocator.alloc(f32, net.layers[i].out_dim * net.layers[i].in_dim * net.layers[i].num_coeffs);
        @memset(layer_coeff_grads[i], 0.0);
    }
    defer {
        for (layer_coeff_grads) |g| allocator.free(g);
    }

    const scratch_grads = try allocator.alloc([]f32, net.layers.len);
    defer allocator.free(scratch_grads);
    for (0..net.layers.len) |i| {
        scratch_grads[i] = try allocator.alloc(f32, batch_size * net.layers[i].in_dim);
    }
    defer {
        for (scratch_grads) |g| allocator.free(g);
    }

    const const_activations = try allocator.alloc([]const f32, activations.len);
    defer allocator.free(const_activations);
    for (0..activations.len) |i| const_activations[i] = activations[i];

    net.backward(const_activations, out_grad, layer_coeff_grads, scratch_grads, batch_size);

    // If we reached here without crashing, the backward pass flow is correct
    try std.testing.expect(scratch_grads[0][0] != 0.0);
}
