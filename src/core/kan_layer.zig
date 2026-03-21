const std = @import("std");
const mem = std.mem;
const kan_spline = @import("kan_spline.zig");

pub const KanLayer = struct {
    in_dim: usize,
    out_dim: usize,
    out_dim_padded: usize, // Padded to multiple of 16 for AVX-512
    num_coeffs: usize,
    coeffs: []align(kan_spline.SplineConfig.Alignment) f32,
    knots: []f32,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, in_dim: usize, out_dim: usize, num_coeffs: usize) !KanLayer {
        const p = kan_spline.SplineConfig.Order;
        const num_knots = num_coeffs + p + 1;
        
        const out_dim_padded = (out_dim + 15) & ~@as(usize, 15);
        const coeffs = try allocator.alignedAlloc(f32, kan_spline.SplineConfig.Alignment, in_dim * num_coeffs * out_dim_padded);
        errdefer allocator.free(coeffs);
        @memset(coeffs, 0.0);
        
        var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
        const rand = prng.random();
        
        const std_dev = @sqrt(2.0 / @as(f32, @floatFromInt(in_dim + out_dim)));
        for (0..in_dim) |i| {
            for (0..num_coeffs) |k| {
                const base = (i * num_coeffs + k) * out_dim_padded;
                for (0..out_dim) |j| {
                    coeffs[base + j] = (rand.float(f32) * 2.0 - 1.0) * std_dev;
                }
            }
        }

        const knots = try allocator.alloc(f32, num_knots);
        errdefer allocator.free(knots);
        const h = 2.0 / @as(f32, @floatFromInt(num_coeffs - 3));
        for (knots, 0..) |*k, i| k.* = (@as(f32, @floatFromInt(i)) - 3.0) * h - 1.0;

        return KanLayer{ 
            .in_dim = in_dim, 
            .out_dim = out_dim, 
            .out_dim_padded = out_dim_padded,
            .num_coeffs = num_coeffs, 
            .coeffs = coeffs, 
            .knots = knots, 
            .allocator = allocator 
        };
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

        const vec_len = 16;
        const V = @Vector(vec_len, f32);

        // AoS Point-Outer, Neuron-Inner -> Peak Performance
        for (0..batch_size) |b| {
            const batch_out = outputs[b * self.out_dim .. (b + 1) * self.out_dim];
            
            for (0..self.in_dim) |i| {
                const x_raw = inputs[b * self.in_dim + i];
                const silu = x_raw / (1.0 + kan_spline.fast_exp(-x_raw));

                const x = std.math.clamp(x_raw, safe_min, safe_max - 1e-5);
                const span_float = (x - self.knots[0]) * inv_h;
                const span_idx = @as(isize, @intFromFloat(@floor(span_float)));
                const u = span_float - @as(f32, @floatFromInt(span_idx));

                const b_vals = kan_spline.basisAll(u);
                const k_base = @as(usize, @intCast(@max(0, span_idx - 3)));
                const layer_coeffs_base = i * self.num_coeffs * self.out_dim_padded;

                var j: usize = 0;
                while (j + vec_len <= self.out_dim) : (j += vec_len) {
                    var out_v: V = batch_out[j .. j + vec_len][0..vec_len].*;
                    out_v += @as(V, @splat(silu));

                    for (0..4) |a| {
                        const k_u = k_base + a;
                        if (k_u < self.num_coeffs) {
                            const c_base = layer_coeffs_base + k_u * self.out_dim_padded + j;
                            const weight_v: V = self.coeffs[c_base .. c_base + vec_len][0..vec_len].*;
                            out_v += @as(V, @splat(b_vals[a])) * weight_v;
                        }
                    }
                    batch_out[j .. j + vec_len][0..vec_len].* = out_v;
                }

                while (j < self.out_dim) : (j += 1) {
                    batch_out[j] += silu;
                    for (0..4) |a| {
                        const k_u = k_base + a;
                        if (k_u < self.num_coeffs) {
                            batch_out[j] += b_vals[a] * self.coeffs[layer_coeffs_base + k_u * self.out_dim_padded + j];
                        }
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

        const vec_len = 16;
        const V = @Vector(vec_len, f32);

        for (0..batch_size) |b| {
            const batch_out = outputs[b * self.out_dim .. (b + 1) * self.out_dim];
            const batch_jac = jacobians[b * self.out_dim * self.in_dim .. (b + 1) * self.out_dim * self.in_dim];
            
            for (0..self.in_dim) |i| {
                const x_raw = inputs[b * self.in_dim + i];
                const sigmoid = 1.0 / (1.0 + kan_spline.fast_exp(-x_raw));
                const silu = x_raw * sigmoid;
                const silu_prime = sigmoid * (1.0 + x_raw * (1.0 - sigmoid));

                const x = std.math.clamp(x_raw, safe_min, safe_max - 1e-5);
                const span_float = (x - self.knots[0]) * inv_h;
                const span_idx = @as(isize, @intFromFloat(@floor(span_float)));
                const u = span_float - @as(f32, @floatFromInt(span_idx));

                const b_vals = kan_spline.basisAll(u);
                const bp_vals = kan_spline.derivativeAll(u, inv_h);
                const k_base = @as(usize, @intCast(@max(0, span_idx - 3)));
                const layer_coeffs_base = i * self.num_coeffs * self.out_dim_padded;

                var j: usize = 0;
                while (j + vec_len <= self.out_dim) : (j += vec_len) {
                    var out_v: V = batch_out[j .. j + vec_len][0..vec_len].*;
                    out_v += @as(V, @splat(silu));
                    
                    for (0..vec_len) |v_idx| {
                        batch_jac[(j + v_idx) * self.in_dim + i] += silu_prime;
                    }

                    for (0..4) |a| {
                        const k_u = k_base + a;
                        if (k_u < self.num_coeffs) {
                            const c_base = layer_coeffs_base + k_u * self.out_dim_padded + j;
                            const weight_v: V = self.coeffs[c_base .. c_base + vec_len][0..vec_len].*;
                            out_v += @as(V, @splat(b_vals[a])) * weight_v;
                            
                            for (0..vec_len) |v_idx| {
                                batch_jac[(j + v_idx) * self.in_dim + i] += bp_vals[a] * weight_v[v_idx];
                            }
                        }
                    }
                    batch_out[j .. j + vec_len][0..vec_len].* = out_v;
                }

                while (j < self.out_dim) : (j += 1) {
                    batch_out[j] += silu;
                    batch_jac[j * self.in_dim + i] += silu_prime;
                    for (0..4) |a| {
                        const k_u = k_base + a;
                        if (k_u < self.num_coeffs) {
                            const coeff = self.coeffs[layer_coeffs_base + k_u * self.out_dim_padded + j];
                            batch_out[j] += b_vals[a] * coeff;
                            batch_jac[j * self.in_dim + i] += bp_vals[a] * coeff;
                        }
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

        const vec_len = 16;
        const V = @Vector(vec_len, f32);

        for (0..batch_size) |b| {
            const b_out_grad = out_grad[b * self.out_dim .. (b + 1) * self.out_dim];
            const b_in_grad = in_grad[b * self.in_dim .. (b + 1) * self.in_dim];

            for (0..self.in_dim) |i| {
                const x_raw = inputs[b * self.in_dim + i];
                const sigmoid = 1.0 / (1.0 + kan_spline.fast_exp(-x_raw));
                const silu_prime = sigmoid * (1.0 + x_raw * (1.0 - sigmoid));

                const x = std.math.clamp(x_raw, safe_min, safe_max - 1e-5);
                const span_float = (x - self.knots[0]) * inv_h;
                const span_idx = @as(isize, @intFromFloat(@floor(span_float)));
                const u = span_float - @as(f32, @floatFromInt(span_idx));

                const b_vals = kan_spline.basisAll(u);
                const bp_vals = kan_spline.derivativeAll(u, inv_h);
                const k_base = @as(usize, @intCast(@max(0, span_idx - 3)));
                const layer_coeffs_base = i * self.num_coeffs * self.out_dim_padded;

                var total_in_grad: f32 = 0.0;
                var j: usize = 0;
                while (j + vec_len <= self.out_dim) : (j += vec_len) {
                    const og_v: V = b_out_grad[j .. j + vec_len][0..vec_len].*;
                    var total_in_grad_v = og_v * @as(V, @splat(silu_prime));

                    for (0..4) |a| {
                        const k_u = k_base + a;
                        if (k_u < self.num_coeffs) {
                            const c_base = layer_coeffs_base + k_u * self.out_dim_padded + j;
                            const weight_v: V = self.coeffs[c_base .. c_base + vec_len][0..vec_len].*;
                            var cg_v: V = coeff_grads[c_base .. c_base + vec_len][0..vec_len].*;
                            
                            cg_v += og_v * @as(V, @splat(b_vals[a]));
                            total_in_grad_v += og_v * @as(V, @splat(bp_vals[a])) * weight_v;
                            
                            coeff_grads[c_base .. c_base + vec_len][0..vec_len].* = cg_v;
                        }
                    }
                    total_in_grad += @reduce(.Add, total_in_grad_v);
                }

                while (j < self.out_dim) : (j += 1) {
                    const og = b_out_grad[j];
                    total_in_grad += og * silu_prime;
                    for (0..4) |a| {
                        const k_u = k_base + a;
                        if (k_u < self.num_coeffs) {
                            const c_idx = layer_coeffs_base + k_u * self.out_dim_padded + j;
                            coeff_grads[c_idx] += og * b_vals[a];
                            total_in_grad += og * bp_vals[a] * self.coeffs[c_idx];
                        }
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

    layer.forward(&input, output1, 1);
    for (0..10) |_| { layer.forward(&input, output2, 1); }

    for (0..4) |i| { try std.testing.expectEqual(output1[i], output2[i]); }
}
