const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

/// B-Spline Configuration
/// We align to 64 bytes to ensure data fits perfectly into AVX-512 (ZMM) registers.
pub const SplineConfig = struct {
    pub const Order = 3; // Cubic B-Splines (Degree 3)
    pub const Alignment = 64;
};

/// A Spline Grid represents the "Wire" data for a single edge in the KAN.
/// It contains the knot vector and the trainable coefficients.
pub const SplineGrid = struct {
    knots: []f32,
    coeffs: []f32,

    pub fn init(allocator: mem.Allocator, num_coeffs: usize) !SplineGrid {
        // For a B-Spline of degree p, we need (n + p + 1) knots for n coefficients.
        const num_knots = num_coeffs + SplineConfig.Order + 1;
        
        const knots = try allocator.alloc(f32, num_knots);
        const coeffs = try allocator.alloc(f32, num_coeffs);

        // Initialize knots to a uniform range [0, 1] for now
        for (knots, 0..) |*k, i| {
            k.* = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_knots - 1));
        }

        // Initialize coefficients to small random values or zero
        @memset(coeffs, 0.0);

        return SplineGrid{
            .knots = knots,
            .coeffs = coeffs,
        };
    }

    pub fn deinit(self: *SplineGrid, allocator: mem.Allocator) void {
        allocator.free(self.knots);
        allocator.free(self.coeffs);
    }

    /// Vectorized evaluation of the spline at multiple points.
    /// This is the "Forward Pass" for a single edge.
    pub fn evaluateBatch(self: SplineGrid, x_batch: anytype, results: []f32) void {
        const Vector = @TypeOf(x_batch);
        const len = @typeInfo(Vector).vector.len;
        assert(results.len >= len);

        var sums = @as(Vector, @splat(0.0));

        // For each coefficient/basis function
        for (0..self.coeffs.len) |i| {
            const coeff = self.coeffs[i];
            if (coeff == 0.0) continue; // Sparsity optimization

            // Evaluate basis function for each point in the batch
            var b_vals: [len]f32 = undefined;
            for (0..len) |j| {
                b_vals[j] = basis(i, SplineConfig.Order, x_batch[j], self.knots);
            }
            
            const b_vec: Vector = b_vals;
            sums += b_vec * @as(Vector, @splat(coeff));
        }

        // Store results
        for (0..len) |j| {
            results[j] = sums[j];
        }
    }
};

/// Cox-de Boor recursion for B-spline basis functions.
/// This is the "Forward Pass" math for a single basis function N_{i,p}(x).
pub fn basis(i: usize, p: usize, x: f32, knots: []const f32) f32 {
    if (p == 0) {
        if (x >= knots[i] and x < knots[i + 1]) {
            return 1.0;
        }
        // Handle the boundary case for the very last knot
        if (x == knots[knots.len - 1] and i == knots.len - 2) {
            return 1.0;
        }
        return 0.0;
    }

    var result: f32 = 0.0;

    // Left term
    const den1 = knots[i + p] - knots[i];
    if (den1 > 0) {
        result += ((x - knots[i]) / den1) * basis(i, p - 1, x, knots);
    }

    // Right term
    const den2 = knots[i + p + 1] - knots[i + 1];
    if (den2 > 0) {
        result += ((knots[i + p + 1] - x) / den2) * basis(i + 1, p - 1, x, knots);
    }

    return result;
}

/// Analytical derivative of the B-spline basis function N_{i,p}(x) with respect to x.
/// This is required for enforcing the Eikonal loss in SDF training.
pub fn derivative(i: usize, p: usize, x: f32, knots: []const f32) f32 {
    if (p == 0) return 0.0;

    var result: f32 = 0.0;

    // Left term derivative
    const den1 = knots[i + p] - knots[i];
    if (den1 > 0) {
        result += (@as(f32, @floatFromInt(p)) / den1) * basis(i, p - 1, x, knots);
    }

    // Right term derivative
    const den2 = knots[i + p + 1] - knots[i + 1];
    if (den2 > 0) {
        result -= (@as(f32, @floatFromInt(p)) / den2) * basis(i + 1, p - 1, x, knots);
    }

    return result;
}

test "B-Spline Basis: Order 0 (Step Function)" {
    const knots = [_]f32{ 0.0, 1.0, 2.0, 3.0 };
    
    // x=0.5 is in [0, 1), so basis 0 should be 1
    try std.testing.expectEqual(@as(f32, 1.0), basis(0, 0, 0.5, &knots));
    // x=1.5 is in [1, 2), so basis 1 should be 1
    try std.testing.expectEqual(@as(f32, 1.0), basis(1, 0, 1.5, &knots));
    // x=0.5 is not in [1, 2), so basis 1 should be 0
    try std.testing.expectEqual(@as(f32, 0.0), basis(1, 0, 0.5, &knots));
}

test "B-Spline Basis: Order 1 (Linear)" {
    const knots = [_]f32{ 0.0, 1.0, 2.0 };
    
    // N_{0,1}(x) peaks at x=1 and goes to 0 at x=0 and x=2
    try std.testing.expectEqual(@as(f32, 0.5), basis(0, 1, 0.5, &knots));
    try std.testing.expectEqual(@as(f32, 0.5), basis(0, 1, 1.5, &knots));
    // At exactly the knot 1.0, it should be 1.0 (if we consider both sides)
    // but the recursive logic handles the spans.
}

test "B-Spline Derivative: Order 1 (Linear)" {
    const knots = [_]f32{ 0.0, 1.0, 2.0 };
    
    // N_{0,1}(x) is linear from x=0 (y=0) to x=1 (y=1). Slope should be 1.0.
    try std.testing.expectEqual(@as(f32, 1.0), derivative(0, 1, 0.5, &knots));
    
    // N_{0,1}(x) is linear from x=1 (y=1) to x=2 (y=0). Slope should be -1.0.
    try std.testing.expectEqual(@as(f32, -1.0), derivative(0, 1, 1.5, &knots));
}

test "SplineGrid: Vectorized Evaluation" {
    const allocator = std.testing.allocator;
    var grid = try SplineGrid.init(allocator, 4);
    defer grid.deinit(allocator);

    // Set some coefficients for testing
    grid.coeffs[0] = 1.0;
    grid.coeffs[1] = 0.5;

    // Evaluate 4 points at once using SIMD
    const Vector = @Vector(4, f32);
    const x_batch: Vector = .{ 0.1, 0.2, 0.3, 0.4 };
    var results: [4]f32 = undefined;

    grid.evaluateBatch(x_batch, &results);

    // Verify results (this confirms that the SIMD wrapper correctly evaluates)
    for (0..4) |j| {
        var expected: f32 = 0.0;
        for (0..grid.coeffs.len) |i| {
            expected += grid.coeffs[i] * basis(i, SplineConfig.Order, x_batch[j], grid.knots);
        }
        try std.testing.expectApproxEqRel(expected, results[j], 1e-5);
    }
}
