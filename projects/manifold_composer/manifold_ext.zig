const std = @import("std");
const manifold_kan = @import("manifold_kan.zig");
const ManifoldNetwork = manifold_kan.ManifoldNetwork;
const BoundarySpline = manifold_kan.BoundarySpline;
const TopologyType = manifold_kan.TopologyType;

// C-compatible opaque handle
const ManifoldNetwork_t = *anyopaque;

export fn manifold_init(layer_dims: [*]const usize, num_layers: usize, num_coeffs: usize) ?ManifoldNetwork_t {
    const allocator = std.heap.page_allocator;
    const dims = layer_dims[0..num_layers];
    
    const net = allocator.create(ManifoldNetwork) catch return null;
    net.* = ManifoldNetwork.init(allocator, dims, num_coeffs) catch return null;
    
    return @as(ManifoldNetwork_t, @ptrCast(net));
}

export fn manifold_deinit(handle: ManifoldNetwork_t) void {
    const net = @as(*ManifoldNetwork, @ptrCast(@alignCast(handle)));
    net.deinit();
    net.allocator.destroy(net);
}

/// HARDENED: Set the topology type (open, periodic_u, etc.)
export fn manifold_set_topology(handle: ManifoldNetwork_t, topo_type: u32) void {
    const net = @as(*ManifoldNetwork, @ptrCast(@alignCast(handle)));
    net.topology_type = switch (topo_type) {
        0 => .open,
        1 => .periodic_u,
        2 => .periodic_uv,
        3 => .capped,
        else => .open,
    };
}

export fn manifold_set_socket(
    handle: ManifoldNetwork_t, 
    socket_type: u32,
    coeffs: [*]const [3]f32,
    num_points: usize
) void {
    const net = @as(*ManifoldNetwork, @ptrCast(@alignCast(handle)));
    const r = if (socket_type == 1) @as(usize, 0) else net.output_surface.num_v - 1;
    for (0..@min(net.output_surface.num_u, num_points)) |i| {
        const base = (r * net.output_surface.num_u + i) * net.output_surface.out_dim;
        net.output_surface.coeffs[base + 0] = coeffs[i][0];
        net.output_surface.coeffs[base + 1] = coeffs[i][1];
        net.output_surface.coeffs[base + 2] = coeffs[i][2];
    }
}

export fn manifold_get_coeffs(handle: ManifoldNetwork_t) ?[*]f32 {
    const net = @as(*ManifoldNetwork, @ptrCast(@alignCast(handle)));
    return net.output_surface.coeffs.ptr;
}

export fn manifold_set_coeffs(handle: ManifoldNetwork_t, data: [*]const f32, count: usize) void {
    const net = @as(*ManifoldNetwork, @ptrCast(@alignCast(handle)));
    const len = @min(count, net.output_surface.coeffs.len);
    @memcpy(net.output_surface.coeffs[0..len], data[0..len]);
}

export fn manifold_forward_pinned(
    handle: ManifoldNetwork_t,
    inputs: [*]const f32,
    activations: [*][*]f32,
    outputs: [*]f32,
    batch_size: usize
) void {
    const net = @as(*ManifoldNetwork, @ptrCast(@alignCast(handle)));
    
    var acts = net.allocator.alloc([]f32, net.hidden_layers.len + 1) catch return;
    defer net.allocator.free(acts);
    
    for (0..net.hidden_layers.len + 1) |i| {
        const dim = if (i == 0) net.hidden_layers[0].in_dim else net.hidden_layers[i-1].out_dim;
        acts[i] = activations[i][0 .. batch_size * dim];
    }

    net.forwardPinned(inputs[0 .. batch_size * net.hidden_layers[0].in_dim], acts, batch_size, outputs[0 .. batch_size * 3]);
}
