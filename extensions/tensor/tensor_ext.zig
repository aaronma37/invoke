const std = @import("std");
const core = @import("core");
const sandbox = core.sandbox;
const Orchestrator = core.Orchestrator;
const simd = @import("moontide_simd");

const abi = @cImport({
    @cInclude("moontide.h");
});

var global_orch: ?*Orchestrator = null;

const MAX_COMMANDS = 32;
const MAX_MEMORY = 65536; // 64K floats = 256KB

const OP_NOP = 0;
const OP_MATMUL = 1; // dest = arg1 * arg2
const OP_ADD = 2;    // dest = arg1 + arg2
const OP_RELU = 3;   // dest = relu(arg1)
const OP_SIGMOID = 4;// dest = sigmoid(arg1)

const TensorCommand = extern struct {
    op: u32,
    arg1_offset: u32,
    arg2_offset: u32,
    dest_offset: u32,
    rows: u32,
    cols: u32,
    inner_dim: u32, // Used for matmul (arg1_cols / arg2_rows)
};

const TensorNode = struct {
    allocator: std.mem.Allocator,
    
    cmd_wire: ?[*]TensorCommand = null,
    mem_wire: ?[*]f32 = null,

    pub fn init(allocator: std.mem.Allocator) !*TensorNode {
        const self = try allocator.create(TensorNode);
        self.allocator = allocator;
        std.debug.print("[Tensor Ext] SOTA SIMD Tensor Engine Initialized.\n", .{});
        return self;
    }

    pub fn deinit(self: *TensorNode) void {
        self.allocator.destroy(self);
    }

    pub fn executeCommands(self: *TensorNode) void {
        const cmds = self.cmd_wire orelse return;
        const memory = self.mem_wire orelse return;

        for (0..MAX_COMMANDS) |i| {
            const cmd = &cmds[i];
            if (cmd.op == OP_NOP) continue;

            switch (cmd.op) {
                OP_MATMUL => {
                    // C (rows x cols) = A (rows x inner) * B (inner x cols)
                    const a = memory[cmd.arg1_offset .. cmd.arg1_offset + cmd.rows * cmd.inner_dim];
                    const b = memory[cmd.arg2_offset .. cmd.arg2_offset + cmd.inner_dim * cmd.cols];
                    var c = memory[cmd.dest_offset .. cmd.dest_offset + cmd.rows * cmd.cols];

                    for (0..cmd.rows) |r| {
                        for (0..cmd.cols) |col| {
                            var sum: f32 = 0.0;
                            // Inner loop (auto-vectorized by Zig in ReleaseFast/ReleaseSafe)
                            for (0..cmd.inner_dim) |k| {
                                sum += a[r * cmd.inner_dim + k] * b[k * cmd.cols + col];
                            }
                            c[r * cmd.cols + col] = sum;
                        }
                    }
                },
                OP_ADD => {
                    // C = A + B (element-wise)
                    const total_len = cmd.rows * cmd.cols;
                    const a = memory[cmd.arg1_offset .. cmd.arg1_offset + total_len];
                    const b = memory[cmd.arg2_offset .. cmd.arg2_offset + total_len];
                    const c = memory[cmd.dest_offset .. cmd.dest_offset + total_len];

                    simd.add(c, a, b);
                },
                OP_RELU => {
                    // C = max(0, A)
                    const total_len = cmd.rows * cmd.cols;
                    const a = memory[cmd.arg1_offset .. cmd.arg1_offset + total_len];
                    const c = memory[cmd.dest_offset .. cmd.dest_offset + total_len];

                    // Explicit SIMD RELU
                    var j: usize = 0;
                    while (j + simd.VEC_SIZE <= total_len) : (j += simd.VEC_SIZE) {
                        const va: simd.f32x8 = a[j..][0..simd.VEC_SIZE].*;
                        const vz: simd.f32x8 = @splat(0.0);
                        c[j..][0..simd.VEC_SIZE].* = @max(va, vz);
                    }
                    while (j < total_len) : (j += 1) {
                        c[j] = if (a[j] > 0.0) a[j] else 0.0;
                    }
                },
                OP_SIGMOID => {
                    // C = 1 / (1 + exp(-A))
                    const total_len = cmd.rows * cmd.cols;
                    const a = memory[cmd.arg1_offset .. cmd.arg1_offset + total_len];
                    const c = memory[cmd.dest_offset .. cmd.dest_offset + total_len];

                    // Explicit SIMD Sigmoid
                    var j: usize = 0;
                    while (j + simd.VEC_SIZE <= total_len) : (j += simd.VEC_SIZE) {
                        const va: simd.f32x8 = a[j..][0..simd.VEC_SIZE].*;
                        const vone: simd.f32x8 = @splat(1.0);
                        // Zig's @exp supports vectors
                        c[j..][0..simd.VEC_SIZE].* = vone / (vone + @exp(-va));
                    }
                    while (j < total_len) : (j += 1) {
                        c[j] = 1.0 / (1.0 + @exp(-a[j]));
                    }
                },
                else => {}
            }

            // Clear command after execution
            cmd.op = OP_NOP;
        }
    }
};

// --- ABI IMPLEMENTATION ---

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.moontide_node_h {
    _ = name; _ = script_path;
    const node = TensorNode.init(std.heap.c_allocator) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.moontide_node_h) void {
    const node: *TensorNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, schema: [*c]const u8, access: usize) abi.moontide_status_t {
    const node: *TensorNode = @ptrCast(@alignCast(handle));
    const wire_name = std.mem.span(name);
    _ = schema;
    _ = access;

    if (std.mem.eql(u8, wire_name, "tensor.commands")) {
        node.cmd_wire = @ptrCast(@alignCast(ptr));
    } else if (std.mem.eql(u8, wire_name, "tensor.memory")) {
        node.mem_wire = @ptrCast(@alignCast(ptr));
    }

    return abi.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h) abi.moontide_status_t {
    const node: *TensorNode = @ptrCast(@alignCast(handle));
    node.executeCommands();
    return abi.MOONTIDE_STATUS_OK;
}

export fn reload_node(handle: abi.moontide_node_h, script_path: [*c]const u8) abi.moontide_status_t {
    _ = handle; _ = script_path;
    return abi.MOONTIDE_STATUS_OK;
}

export fn add_trigger(handle: abi.moontide_node_h, event_name: [*c]const u8) abi.moontide_status_t {
    _ = handle; _ = event_name;
    return abi.MOONTIDE_STATUS_OK;
}

export fn set_log_handler(handler: abi.moontide_log_fn) void { _ = handler; }
export fn set_poke_handler(handler: abi.moontide_poke_fn) void { _ = handler; }
export fn set_orchestrator_handler(orch: ?*anyopaque) void {
    global_orch = @ptrCast(@alignCast(orch));
}
export fn poll_events(handle: abi.moontide_node_h) bool {
    _ = handle;
    return true;
}

export fn moontide_ext_init() abi.moontide_extension_t {
    return .{
        .abi_version = abi.MOONTIDE_ABI_VERSION,
        .create_node = create_node,
        .destroy_node = destroy_node,
        .bind_wire = bind_wire,
        .tick = tick,
        .reload_node = reload_node,
        .add_trigger = add_trigger,
        .set_log_handler = set_log_handler,
        .set_poke_handler = set_poke_handler,
        .set_orchestrator_handler = set_orchestrator_handler,
        .poll_events = poll_events,
    };
}
