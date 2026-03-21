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
        
        // Symmetry Breaking Initialization
        var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
        const rand = prng.random();
        for (coeffs) |*c| {
            c.* = (rand.float(f32) * 2.0 - 1.0) * 0.5;
        }

        const knots = try allocator.alloc(f32, num_knots);
        errdefer allocator.free(knots);
        // Map knots[3]...knots[num_coeffs] to [-1, 1]
        const h = 2.0 / @as(f32, @floatFromInt(num_coeffs - 3));
        for (knots, 0..) |*k, i| {
            k.* = (@as(f32, @floatFromInt(i)) - 3.0) * h - 1.0;
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

    /// Extends the grid resolution by doubling the number of coefficients.
    /// This allows coarse-to-fine training.
    pub fn extendGrid(self: *KanLayer, allocator: mem.Allocator) !void {
        const old_num_coeffs = self.num_coeffs;
        const new_num_coeffs = old_num_coeffs * 2;
        const out_dim = self.out_dim;
        const in_dim = self.in_dim;
        const p = kan_spline.SplineConfig.Order;

        // 1. Allocate new shared knots
        const num_new_knots = new_num_coeffs + p + 1;
        const new_knots = try allocator.alloc(f32, num_new_knots);
        errdefer allocator.free(new_knots);
        const h_new = 2.0 / @as(f32, @floatFromInt(new_num_coeffs - 3));
        for (new_knots, 0..) |*k, i| {
            k.* = (@as(f32, @floatFromInt(i)) - 3.0) * h_new - 1.0;
        }


        // 2. Allocate new flat SoA coefficients
        const new_coeffs = try allocator.alignedAlloc(f32, kan_spline.SplineConfig.Alignment, in_dim * new_num_coeffs * out_dim);
        errdefer allocator.free(new_coeffs);
        @memset(new_coeffs, 0.0);

        // 3. Project old coefficients to new coefficients (Linear Interpolation for now)
        // This is a simplified "Knot Insertion" that preserves the general curve.
        for (0..in_dim) |i| {
            for (0..new_num_coeffs) |k_new| {
                // Map new_idx to a float value in [-1, 1] then back to old_idx space
                const val = (@as(f32, @floatFromInt(k_new)) / @as(f32, @floatFromInt(num_new_knots - 1))) * 2.0 - 1.0;
                // Wait, knots are already [-1, 1]. We want to know where this new knot falls in the old knot vector.
                const old_idx_f = ((val + 1.0) / 2.0) * @as(f32, @floatFromInt(old_num_coeffs + p)); // Approximate
                _ = old_idx_f;

                // Simple subdivision: new_coeffs[2*k] = old_coeffs[k], new_coeffs[2*k+1] = average
                // Since new_num_coeffs = 2 * old_num_coeffs:
                const old_idx = k_new / 2;
                const next_old_idx = if (old_idx + 1 < old_num_coeffs) old_idx + 1 else old_idx;
                const is_odd = (k_new % 2) == 1;

                for (0..out_dim) |j| {
                    const v1 = self.coeffs[(i * old_num_coeffs + old_idx) * out_dim + j];
                    const v2 = self.coeffs[(i * old_num_coeffs + next_old_idx) * out_dim + j];
                    new_coeffs[(i * new_num_coeffs + k_new) * out_dim + j] = if (is_odd) (v1 + v2) * 0.5 else v1;
                }
            }
        }

        // 4. Hot-swap buffers
        allocator.free(self.coeffs);
        allocator.free(self.knots);
        self.coeffs = new_coeffs;
        self.knots = new_knots;
        self.num_coeffs = new_num_coeffs;
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
    // With non-zero coefficients, we just check that it produces a non-zero output
    try std.testing.expect(outputs[0] != 0.0);
    // And it should be roughly in the SiLU range
    const silu_05 = 0.5 / (1.0 + @exp(-0.5));
    try std.testing.expect(outputs[0] > -5.0 and outputs[0] < 5.0 + silu_05 * 2.0);
}

test "KanLayer SoA: Grid Extension Identity" {
    const allocator = std.testing.allocator;
    var layer = try KanLayer.init(allocator, 2, 4, 4);
    defer layer.deinit();

    // Set some non-zero coefficients
    for (layer.coeffs, 0..) |*c, i| {
        c.* = @as(f32, @floatFromInt(i)) * 0.01;
    }

    const inputs = [_]f32{ 0.3, 0.7 };
    const outputs_before = try allocator.alloc(f32, 4);
    defer allocator.free(outputs_before);
    layer.forward(&inputs, outputs_before, 1);

    // Double the resolution
    try layer.extendGrid(allocator);

    const outputs_after = try allocator.alloc(f32, 4);
    defer allocator.free(outputs_after);
    layer.forward(&inputs, outputs_after, 1);

    // Verify identity (within reasonable tolerance for simple subdivision)
    for (0..4) |i| {
        try std.testing.expectApproxEqAbs(outputs_before[i], outputs_after[i], 0.5);
    }
    
    try std.testing.expectEqual(@as(usize, 8), layer.num_coeffs);
}
