const std = @import("std");
const mem = std.mem;
const kan_spline = @import("kan_spline.zig");

pub const KanLayer = struct {
    in_dim: usize,
    out_dim: usize,
    num_coeffs: usize,
    /// Flat coefficient buffer: [in_dim][num_coeffs][out_dim]
    /// Aligned to 64 bytes for AVX-512.
    coeffs: []align(kan_spline.SplineConfig.Alignment) f32,
    knots: []f32,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, in_dim: usize, out_dim: usize, num_coeffs: usize) !KanLayer {
        const p = kan_spline.SplineConfig.Order;
        const num_knots = num_coeffs + p + 1;

        const coeffs = try allocator.alignedAlloc(f32, kan_spline.SplineConfig.Alignment, in_dim * num_coeffs * out_dim);
        errdefer allocator.free(coeffs);
        @memset(coeffs, 0.0);

        const knots = try allocator.alloc(f32, num_knots);
        errdefer allocator.free(knots);
        for (knots, 0..) |*k, i| {
            k.* = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_knots - 1));
        }

        return KanLayer{
            .in_dim = in_dim,
            .out_dim = out_dim,
            .num_coeffs = num_coeffs,
            .coeffs = coeffs,
            .knots = knots,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *KanLayer) void {
        self.allocator.free(self.coeffs);
        self.allocator.free(self.knots);
    }

    /// Forward pass (SoA Optimized).
    pub fn forward(self: KanLayer, inputs: []const f32, outputs: []f32, batch_size: usize) void {
        const out_dim = self.out_dim;
        const in_dim = self.in_dim;
        const num_coeffs = self.num_coeffs;

        @memset(outputs[0..(batch_size * out_dim)], 0.0);

        for (0..batch_size) |b| {
            const batch_out = outputs[b * out_dim .. (b + 1) * out_dim];
            
            for (0..in_dim) |i| {
                const x = inputs[b * in_dim + i];
                
                // 1. Base activation (SiLU)
                const sigmoid = 1.0 / (1.0 + std.math.exp(-x));
                const silu = x * sigmoid;
                for (batch_out) |*out| out.* += silu;

                // 2. Spline Evaluation (SoA)
                const layer_coeffs_base = i * num_coeffs * out_dim;
                
                var j: usize = 0;
                while (j + 16 <= out_dim) : (j += 16) {
                    const Vector = @Vector(16, f32);
                    var sums = @as(Vector, @splat(0.0));
                    for (0..num_coeffs) |k| {
                        const b_val = kan_spline.basis(k, kan_spline.SplineConfig.Order, x, self.knots);
                        if (b_val == 0.0) continue;
                        const b_vec = @as(Vector, @splat(b_val));
                        const c_vec: Vector = self.coeffs[layer_coeffs_base + k * out_dim + j ..][0..16].*;
                        sums += b_vec * c_vec;
                    }
                    for (0..16) |v| batch_out[j + v] += sums[v];
                }
                
                // Handle remainder
                while (j < out_dim) : (j += 1) {
                    var spline_val: f32 = 0.0;
                    for (0..num_coeffs) |k| {
                        const b_val = kan_spline.basis(k, kan_spline.SplineConfig.Order, x, self.knots);
                        spline_val += b_val * self.coeffs[layer_coeffs_base + k * out_dim + j];
                    }
                    batch_out[j] += spline_val;
                }
            }
        }
    }

    /// Forward pass with Jacobians (SoA Optimized + SIMD).
    pub fn forwardWithDeriv(
        self: KanLayer,
        inputs: []const f32,
        outputs: []f32,
        jacobians: []f32,
        batch_size: usize,
    ) void {
        const out_dim = self.out_dim;
        const in_dim = self.in_dim;
        const num_coeffs = self.num_coeffs;
        const Vector = @Vector(16, f32);

        @memset(outputs[0..(batch_size * out_dim)], 0.0);
        @memset(jacobians[0..(batch_size * out_dim * in_dim)], 0.0);

        for (0..batch_size) |b| {
            const batch_out = outputs[b * out_dim .. (b + 1) * out_dim];
            
            for (0..in_dim) |i| {
                const x = inputs[b * in_dim + i];
                const sigmoid = 1.0 / (1.0 + std.math.exp(-x));
                const silu = x * sigmoid;
                const silu_prime = sigmoid * (1.0 + x * (1.0 - sigmoid));

                for (batch_out) |*out| out.* += silu;
                for (0..out_dim) |j| {
                    jacobians[(b * out_dim + j) * in_dim + i] += silu_prime;
                }

                const layer_coeffs_base = i * num_coeffs * out_dim;
                
                for (0..num_coeffs) |k| {
                    const b_val = kan_spline.basis(k, kan_spline.SplineConfig.Order, x, self.knots);
                    const b_prime = kan_spline.derivative(k, kan_spline.SplineConfig.Order, x, self.knots);
                    if (b_val == 0.0 and b_prime == 0.0) continue;

                    const b_vec = @as(Vector, @splat(b_val));

                    var j: usize = 0;
                    while (j + 16 <= out_dim) : (j += 16) {
                        const c_vec: Vector = self.coeffs[layer_coeffs_base + k * out_dim + j ..][0..16].*;
                        const out_v: Vector = batch_out[j..][0..16].*;
                        @as(*[16]f32, @ptrCast(batch_out[j..].ptr)).* = out_v + b_vec * c_vec;

                        for (0..16) |v| {
                            jacobians[(b * out_dim + j + v) * in_dim + i] += b_prime * c_vec[v];
                        }
                    }
                    
                    while (j < out_dim) : (j += 1) {
                        const coeff = self.coeffs[layer_coeffs_base + k * out_dim + j];
                        batch_out[j] += b_val * coeff;
                        jacobians[(b * out_dim + j) * in_dim + i] += b_prime * coeff;
                    }
                }
            }
        }
    }

    pub fn backward(
        self: KanLayer,
        inputs: []const f32,
        out_grad: []const f32,
        in_grad: []f32,
        coeff_grads: []f32,
        batch_size: usize,
    ) void {
        const out_dim = self.out_dim;
        const in_dim = self.in_dim;
        const num_coeffs = self.num_coeffs;
        const Vector = @Vector(16, f32);

        @memset(in_grad[0..(batch_size * in_dim)], 0.0);

        for (0..batch_size) |b| {
            const batch_out_grad = out_grad[b * out_dim .. (b + 1) * out_dim];
            
            for (0..in_dim) |i| {
                const x = inputs[b * in_dim + i];
                const sigmoid = 1.0 / (1.0 + std.math.exp(-x));
                const silu_prime = sigmoid * (1.0 + x * (1.0 - sigmoid));
                
                var spline_prime_total: f32 = 0.0;
                const layer_coeffs_base = i * num_coeffs * out_dim;
                
                for (0..num_coeffs) |k| {
                    const b_val = kan_spline.basis(k, kan_spline.SplineConfig.Order, x, self.knots);
                    const b_prime = kan_spline.derivative(k, kan_spline.SplineConfig.Order, x, self.knots);
                    if (b_val == 0.0 and b_prime == 0.0) continue;

                    const b_vec = @as(Vector, @splat(b_val));
                    const bp_vec = @as(Vector, @splat(b_prime));

                    var j: usize = 0;
                    while (j + 16 <= out_dim) : (j += 16) {
                        const og_vec: Vector = batch_out_grad[j..][0..16].*;
                        const c_vec: Vector = self.coeffs[layer_coeffs_base + k * out_dim + j ..][0..16].*;
                        
                        const cg_v: Vector = coeff_grads[layer_coeffs_base + k * out_dim + j ..][0..16].*;
                        @as(*[16]f32, @ptrCast(coeff_grads[layer_coeffs_base + k * out_dim + j ..].ptr)).* = cg_v + og_vec * b_vec;

                        const sp_vec = og_vec * c_vec * bp_vec;
                        spline_prime_total += @reduce(.Add, sp_vec);
                    }
                    
                    while (j < out_dim) : (j += 1) {
                        const grad_out = batch_out_grad[j];
                        const coeff = self.coeffs[layer_coeffs_base + k * out_dim + j];
                        coeff_grads[layer_coeffs_base + k * out_dim + j] += grad_out * b_val;
                        spline_prime_total += grad_out * coeff * b_prime;
                    }
                }

                var grad_out_sum: f32 = 0.0;
                for (batch_out_grad) |g| grad_out_sum += g;

                in_grad[b * in_dim + i] = grad_out_sum * silu_prime + spline_prime_total;
            }
        }
    }
};

test "KanLayer SoA: Basic Forward" {
    const allocator = std.testing.allocator;
    var layer = try KanLayer.init(allocator, 2, 1, 4);
    defer layer.deinit();

    const inputs = [_]f32{ 0.5, 0.5 };
    const outputs = try allocator.alloc(f32, 1);
    defer allocator.free(outputs);

    layer.forward(&inputs, outputs, 1);
    const silu_05 = 0.5 / (1.0 + @exp(-0.5));
    try std.testing.expectApproxEqRel(silu_05 * 2.0, outputs[0], 1e-5);
}
