const std = @import("std");
const core = @import("core");
const wire = core.wire;
const node = core.node;
const simd = @import("moontide_simd");

test "Neural Propagation Determinism" {
    std.testing.refAllDecls(simd);
    const allocator = std.heap.page_allocator;
    var orch: core.Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    // 1. Create a 2-neuron reservoir
    const res_schema = "potentials:f32[2];thresholds:f32[2];spikes:u32[1]";
    const res_wire = try orch.addWire("test.reservoir", res_schema, 20, true);
    
    // 2. Create 1-synapse fabric (Neuron 0 -> Neuron 1)
    const syn_schema = "targets:u32[1];weights:f32[1]";
    const syn_wire = try orch.addWire("test.synapses", syn_schema, 8, false);

    // Setup initial state: Neuron 0 is at threshold, Neuron 1 is at 0
    res_wire.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
    const res_ptr: [*]f32 = @ptrCast(@alignCast(res_wire.backPtr()));
    res_ptr[0] = 1.0; // Potential 0
    res_ptr[1] = 0.0; // Potential 1
    res_ptr[2] = 0.5; // Threshold 0
    res_ptr[3] = 0.5; // Threshold 1
    res_wire.setAccess(std.posix.PROT.NONE);

    // Setup synapse: 0 -> 1 with weight 0.25
    syn_wire.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
    const syn_targets: [*]u32 = @ptrCast(@alignCast(syn_wire.banks[0].ptr));
    const syn_weights: [*]f32 = @ptrCast(@alignCast(syn_wire.banks[0].ptr + 4));
    syn_targets[0] = 1;
    syn_weights[0] = 0.25;
    syn_wire.setAccess(std.posix.PROT.NONE);

    // 3. Manually run the propagation logic (simulating the extension)
    res_wire.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
    syn_wire.setAccess(std.posix.PROT.READ);
    const potentials = res_ptr[0..2];
    const thresholds = res_ptr[2..4];
    
    for (potentials, 0..) |*p, i| {
        if (p.* > thresholds[i]) {
            p.* = 0; // Reset
            const target = syn_targets[0];
            const weight = syn_weights[0];
            potentials[target] += weight;
        }
    }
    res_wire.setAccess(std.posix.PROT.NONE);
    syn_wire.setAccess(std.posix.PROT.NONE);

    // 4. Verify results
    res_wire.setAccess(std.posix.PROT.READ);
    try std.testing.expectEqual(@as(f32, 0.0), potentials[0]); // Neuron 0 reset
    try std.testing.expectEqual(@as(f32, 0.25), potentials[1]); // Neuron 1 received spike
    res_wire.setAccess(std.posix.PROT.NONE);
}
