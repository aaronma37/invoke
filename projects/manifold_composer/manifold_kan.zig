const std = @import("std");
const mem = std.mem;
const core = @import("core");
const KanLayer = core.KanLayer;
const TensorSurface = core.tensor_spline.TensorSurface;

pub const BoundarySpline = struct {
    num_points: usize,
    points: []const [3]f32,
};

pub const TopologyType = enum {
    open,
    periodic_u, // Tube
    periodic_uv, // Torus
    capped,
};

pub const ManifoldNetwork = struct {
    hidden_layers: []KanLayer,
    output_surface: TensorSurface,
    topology_type: TopologyType = .open,
    allocator: mem.Allocator,
    
    top_socket: ?BoundarySpline = null,
    bottom_socket: ?BoundarySpline = null,

    pub fn init(allocator: mem.Allocator, hidden_dims: []const usize, num_coeffs: usize) !ManifoldNetwork {
        const layers = try allocator.alloc(KanLayer, hidden_dims.len - 1);
        errdefer allocator.free(layers);

        for (0..layers.len) |i| {
            layers[i] = try KanLayer.init(allocator, hidden_dims[i], hidden_dims[i + 1], num_coeffs, 0.0, 1.0);
        }

        const out_surface = try TensorSurface.init(allocator, num_coeffs, num_coeffs, 3);

        return ManifoldNetwork{
            .hidden_layers = layers,
            .output_surface = out_surface,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ManifoldNetwork) void {
        for (self.hidden_layers) |*layer| {
            layer.deinit();
        }
        self.allocator.free(self.hidden_layers);
        self.output_surface.deinit();
    }

    pub fn forwardPinned(
        self: *ManifoldNetwork,
        inputs: []const f32,
        activations: [][]f32,
        batch_size: usize,
        outputs: []f32
    ) void {
        var current_input = inputs;
        for (0..self.hidden_layers.len) |i| {
            self.hidden_layers[i].forward(current_input, activations[i + 1], batch_size);
            current_input = activations[i + 1];
        }

        // 1. PIN VERTICAL WELDS (Parent to Child)
        if (self.bottom_socket) |socket| {
            self.output_surface.pinRow(0, socket.points);
        }
        if (self.top_socket) |socket| {
            self.output_surface.pinRow(self.output_surface.num_v - 1, socket.points);
        }

        // 2. PIN HORIZONTAL SEAMS (Topology Closure)
        const is_periodic_u = (self.topology_type == .periodic_u);
        if (is_periodic_u) {
            const n_u = self.output_surface.num_u;
            const n_v = self.output_surface.num_v;
            const dim = self.output_surface.out_dim;
            for (0..n_v) |v_idx| {
                const first_idx = (v_idx * n_u + 0) * dim;
                const last_idx  = (v_idx * n_u + (n_u - 1)) * dim;
                self.output_surface.coeffs[last_idx + 0] = self.output_surface.coeffs[first_idx + 0];
                self.output_surface.coeffs[last_idx + 1] = self.output_surface.coeffs[first_idx + 1];
                self.output_surface.coeffs[last_idx + 2] = self.output_surface.coeffs[first_idx + 2];
            }
        }

        // 3. Final Evaluation (HARDENED with Topology-Aware Wrapping)
        for (0..batch_size) |b| {
            const u = inputs[b * 2 + 0];
            const v = inputs[b * 2 + 1];
            self.output_surface.evaluate(u, v, is_periodic_u, outputs[b * 3 .. (b + 1) * 3]);
        }
    }

    pub fn backwardPinned(
        self: *ManifoldNetwork,
        inputs: []const f32,
        output_grads: []const f32,
        batch_size: usize,
    ) void {
        const is_periodic_u = (self.topology_type == .periodic_u);
        
        // Train only the TensorSurface coefficients for now
        // coeff_grads for the TensorSurface are its own memory block in a real trainer
        // But here we'll assume we are accumulating directly for simplicity in testing
        for (0..batch_size) |b| {
            const u = inputs[b * 2 + 0];
            const v = inputs[b * 2 + 1];
            const grads = output_grads[b * 3 .. (b + 1) * 3];
            
            // Note: In a real multi-threaded trainer, we'd use a gradient buffer.
            // For this unit test verification, we update coeffs directly (SGD-style).
            self.output_surface.backward(u, v, is_periodic_u, grads, self.output_surface.coeffs);
        }
    }
};

test "ManifoldNetwork: Periodic Closure" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 2, 4 };
    var net = try ManifoldNetwork.init(allocator, &dims, 8);
    defer net.deinit();
    net.topology_type = .periodic_u;

    net.output_surface.coeffs[0] = 42.0;

    const inputs = [_]f32{ 0.0, 0.5, 1.0, 0.5 };
    var acts = try allocator.alloc([]f32, 2);
    defer allocator.free(acts);
    acts[0] = try allocator.alloc(f32, 4);
    acts[1] = try allocator.alloc(f32, 8);
    defer { for (acts) |a| allocator.free(a); }

    const outputs = try allocator.alloc(f32, 6);
    defer allocator.free(outputs);

    net.forwardPinned(&inputs, acts, 2, outputs);

    try std.testing.expectEqual(outputs[0], outputs[3]);
    try std.testing.expectEqual(outputs[1], outputs[4]);
    try std.testing.expectEqual(outputs[2], outputs[5]);
}

test "ManifoldNetwork: Shape Learning (SGD Sanity)" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 2, 4 };
    var net = try ManifoldNetwork.init(allocator, &dims, 8);
    defer net.deinit();

    // Target: A point at UV(0.5, 0.5) should be at XYZ(10, 20, 30)
    const input = [_]f32{ 0.5, 0.5 };
    const target = [_]f32{ 10.0, 20.0, 30.0 };
    
    // Train for 100 iterations (Basic SGD)
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var out = [_]f32{ 0, 0, 0 };
        // Empty activations for hidden layers (not used in this test)
        var acts = try allocator.alloc([]f32, 2);
        acts[0] = try allocator.alloc(f32, 2);
        acts[1] = try allocator.alloc(f32, 4);
        defer { for (acts) |a| allocator.free(a); allocator.free(acts); }

        net.forwardPinned(&input, acts, 1, &out);
        
        // Loss gradient: (pred - target)
        const grads = [_]f32{ 
            (out[0] - target[0]) * 0.1, 
            (out[1] - target[1]) * 0.1, 
            (out[2] - target[2]) * 0.1 
        };
        
        // We use a large learning rate (0.1) to see quick convergence
        net.backwardPinned(&input, &grads, 1);
    }

    // Verify convergence
    var final_out = [_]f32{ 0, 0, 0 };
    var acts_final = try allocator.alloc([]f32, 2);
    acts_final[0] = try allocator.alloc(f32, 2);
    acts_final[1] = try allocator.alloc(f32, 4);
    defer { for (acts_final) |a| allocator.free(a); allocator.free(acts_final); }

    net.forwardPinned(&input, acts_final, 1, &final_out);

    try std.testing.expectApproxEqAbs(@as(f32, 10.0), final_out[0], 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), final_out[1], 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), final_out[2], 0.1);
}
