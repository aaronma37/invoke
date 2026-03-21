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
        for (coeffs) |*c| c.* = (rand.float(f32) * 2.0 - 1.0) * 0.001;

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

        for (0..batch_size) |b| {
            const batch_out = outputs[b * self.out_dim .. (b + 1) * self.out_dim];
            for (0..self.in_dim) |i| {
                const x = inputs[b * self.in_dim + i];
                const sigmoid = 1.0 / (1.0 + std.math.exp(-x));
                const silu = x * sigmoid;
                for (batch_out) |*out| out.* += silu;

                const layer_coeffs_base = i * self.num_coeffs * self.out_dim;
                for (0..self.out_dim) |j| {
                    var spline_val: f32 = 0.0;
                    for (0..self.num_coeffs) |k| {
                        const b_val = kan_spline.basis(k, kan_spline.SplineConfig.Order, x, self.knots);
                        spline_val += b_val * self.coeffs[layer_coeffs_base + k * self.out_dim + j];
                    }
                    batch_out[j] += spline_val;
                }
            }
        }
    }

    pub fn forwardWithDeriv(self: KanLayer, inputs: []const f32, outputs: []f32, jacobians: []f32, batch_size: usize) void {
        @memset(outputs[0 .. batch_size * self.out_dim], 0.0);
        @memset(jacobians[0 .. batch_size * self.out_dim * self.in_dim], 0.0);

        for (0..batch_size) |b| {
            const batch_out = outputs[b * self.out_dim .. (b + 1) * self.out_dim];
            const batch_jac = jacobians[b * self.out_dim * self.in_dim .. (b + 1) * self.out_dim * self.in_dim];
            
            for (0..self.in_dim) |i| {
                const x = inputs[b * self.in_dim + i];
                const exp_nx = std.math.exp(-x);
                const sigmoid = 1.0 / (1.0 + exp_nx);
                const silu = x * sigmoid;
                const silu_prime = sigmoid * (1.0 + x * (1.0 - sigmoid));

                for (0..self.out_dim) |j| {
                    batch_out[j] += silu;
                    batch_jac[j * self.in_dim + i] += silu_prime;

                    const layer_coeffs_base = i * self.num_coeffs * self.out_dim;
                    var spline_val: f32 = 0.0;
                    var spline_prime: f32 = 0.0;
                    for (0..self.num_coeffs) |k| {
                        const b_val = kan_spline.basis(k, kan_spline.SplineConfig.Order, x, self.knots);
                        const b_prime = kan_spline.derivative(k, kan_spline.SplineConfig.Order, x, self.knots);
                        const coeff = self.coeffs[layer_coeffs_base + k * self.out_dim + j];
                        spline_val += b_val * coeff;
                        spline_prime += b_prime * coeff;
                    }
                    batch_out[j] += spline_val;
                    batch_jac[j * self.in_dim + i] += spline_prime;
                }
            }
        }
    }

    pub fn backward(self: KanLayer, inputs: []const f32, out_grad: []const f32, in_grad: []f32, coeff_grads: []f32, batch_size: usize) void {
        @memset(in_grad[0 .. batch_size * self.in_dim], 0.0);

        for (0..batch_size) |b| {
            const b_out_grad = out_grad[b * self.out_dim .. (b + 1) * self.out_dim];
            const b_in_grad = in_grad[b * self.in_dim .. (b + 1) * self.in_dim];

            for (0..self.in_dim) |i| {
                const x = inputs[b * self.in_dim + i];
                const sigmoid = 1.0 / (1.0 + std.math.exp(-x));
                const silu_prime = sigmoid * (1.0 + x * (1.0 - sigmoid));

                var total_in_grad: f32 = 0.0;
                for (0..self.out_dim) |j| {
                    const og = b_out_grad[j];
                    total_in_grad += og * silu_prime;

                    const layer_coeffs_base = i * self.num_coeffs * self.out_dim;
                    for (0..self.num_coeffs) |k| {
                        const b_val = kan_spline.basis(k, kan_spline.SplineConfig.Order, x, self.knots);
                        const b_prime = kan_spline.derivative(k, kan_spline.SplineConfig.Order, x, self.knots);
                        const coeff = self.coeffs[layer_coeffs_base + k * self.out_dim + j];
                        
                        coeff_grads[layer_coeffs_base + k * self.out_dim + j] += og * b_val;
                        total_in_grad += og * b_prime * coeff;
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
