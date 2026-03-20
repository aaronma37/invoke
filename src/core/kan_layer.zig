const std = @import("std");
const mem = std.mem;
const kan_spline = @import("kan_spline.zig");
const SplineGrid = kan_spline.SplineGrid;

pub const KanLayer = struct {
    in_dim: usize,
    out_dim: usize,
    /// Matrix of splines: [out_dim][in_dim]
    grids: []SplineGrid,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, in_dim: usize, out_dim: usize, num_coeffs: usize) !KanLayer {
        const grids = try allocator.alloc(SplineGrid, in_dim * out_dim);
        errdefer allocator.free(grids);

        for (0..grids.len) |i| {
            grids[i] = try SplineGrid.init(allocator, num_coeffs);
        }

        return KanLayer{
            .in_dim = in_dim,
            .out_dim = out_dim,
            .grids = grids,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *KanLayer) void {
        for (self.grids) |*grid| {
            grid.deinit(self.allocator);
        }
        self.allocator.free(self.grids);
    }

    /// Forward pass for the layer.
    /// inputs: [batch_size][in_dim]
    /// outputs: [batch_size][out_dim]
    pub fn forward(self: KanLayer, inputs: []const f32, outputs: []f32, batch_size: usize) void {
        @memset(outputs, 0.0);

        const SimdLen = 16; // AVX-512 target
        const Vector = @Vector(SimdLen, f32);
        
        var b: usize = 0;
        while (b + SimdLen <= batch_size) : (b += SimdLen) {
            for (0..self.out_dim) |j| {
                var out_vec = @as(Vector, @splat(0.0));
                
                for (0..self.in_dim) |i| {
                    // Extract input batch for this dimension
                    var in_vals: [SimdLen]f32 = undefined;
                    for (0..SimdLen) |v| {
                        in_vals[v] = inputs[(b + v) * self.in_dim + i];
                    }
                    const in_vec: Vector = in_vals;
                    
                    // Base activation (SiLU: x * sigmoid(x))
                    // Note: Zig's @exp handles vectors
                    const sigmoid = @as(Vector, @splat(1.0)) / (@as(Vector, @splat(1.0)) + @exp(-in_vec));
                    const silu = in_vec * sigmoid;
                    
                    // Evaluate spline batch
                    var spline_vals: [SimdLen]f32 = undefined;
                    const grid = self.grids[j * self.in_dim + i];
                    grid.evaluateBatch(in_vec, &spline_vals);
                    const spline_vec: Vector = spline_vals;
                    
                    out_vec += silu + spline_vec;
                }
                
                // Store output batch
                for (0..SimdLen) |v| {
                    outputs[(b + v) * self.out_dim + j] = out_vec[v];
                }
            }
        }

        // Handle remainder of the batch (scalar)
        while (b < batch_size) : (b += 1) {
            for (0..self.out_dim) |j| {
                var sum: f32 = 0.0;
                for (0..self.in_dim) |i| {
                    const x = inputs[b * self.in_dim + i];
                    const grid = self.grids[j * self.in_dim + i];
                    const silu = x / (1.0 + std.math.exp(-x));
                    
                    var spline_val: f32 = 0.0;
                    for (0..grid.coeffs.len) |k| {
                        spline_val += grid.coeffs[k] * kan_spline.basis(k, kan_spline.SplineConfig.Order, x, grid.knots);
                    }
                    sum += silu + spline_val;
                }
                outputs[b * self.out_dim + j] = sum;
            }
        }
    }

    /// Forward pass that also calculates the derivative of each output w.r.t each input.
    /// jacobians: [batch_size][out_dim][in_dim]
    pub fn forwardWithDeriv(
        self: KanLayer,
        inputs: []const f32,
        outputs: []f32,
        jacobians: []f32,
        batch_size: usize,
    ) void {
        @memset(outputs, 0.0);
        @memset(jacobians, 0.0);

        for (0..batch_size) |b| {
            for (0..self.out_dim) |j| {
                var sum: f32 = 0.0;
                for (0..self.in_dim) |i| {
                    const x = inputs[b * self.in_dim + i];
                    const grid = self.grids[j * self.in_dim + i];
                    
                    // Base activation derivative
                    const sigmoid = 1.0 / (1.0 + std.math.exp(-x));
                    const silu = x * sigmoid;
                    const silu_prime = sigmoid * (1.0 + x * (1.0 - sigmoid));
                    
                    // Spline and its derivative
                    var spline_val: f32 = 0.0;
                    var spline_prime: f32 = 0.0;
                    for (0..grid.coeffs.len) |k| {
                        const b_val = kan_spline.basis(k, kan_spline.SplineConfig.Order, x, grid.knots);
                        const b_prime = kan_spline.derivative(k, kan_spline.SplineConfig.Order, x, grid.knots);
                        
                        spline_val += grid.coeffs[k] * b_val;
                        spline_prime += grid.coeffs[k] * b_prime;
                    }
                    
                    sum += silu + spline_val;
                    // Store the partial derivative dy_j / dx_i
                    jacobians[(b * self.out_dim + j) * self.in_dim + i] = silu_prime + spline_prime;
                }
                outputs[b * self.out_dim + j] = sum;
            }
        }
    }

    /// Backward pass for the layer.
    /// out_grad: [batch_size][out_dim] (Error from next layer)
    /// in_grad: [batch_size][in_dim] (Error to previous layer)
    /// coeff_grads: [out_dim][in_dim][num_coeffs] (Gradient for training)
    pub fn backward(
        self: KanLayer,
        inputs: []const f32,
        out_grad: []const f32,
        in_grad: []f32,
        coeff_grads: []f32,
        batch_size: usize,
    ) void {
        @memset(in_grad, 0.0);
        // Note: coeff_grads should be accumulated or zeroed by the caller (optimizer)

        for (0..batch_size) |b| {
            for (0..self.out_dim) |j| {
                const grad_out = out_grad[b * self.out_dim + j];
                if (grad_out == 0.0) continue;

                for (0..self.in_dim) |i| {
                    const x = inputs[b * self.in_dim + i];
                    const grid = self.grids[j * self.in_dim + i];
                    const num_coeffs = grid.coeffs.len;

                    // 1. Gradient w.r.t SiLU base activation
                    const sigmoid = 1.0 / (1.0 + std.math.exp(-x));
                    const silu_prime = sigmoid * (1.0 + x * (1.0 - sigmoid));
                    
                    // 2. Gradient w.r.t Spline
                    var spline_prime: f32 = 0.0;
                    for (0..num_coeffs) |k| {
                        const b_val = kan_spline.basis(k, kan_spline.SplineConfig.Order, x, grid.knots);
                        const b_prime = kan_spline.derivative(k, kan_spline.SplineConfig.Order, x, grid.knots);
                        
                        // Accumulate gradient for coefficients
                        coeff_grads[(j * self.in_dim + i) * num_coeffs + k] += grad_out * b_val;
                        
                        spline_prime += grid.coeffs[k] * b_prime;
                    }

                    // Accumulate gradient for inputs
                    in_grad[b * self.in_dim + i] += grad_out * (silu_prime + spline_prime);
                }
            }
        }
    }
};

test "KanLayer: Basic Forward Pass" {
    const allocator = std.testing.allocator;
    var layer = try KanLayer.init(allocator, 2, 1, 4);
    defer layer.deinit();

    const inputs = [_]f32{ 0.5, 0.5 };
    var outputs = [_]f32{ 0.0 };

    layer.forward(&inputs, &outputs, 1);

    // With 0 coefficients, output should just be 2 * silu(0.5)
    const silu_05 = 0.5 / (1.0 + @exp(-0.5));
    try std.testing.expectApproxEqRel(silu_05 * 2.0, outputs[0], 1e-5);
}

test "KanLayer: SIMD Batch Forward Pass" {
    const allocator = std.testing.allocator;
    const in_dim = 3;
    const out_dim = 2;
    const batch_size = 32; // Two full SIMD chunks
    var layer = try KanLayer.init(allocator, in_dim, out_dim, 4);
    defer layer.deinit();

    // Randomize some coefficients
    for (layer.grids) |grid| {
        grid.coeffs[0] = 0.1;
        grid.coeffs[1] = -0.2;
    }

    const inputs = try allocator.alloc(f32, batch_size * in_dim);
    defer allocator.free(inputs);
    for (inputs, 0..) |*val, i| {
        val.* = @as(f32, @floatFromInt(i % 10)) / 10.0;
    }

    const outputs = try allocator.alloc(f32, batch_size * out_dim);
    defer allocator.free(outputs);

    layer.forward(inputs, outputs, batch_size);

    // Verify a sample point against scalar math
    const sample_idx = 17;
    for (0..out_dim) |j| {
        var expected: f32 = 0.0;
        for (0..in_dim) |i| {
            const x = inputs[sample_idx * in_dim + i];
            const grid = layer.grids[j * in_dim + i];
            const silu = x / (1.0 + std.math.exp(-x));
            
            var spline_val: f32 = 0.0;
            for (0..grid.coeffs.len) |k| {
                spline_val += grid.coeffs[k] * kan_spline.basis(k, kan_spline.SplineConfig.Order, x, grid.knots);
            }
            expected += silu + spline_val;
        }
        try std.testing.expectApproxEqRel(expected, outputs[sample_idx * out_dim + j], 1e-5);
    }
}

test "KanLayer: Basic Backward Pass" {
    const allocator = std.testing.allocator;
    const in_dim = 2;
    const out_dim = 1;
    const num_coeffs = 4;
    var layer = try KanLayer.init(allocator, in_dim, out_dim, num_coeffs);
    defer layer.deinit();

    // Set some coefficients
    layer.grids[0].coeffs[0] = 0.5;

    const inputs = [_]f32{ 0.5, 0.5 };
    const out_grad = [_]f32{ 1.0 };
    var in_grad = [_]f32{ 0.0, 0.0 };
    
    const coeff_grads = try allocator.alloc(f32, out_dim * in_dim * num_coeffs);
    defer allocator.free(coeff_grads);
    @memset(coeff_grads, 0.0);

    layer.backward(&inputs, &out_grad, &in_grad, coeff_grads, 1);

    // Verify coeff_grad[0,0,0] should be out_grad[0] * basis(0, 3, 0.5, knots)
    const expected_coeff_grad = 1.0 * kan_spline.basis(0, 3, 0.5, layer.grids[0].knots);
    try std.testing.expectApproxEqRel(expected_coeff_grad, coeff_grads[0], 1e-5);

    // Verify in_grad[0] should be out_grad[0] * (silu'(0.5) + spline'(0.5))
    const sigmoid = 1.0 / (1.0 + @exp(-0.5));
    const silu_prime = sigmoid * (1.0 + 0.5 * (1.0 - sigmoid));
    const spline_prime = 0.5 * kan_spline.derivative(0, 3, 0.5, layer.grids[0].knots);
    try std.testing.expectApproxEqRel(silu_prime + spline_prime, in_grad[0], 1e-5);
}
