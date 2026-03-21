const std = @import("std");

test {
    _ = @import("../src/core/benchmark_test.zig");
    _ = @import("../src/core/kan_layer.zig");
    _ = @import("../src/core/kan_spline.zig");
    _ = @import("../src/core/kan_network.zig");
    _ = @import("../src/core/kan_trainer.zig");
}
