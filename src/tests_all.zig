const std = @import("std");
const kan_layer = @import("core/kan_layer.zig");

test "KanLayer: Spline Parity Sanity" {
    const allocator = std.testing.allocator;
    var layer = try kan_layer.KanLayer.init(allocator, 1, 1, 8);
    defer layer.deinit();

    // Set all coefficients to 1.0
    for (layer.coeffs) |*c| c.* = 1.0;

    const input = [_]f32{ 0.0 };
    const output = try allocator.alloc(f32, 1);
    defer allocator.free(output);

    layer.forward(&input, output, 1);
    
    // SiLU(0) = 0.
    // Sum of Spline basis at 0.0 should be approx 1.0 (partition of unity)
    // So output should be 1.0
    std.debug.print("\nSanity Test - Input: 0.0, Output: {d:0.4}\n", .{output[0]});
    try std.testing.expect(output[0] > 0.5);
}

test {
    _ = @import("core/benchmark_test.zig");
    _ = @import("core/kan_layer.zig");
    _ = @import("core/kan_spline.zig");
    _ = @import("core/kan_network.zig");
    _ = @import("core/kan_trainer.zig");
    _ = @import("tests/pipeline_test.zig");
}
