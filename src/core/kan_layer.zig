const std = @import("std");
const mem = std.mem;
const kan_spline = @import("kan_spline.zig");

pub const KanLayer = struct {
    in_dim: usize,
    out_dim: usize,
    num_coeffs: usize,
    coeffs: []align(kan_spline.SplineConfig.Alignment) f32,
    knots: []f32,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, in_dim: usize, out_dim: usize, num_coeffs: usize) !KanLayer {
        const p = kan_spline.SplineConfig.Order;
        const num_knots = num_coeffs + p + 1;
        const coeffs = try allocator.alignedAlloc(f32, kan_spline.SplineConfig.Alignment, in_dim * num_coeffs * out_dim);
        errdefer allocator.free(coeffs);
        
        var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
        const rand = prng.random();
        
        // Xavier/Kaiming-like initialization for KAN coefficients
        const std_dev = @sqrt(2.0 / @as(f32, @floatFromInt(in_dim + out_dim)));
        for (coeffs) |*c| {
            c.* = (rand.float(f32) * 2.0 - 1.0) * std_dev;
        }

        const knots = try allocator.alloc(f32, num_knots);
        errdefer allocator.free(knots);
        const h = 2.0 / @as(f32, @floatFromInt(num_coeffs - 3));
        for (knots, 0..) |*k, i| k.* = (@as(f32, @floatFromInt(i)) - 3.0) * h - 1.0;

        return KanLayer{ .in_dim = in_dim, .out_dim = out_dim, .num_coeffs = num_coeffs, .coeffs = coeffs, .knots = knots, .allocator = allocator };
    }

    pub fn deinit(self: *KanLayer) void {
        self.allocator.free(self.coeffs);
        self.allocator.free(self.knots);
    }

    pub fn forward(self: KanLayer, inputs: []const f32, outputs: []f32, batch_size: usize) void {
        @memset(outputs[0 .. batch_size * self.out_dim], 0.0);

        const h = self.knots[1] - self.knots[0];
        const inv_h = 1.0 / h;
        const safe_min = self.knots[3];
        const safe_max = self.knots[self.num_coeffs];

        for (0..batch_size) |b| {
            const batch_out = outputs[b * self.out_dim .. (b + 1) * self.out_dim];
            for (0..self.in_dim) |i| {
                const x_raw = inputs[b * self.in_dim + i];
                const sigmoid = 1.0 / (1.0 + std.math.exp(-x_raw));
                const silu = x_raw * sigmoid;

                const x = std.math.clamp(x_raw, safe_min, safe_max - 1e-5);
                const span_float = (x - self.knots[0]) * inv_h;
                const span_idx = @as(isize, @intFromFloat(@floor(span_float)));

                // Evaluate the 4 active basis functions ONCE per input
                var b_vals: [4]f32 = .{0, 0, 0, 0};
                var k_indices: [4]usize = .{0, 0, 0, 0};
                var num_active: usize = 0;
                
                var k_iter: isize = span_idx - 3;
                while (k_iter <= span_idx) : (k_iter += 1) {
                    if (k_iter < 0 or k_iter >= @as(isize, @intCast(self.num_coeffs))) continue;
                    const k_u = @as(usize, @intCast(k_iter));
                    k_indices[num_active] = k_u;
                    b_vals[num_active] = kan_spline.basis(k_u, 3, x, self.knots);
                    num_active += 1;
                }

                const layer_coeffs_base = i * self.num_coeffs * self.out_dim;
                
                // 1. Apply SiLU base to all outputs
                for (0..self.out_dim) |j| {
                    batch_out[j] += silu;
                }

                // 2. Accumulate spline values
                for (0..num_active) |a| {
                    const b_val = b_vals[a];
                    const coeff_idx_start = layer_coeffs_base + k_indices[a] * self.out_dim;
                    const coeff_row = self.coeffs[coeff_idx_start .. coeff_idx_start + self.out_dim];
                    
                    var j: usize = 0;
                    // Vectorized chunk processing
                    const vec_len = 16;
                    const V = @Vector(vec_len, f32);
                    const b_vec = @as(V, @splat(b_val));
                    
                    while (j + vec_len <= self.out_dim) : (j += vec_len) {
                        const c_vec: V = coeff_row[j .. j + vec_len][0..vec_len].*;
                        var out_vec: V = batch_out[j .. j + vec_len][0..vec_len].*;
                        out_vec += b_vec * c_vec;
                        const out_slice: *[vec_len]f32 = batch_out[j .. j + vec_len][0..vec_len];
                        out_slice.* = out_vec;
                    }
                    
                    // Remainder
                    while (j < self.out_dim) : (j += 1) {
                        batch_out[j] += b_val * coeff_row[j];
                    }
                }
            }
        }
    }

    pub fn forwardWithDeriv(self: KanLayer, inputs: []const f32, outputs: []f32, jacobians: []f32, batch_size: usize) void {
        @memset(outputs[0 .. batch_size * self.out_dim], 0.0);
        @memset(jacobians[0 .. batch_size * self.out_dim * self.in_dim], 0.0);

        const h = self.knots[1] - self.knots[0];
        const inv_h = 1.0 / h;
        const safe_min = self.knots[3];
        const safe_max = self.knots[self.num_coeffs];

        for (0..batch_size) |b| {
            const batch_out = outputs[b * self.out_dim .. (b + 1) * self.out_dim];
            const batch_jac = jacobians[b * self.out_dim * self.in_dim .. (b + 1) * self.out_dim * self.in_dim];
            
            for (0..self.in_dim) |i| {
                const x_raw = inputs[b * self.in_dim + i];
                const exp_nx = std.math.exp(-x_raw);
                const sigmoid = 1.0 / (1.0 + exp_nx);
                const silu = x_raw * sigmoid;
                const silu_prime = sigmoid * (1.0 + x_raw * (1.0 - sigmoid));

                const x = std.math.clamp(x_raw, safe_min, safe_max - 1e-5);
                const span_float = (x - self.knots[0]) * inv_h;
                const span_idx = @as(isize, @intFromFloat(@floor(span_float)));

                // Evaluate the 4 active basis functions and derivatives ONCE per input
                var b_vals: [4]f32 = .{0, 0, 0, 0};
                var b_primes: [4]f32 = .{0, 0, 0, 0};
                var k_indices: [4]usize = .{0, 0, 0, 0};
                var num_active: usize = 0;
                
                var k_iter: isize = span_idx - 3;
                while (k_iter <= span_idx) : (k_iter += 1) {
                    if (k_iter < 0 or k_iter >= @as(isize, @intCast(self.num_coeffs))) continue;
                    const k_u = @as(usize, @intCast(k_iter));
                    k_indices[num_active] = k_u;
                    b_vals[num_active] = kan_spline.basis(k_u, 3, x, self.knots);
                    b_primes[num_active] = kan_spline.derivative(k_u, 3, x, self.knots);
                    num_active += 1;
                }

                const layer_coeffs_base = i * self.num_coeffs * self.out_dim;
                
                // 1. Apply SiLU base to all outputs
                for (0..self.out_dim) |j| {
                    batch_out[j] += silu;
                    batch_jac[j * self.in_dim + i] += silu_prime;
                }

                // 2. Accumulate spline values and derivatives
                for (0..num_active) |a| {
                    const b_val = b_vals[a];
                    const b_prime = b_primes[a];
                    const coeff_idx_start = layer_coeffs_base + k_indices[a] * self.out_dim;
                    const coeff_row = self.coeffs[coeff_idx_start .. coeff_idx_start + self.out_dim];
                    
                    var j: usize = 0;
                    const vec_len = 16;
                    const V = @Vector(vec_len, f32);
                    const b_vec = @as(V, @splat(b_val));
                    
                    while (j + vec_len <= self.out_dim) : (j += vec_len) {
                        const c_vec: V = coeff_row[j .. j + vec_len][0..vec_len].*;
                        
                        var out_vec: V = batch_out[j .. j + vec_len][0..vec_len].*;
                        out_vec += b_vec * c_vec;
                        batch_out[j .. j + vec_len][0..vec_len].* = out_vec;
                        
                        // Jacobian is strided by in_dim, so we can't easily vector-load it here
                        // unless out_dim is contiguous. Wait, jacobian is [out_dim][in_dim] technically?
                        // "batch_jac[j * self.in_dim + i] += b_prime * coeff;"
                        // It's strided by in_dim. We'll do scalar for Jacobian for now to avoid gather/scatter.
                        for (j .. j + vec_len) |v_j| {
                            batch_jac[v_j * self.in_dim + i] += b_prime * coeff_row[v_j];
                        }
                    }
                    
                    while (j < self.out_dim) : (j += 1) {
                        const coeff = coeff_row[j];
                        batch_out[j] += b_val * coeff;
                        batch_jac[j * self.in_dim + i] += b_prime * coeff;
                    }
                }
            }
        }
    }

    pub fn backward(self: KanLayer, inputs: []const f32, out_grad: []const f32, in_grad: []f32, coeff_grads: []f32, batch_size: usize) void {
        @memset(in_grad[0 .. batch_size * self.in_dim], 0.0);

        const h = self.knots[1] - self.knots[0];
        const inv_h = 1.0 / h;
        const safe_min = self.knots[3];
        const safe_max = self.knots[self.num_coeffs];

        for (0..batch_size) |b| {
            const b_out_grad = out_grad[b * self.out_dim .. (b + 1) * self.out_dim];
            const b_in_grad = in_grad[b * self.in_dim .. (b + 1) * self.in_dim];

            for (0..self.in_dim) |i| {
                const x_raw = inputs[b * self.in_dim + i];
                const sigmoid = 1.0 / (1.0 + std.math.exp(-x_raw));
                const silu_prime = sigmoid * (1.0 + x_raw * (1.0 - sigmoid));

                const x = std.math.clamp(x_raw, safe_min, safe_max - 1e-5);
                const span_float = (x - self.knots[0]) * inv_h;
                const span_idx = @as(isize, @intFromFloat(@floor(span_float)));

                // Evaluate the 4 active basis functions and derivatives ONCE per input
                var b_vals: [4]f32 = .{0, 0, 0, 0};
                var b_primes: [4]f32 = .{0, 0, 0, 0};
                var k_indices: [4]usize = .{0, 0, 0, 0};
                var num_active: usize = 0;
                
                var k_iter: isize = span_idx - 3;
                while (k_iter <= span_idx) : (k_iter += 1) {
                    if (k_iter < 0 or k_iter >= @as(isize, @intCast(self.num_coeffs))) continue;
                    const k_u = @as(usize, @intCast(k_iter));
                    k_indices[num_active] = k_u;
                    b_vals[num_active] = kan_spline.basis(k_u, 3, x, self.knots);
                    b_primes[num_active] = kan_spline.derivative(k_u, 3, x, self.knots);
                    num_active += 1;
                }

                var total_in_grad: f32 = 0.0;
                const layer_coeffs_base = i * self.num_coeffs * self.out_dim;
                
                // 1. SiLU backprop contribution
                for (0..self.out_dim) |j| {
                    total_in_grad += b_out_grad[j] * silu_prime;
                }

                // 2. Spline backprop contribution
                for (0..num_active) |a| {
                    const b_val = b_vals[a];
                    const b_prime = b_primes[a];
                    const coeff_idx_start = layer_coeffs_base + k_indices[a] * self.out_dim;
                    const coeff_row = self.coeffs[coeff_idx_start .. coeff_idx_start + self.out_dim];
                    const coeff_grad_row = coeff_grads[coeff_idx_start .. coeff_idx_start + self.out_dim];
                    
                    var j: usize = 0;
                    const vec_len = 16;
                    const V = @Vector(vec_len, f32);
                    const b_vec = @as(V, @splat(b_val));
                    const bp_vec = @as(V, @splat(b_prime));
                    
                    var total_in_grad_vec = @as(V, @splat(0.0));
                    
                    while (j + vec_len <= self.out_dim) : (j += vec_len) {
                        const og_vec: V = b_out_grad[j .. j + vec_len][0..vec_len].*;
                        var c_grad_vec: V = coeff_grad_row[j .. j + vec_len][0..vec_len].*;
                        
                        c_grad_vec += og_vec * b_vec;
                        coeff_grad_row[j .. j + vec_len][0..vec_len].* = c_grad_vec;
                        
                        const c_vec: V = coeff_row[j .. j + vec_len][0..vec_len].*;
                        total_in_grad_vec += og_vec * bp_vec * c_vec;
                    }
                    
                    total_in_grad += @reduce(.Add, total_in_grad_vec);
                    
                    while (j < self.out_dim) : (j += 1) {
                        const og = b_out_grad[j];
                        coeff_grad_row[j] += og * b_val;
                        total_in_grad += og * b_prime * coeff_row[j];
                    }
                }
                b_in_grad[i] += total_in_grad;
            }
        }
    }
};

test "KanLayer: No Accumulation Sanity" {
    const allocator = std.testing.allocator;
    var layer = try KanLayer.init(allocator, 3, 4, 8);
    defer layer.deinit();

    const input = [_]f32{ 0.5, -0.2, 0.1 };
    const output1 = try allocator.alloc(f32, 4);
    const output2 = try allocator.alloc(f32, 4);
    defer allocator.free(output1);
    defer allocator.free(output2);

    // Run first time
    layer.forward(&input, output1, 1);
    
    // Run 10 more times
    for (0..10) |_| {
        layer.forward(&input, output2, 1);
    }

    // Verify output2 is identical to output1 (no accumulation)
    for (0..4) |i| {
        try std.testing.expectEqual(output1[i], output2[i]);
    }
}
