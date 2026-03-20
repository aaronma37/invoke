const std = @import("std");
const moontide = @import("moontide");
const simd = @import("moontide_simd");

const abi = @cImport({
    @cInclude("moontide.h");
});

const ReservoirWire = struct {
    potentials: []f32,
    thresholds: []f32,
    spikes: []u32,
    history: []f32,
};

const SynapsesWire = struct {
    targets: []u32,
    weights: []f32,
};

const SpikingNode = struct {
    name: []const u8,
    allocator: std.mem.Allocator,
    reservoir: ?ReservoirWire = null,
    synapses: ?SynapsesWire = null,

    pub fn init(allocator: std.mem.Allocator, name_c: [*c]const u8) !*SpikingNode {
        const self = try allocator.create(SpikingNode);
        self.allocator = allocator;
        self.name = try allocator.dupe(u8, std.mem.span(name_c));
        self.reservoir = null;
        return self;
    }

    pub fn deinit(self: *SpikingNode) void {
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }
};

var global_log_handler: ?abi.moontide_log_fn = null;

export fn set_log_handler(handler: abi.moontide_log_fn) void {
    global_log_handler = handler;
}

export fn create_node(name: [*c]const u8, _: [*c]const u8) abi.moontide_node_h {
    const node = SpikingNode.init(std.heap.c_allocator, name) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.moontide_node_h) void {
    if (handle == null) return;
    const node: *SpikingNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, schema: [*c]const u8, _: usize) abi.moontide_status_t {
    if (handle == null) return abi.MOONTIDE_STATUS_ERROR;
    const node: *SpikingNode = @ptrCast(@alignCast(handle));
    const wire_name = std.mem.span(name);
    
    if (std.mem.eql(u8, wire_name, "reservoir")) {
        const float_ptr: [*]f32 = @ptrCast(@alignCast(ptr.?));
        node.reservoir = .{
            .potentials = float_ptr[0..1048576],
            .thresholds = float_ptr[1048576 .. 1048576 * 2],
            .spikes = @as([*]u32, @ptrCast(@alignCast(float_ptr + 1048576 * 2)))[0..2048],
            .history = float_ptr[1048576 * 2 + 2048 .. 1048576 * 3 + 2048],
        };
    } else if (std.mem.eql(u8, wire_name, "synapses")) {
        const u32_ptr: [*]u32 = @ptrCast(@alignCast(ptr.?));
        const f32_ptr: [*]f32 = @ptrCast(@alignCast(ptr.?));
        node.synapses = .{
            .targets = u32_ptr[0..33554432],
            .weights = f32_ptr[33554432 .. 33554432 * 2],
        };
    }
    _ = schema;
    return abi.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h, pulse_count: u64) abi.moontide_status_t {
    if (handle == null) return abi.MOONTIDE_STATUS_OK;
    const node: *SpikingNode = @ptrCast(@alignCast(handle));
    
    if (std.mem.indexOf(u8, node.name, "liquid_physics") != null) {
        if (node.reservoir) |res| {
            // --- 1. THE NEURAL PULSE (SIMD LEAK) ---
            simd.leak(res.potentials, 0.99);

            // --- 2. THE SPIKE THRESHOLD & PROPAGATION ---
            for (res.potentials, 0..) |*p, i| {
                if (p.* > res.thresholds[i]) {
                    p.* = 0; // Reset potential
                    res.history[i] = @floatFromInt(pulse_count); // Record spike time
                    
                    // PROPAGATE SPIKE TO NEIGHBORS
                    if (node.synapses) |syn| {
                        const start_syn = i * 32;
                        const end_syn = start_syn + 32;
                        simd.propagate(res.potentials, syn.targets[start_syn..end_syn], syn.weights[start_syn..end_syn]);
                    }
                }
            }
        }
    } else if (std.mem.indexOf(u8, node.name, "plasticity_stdp") != null) {
        if (node.reservoir) |res| {
            if (node.synapses) |syn| {
                // HEBBIAN LEARNING: Neurons that fire together, wire together.
                // We only update a subset of synapses per tick to keep background latency low.
                const chunk_size = 1024;
                const start_n = (pulse_count % 64) * chunk_size;
                const end_n = start_n + chunk_size;

                for (start_n..end_n) |ni| {
                    const t_pre = res.history[ni];
                    if (t_pre == 0) continue;

                    for (0..32) |ci| {
                        const si = ni * 32 + ci;
                        const target = syn.targets[si];
                        const t_post = res.history[target];
                        
                        if (t_post == 0) continue;

                        const dt = t_post - t_pre;
                        if (dt > 0 and dt < 10) {
                            // Potentiation: Pre-synaptic fired JUST BEFORE post-synaptic
                            syn.weights[si] = @min(1.0, syn.weights[si] + 0.001);
                        } else if (dt < 0 and dt > -10) {
                            // Depression: Pre-synaptic fired JUST AFTER post-synaptic
                            syn.weights[si] = @max(0.0, syn.weights[si] - 0.001);
                        }
                    }
                }
            }
        }
    }
    
    return abi.MOONTIDE_STATUS_OK;
}

export fn moontide_ext_init() abi.moontide_extension_t {
    var vtable: abi.moontide_extension_t = std.mem.zeroes(abi.moontide_extension_t);
    vtable.abi_version = abi.MOONTIDE_ABI_VERSION;
    vtable.create_node = create_node;
    vtable.destroy_node = destroy_node;
    vtable.bind_wire = bind_wire;
    vtable.tick = tick;
    vtable.set_log_handler = set_log_handler;
    return vtable;
}
