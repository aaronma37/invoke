const std = @import("std");
const kan_spline = @import("kan_spline.zig");

/// A 2D Tensor Product B-Spline Surface.
/// HARDENED: Support for Periodic Wrapping and Backpropagation.
pub const TensorSurface = struct {
    num_u: usize,
    num_v: usize,
    out_dim: usize,
    coeffs: []f32,
    knots_u: []f32,
    knots_v: []f32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, num_u: usize, num_v: usize, out_dim: usize) !TensorSurface {
        const coeffs = try allocator.alloc(f32, num_u * num_v * out_dim);
        @memset(coeffs, 0.0);

        const knots_u = try allocator.alloc(f32, num_u + 4);
        const knots_v = try allocator.alloc(f32, num_v + 4);

        for (0..4) |i| { knots_u[i] = 0.0; knots_v[i] = 0.0; }
        for (4..num_u) |i| {
            const val = @as(f32, @floatFromInt(i - 3)) / @as(f32, @floatFromInt(num_u - 3));
            knots_u[i] = val;
        }
        for (4..num_v) |i| {
            const val = @as(f32, @floatFromInt(i - 3)) / @as(f32, @floatFromInt(num_v - 3));
            knots_v[i] = val;
        }
        for (num_u..num_u + 4) |i| { knots_u[i] = 1.0; knots_v[i] = 1.0; }

        return TensorSurface{
            .num_u = num_u,
            .num_v = num_v,
            .out_dim = out_dim,
            .coeffs = coeffs,
            .knots_u = knots_u,
            .knots_v = knots_v,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TensorSurface) void {
        self.allocator.free(self.coeffs);
        self.allocator.free(self.knots_u);
        self.allocator.free(self.knots_v);
    }

    pub fn evaluate(self: TensorSurface, u_in: f32, v_in: f32, is_periodic_u: bool, output: []f32) void {
        @memset(output[0..self.out_dim], 0.0);
        var u = std.math.clamp(u_in, 0.0, 1.0);
        if (is_periodic_u and u >= 1.0) u = 0.0;
        const v = std.math.clamp(v_in, 0.0, 1.0);

        const uc = if (u >= 1.0) 1.0 - 1e-7 else u;
        const vc = if (v >= 1.0) 1.0 - 1e-7 else v;

        const iu = findSpan(self.num_u, 3, uc, self.knots_u);
        const iv = findSpan(self.num_v, 3, vc, self.knots_v);

        const basis_u = basisFunctions(iu, uc, 3, self.knots_u);
        const basis_v = basisFunctions(iv, vc, 3, self.knots_v);

        for (0..4) |j| {
            const kv = iv - 3 + j;
            const wv = basis_v[j];
            for (0..4) |i| {
                const ku = iu - 3 + i;
                const wu = basis_u[i];
                const coeff_idx = (kv * self.num_u + ku) * self.out_dim;
                const weight = wu * wv;
                for (0..self.out_dim) |d| {
                    output[d] += weight * self.coeffs[coeff_idx + d];
                }
            }
        }
    }

    /// Backpropagation for Tensor Product Splines.
    /// Accumulates gradients into 'coeff_grads'.
    pub fn backward(
        self: TensorSurface,
        u_in: f32,
        v_in: f32,
        is_periodic_u: bool,
        output_grads: []const f32,
        coeff_grads: []f32,
    ) void {
        var u = std.math.clamp(u_in, 0.0, 1.0);
        if (is_periodic_u and u >= 1.0) u = 0.0;
        const v = std.math.clamp(v_in, 0.0, 1.0);

        const uc = if (u >= 1.0) 1.0 - 1e-7 else u;
        const vc = if (v >= 1.0) 1.0 - 1e-7 else v;

        const iu = findSpan(self.num_u, 3, uc, self.knots_u);
        const iv = findSpan(self.num_v, 3, vc, self.knots_v);

        const basis_u = basisFunctions(iu, uc, 3, self.knots_u);
        const basis_v = basisFunctions(iv, vc, 3, self.knots_v);

        for (0..4) |j| {
            const kv = iv - 3 + j;
            const wv = basis_v[j];
            for (0..4) |i| {
                const ku = iu - 3 + i;
                const wu = basis_u[i];
                const coeff_idx = (kv * self.num_u + ku) * self.out_dim;
                const weight = wu * wv;
                
                // dLoss/dCoeff = dLoss/dOutput * dOutput/dCoeff
                // dOutput/dCoeff = Basis_u * Basis_v
                for (0..self.out_dim) |d| {
                    coeff_grads[coeff_idx + d] += output_grads[d] * weight;
                }
            }
        }
    }

    fn findSpan(n: usize, p: usize, u: f32, knots: []f32) usize {
        if (u >= knots[n]) return n - 1;
        var low: usize = p;
        var high: usize = n;
        var mid = (low + high) / 2;
        while (u < knots[mid] or u >= knots[mid + 1]) {
            if (u < knots[mid]) high = mid else low = mid;
            mid = (low + high) / 2;
        }
        return mid;
    }

    fn basisFunctions(i: usize, u: f32, p: usize, knots: []f32) [4]f32 {
        var n: [4]f32 = undefined;
        var left: [4]f32 = undefined;
        var right: [4]f32 = undefined;
        n[0] = 1.0;
        for (1..p + 1) |j| {
            left[j] = u - knots[i + 1 - j];
            right[j] = knots[i + j] - u;
            var saved: f32 = 0.0;
            for (0..j) |r| {
                const temp = n[r] / (right[r + 1] + left[j - r]);
                n[r] = saved + right[r + 1] * temp;
                saved = left[j - r] * temp;
            }
            n[j] = saved;
        }
        return n;
    }

    pub fn pinRow(self: *TensorSurface, row_idx: usize, points: []const [3]f32) void {
        const r = if (row_idx == 0) 0 else self.num_v - 1;
        for (0..@min(self.num_u, points.len)) |i| {
            const base = (r * self.num_u + i) * self.out_dim;
            self.coeffs[base + 0] = points[i][0];
            self.coeffs[base + 1] = points[i][1];
            self.coeffs[base + 2] = points[i][2];
        }
    }
};

test "TensorSurface: Corner Identity" {
    const allocator = std.testing.allocator;
    var surf = try TensorSurface.init(allocator, 8, 8, 3);
    defer surf.deinit();

    // Set corner coefficient (0,0)
    for (0..3) |v| {
        for (0..3) |u| {
            const base = (v * 8 + u) * 3;
            surf.coeffs[base + 0] = 10.0;
            surf.coeffs[base + 1] = 20.0;
            surf.coeffs[base + 2] = 30.0;
        }
    }

    var result: [3]f32 = undefined;
    surf.evaluate(0.0, 0.0, false, &result);

    try std.testing.expectApproxEqAbs(@as(f32, 10.0), result[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), result[1], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), result[2], 1e-5);
}

test "TensorSurface: Pinning Accuracy" {
    const allocator = std.testing.allocator;
    var surf = try TensorSurface.init(allocator, 8, 8, 3);
    defer surf.deinit();

    const socket = [_][3]f32{ .{1.0, 2.0, 3.0} } ** 8;
    surf.pinRow(0, &socket);

    var result: [3]f32 = undefined;
    surf.evaluate(0.5, 0.0, false, &result);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), result[2], 1e-5);
}

test "TensorSurface: Backward Pass (Gradient Parity)" {
    const allocator = std.testing.allocator;
    var surf = try TensorSurface.init(allocator, 8, 8, 3);
    defer surf.deinit();

    const grads = try allocator.alloc(f32, surf.coeffs.len);
    defer allocator.free(grads);
    @memset(grads, 0.0);

    const target_grad = [_]f32{ 0.0, 0.0, 1.0 };
    surf.backward(0.5, 0.5, false, &target_grad, grads);

    var sum_z_grad: f32 = 0.0;
    var i: usize = 2;
    while (i < grads.len) : (i += 3) {
        sum_z_grad += grads[i];
    }
    
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), sum_z_grad, 1e-5);
}
