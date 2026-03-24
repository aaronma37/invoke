const std = @import("std");
const manifold_ext = @import("manifold_ext.zig");

test "FFI Bridge: Initialization and Coefficients" {
    const layer_dims = [_]usize{ 2, 8, 8 };
    const num_coeffs = 8;
    
    // 1. Init
    const handle = manifold_ext.manifold_init(&layer_dims, 3, num_coeffs).?;
    defer manifold_ext.manifold_deinit(handle);

    // 2. Set Coefficients (A simple flat plane)
    const c_count = num_coeffs * num_coeffs * 3;
    var c_data = try std.heap.page_allocator.alloc(f32, c_count);
    defer std.heap.page_allocator.free(c_data);
    @memset(c_data, 0.5);
    
    manifold_ext.manifold_set_coeffs(handle, c_data.ptr, c_count);

    // 3. Verify Get Coeffs
    const retrieved = manifold_ext.manifold_get_coeffs(handle).?;
    try std.testing.expectEqual(retrieved[0], 0.5);
}

test "FFI Bridge: Pinned Forward Pass" {
    const layer_dims = [_]usize{ 2, 4 };
    const num_coeffs = 8;
    const handle = manifold_ext.manifold_init(&layer_dims, 2, num_coeffs).?;
    defer manifold_ext.manifold_deinit(handle);

    const socket_points = [_][3]f32{ .{2, 2, 2} } ** 8;
    manifold_ext.manifold_set_socket(handle, 1, &socket_points, 8); // Bottom pin

    const inputs = [_]f32{ 0.5, 0.0 };
    var outputs = [_]f32{ 0, 0, 0 };
    
    // Setup activations double-pointer
    var act0 = [_]f32{ 0, 0 };
    var act1 = [_]f32{ 0, 0, 0, 0 };
    var acts_ptrs = [_][*]f32{ &act0, &act1 };

    manifold_ext.manifold_forward_pinned(handle, &inputs, &acts_ptrs, &outputs, 1);

    // Verify pinning through FFI
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), outputs[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), outputs[1], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), outputs[2], 1e-5);
}
