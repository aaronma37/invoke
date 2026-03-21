const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

/// B-Spline Configuration
pub const SplineConfig = struct {
    pub const Order = 3; // Cubic B-Splines (Degree 3)
    pub const Alignment = 64;
};

/// Analytical Piecewise Cubic B-Spline Basis Function.
/// This replaces the recursive Cox-de Boor for massive performance gains.
/// Assumes uniform knot spacing.
pub fn basis(i: usize, p: usize, x: f32, knots: []const f32) f32 {
    _ = p; // Always cubic
    const h = knots[1] - knots[0];
    const t = (x - knots[i]) / h;

    if (t < 0.0 or t >= 4.0) return 0.0;

    if (t < 1.0) {
        return 0.16666667 * t * t * t;
    } else if (t < 2.0) {
        const t1 = t - 1.0;
        return 0.16666667 * (-3.0 * t1 * t1 * t1 + 3.0 * t1 * t1 + 3.0 * t1 + 1.0);
    } else if (t < 3.0) {
        const t2 = t - 2.0;
        return 0.16666667 * (3.0 * t2 * t2 * t2 - 6.0 * t2 * t2 + 4.0);
    } else {
        const t3 = t - 3.0;
        return 0.16666667 * (1.0 - t3) * (1.0 - t3) * (1.0 - t3);
    }
}

/// Analytical derivative of the Cubic B-Spline Basis.
pub fn derivative(i: usize, p: usize, x: f32, knots: []const f32) f32 {
    _ = p;
    const h = knots[1] - knots[0];
    const t = (x - knots[i]) / h;
    const inv_h = 1.0 / h;

    if (t < 0.0 or t >= 4.0) return 0.0;

    if (t < 1.0) {
        return inv_h * 0.5 * t * t;
    } else if (t < 2.0) {
        const t1 = t - 1.0;
        return inv_h * 0.5 * (-3.0 * t1 * t1 + 2.0 * t1 + 1.0);
    } else if (t < 3.0) {
        const t2 = t - 2.0;
        return inv_h * 0.5 * (3.0 * t2 * t2 - 4.0 * t2);
    } else {
        const t3 = t - 3.0;
        return inv_h * -0.5 * (1.0 - t3) * (1.0 - t3);
    }
}

/// Structure of Arrays (SoA) Evaluation.
pub fn evaluateEdges(
    x_raw: f32,
    knots: []const f32,
    coeffs: []const f32,
    num_coeffs: usize,
    num_edges: usize,
    results: []f32,
) void {
    @memset(results[0..num_edges], 0.0);
    
    const h = knots[1] - knots[0];
    // Clamp x to ensure we always have 4 basis functions (k-3 to k)
    // Safe range is [knots[3], knots[num_coeffs]]
    const safe_min = knots[3];
    const safe_max = knots[num_coeffs];
    const x = std.math.clamp(x_raw, safe_min, safe_max - 1e-5);

    const i_float = (x - knots[0]) / h;
    const i = @as(isize, @intFromFloat(@floor(i_float)));
    
    var k: isize = i - 3;
    while (k <= i) : (k += 1) {
        if (k < 0 or k >= @as(isize, @intCast(num_coeffs))) continue;
        if (@as(usize, @intCast(k)) >= knots.len) continue;

        const b_val = basis(@as(usize, @intCast(k)), 3, x, knots);
        if (b_val == 0.0) continue;

        for (0..num_edges) |e| {
            results[e] += b_val * coeffs[@as(usize, @intCast(k)) * num_edges + e];
        }
    }
}

/// Vectorized SoA Evaluation (AVX-512)
pub fn evaluateEdgesSimd(
    x_raw: f32,
    knots: []const f32,
    coeffs: []const f32,
    num_coeffs: usize,
    results: *[16]f32,
) void {
    const Vector = @Vector(16, f32);
    var sums = @as(Vector, @splat(0.0));

    const h = knots[1] - knots[0];
    const safe_min = knots[3];
    const safe_max = knots[num_coeffs];
    const x = std.math.clamp(x_raw, safe_min, safe_max - 1e-5);

    const i_float = (x - knots[0]) / h;
    const i = @as(isize, @intFromFloat(@floor(i_float)));

    var k: isize = i - 3;
    while (k <= i) : (k += 1) {
        if (k < 0 or k >= @as(isize, @intCast(num_coeffs))) continue;
        if (@as(usize, @intCast(k)) >= knots.len) continue;

        const b_val = basis(@as(usize, @intCast(k)), 3, x, knots);
        if (b_val == 0.0) continue;

        const b_vec = @as(Vector, @splat(b_val));
        const c_vec: Vector = coeffs[@as(usize, @intCast(k)) * 16 ..][0..16].*;
        sums += b_vec * c_vec;
    }
    results.* = sums;
}

test "B-Spline Basis: Analytical Parity" {
    const knots = [_]f32{ 0.0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4 };
    // N_{0,3}(x) is non-zero from 0 to 0.8
    try std.testing.expect(basis(0, 3, 0.1, &knots) > 0);
    try std.testing.expect(basis(0, 3, 0.9, &knots) == 0);
}
