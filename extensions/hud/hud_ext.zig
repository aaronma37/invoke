const std = @import("std");
const core = @import("core");
const sandbox = core.sandbox;

const abi = @cImport({
    @cInclude("moontide.h");
});
const orchestrator = core;
const node_pkg = core.node;
const wire_pkg = core.wire;

const rl = @cImport({
    @cInclude("raylib.h");
});

const HudNode = struct {
    allocator: std.mem.Allocator,
    camera: rl.Camera2D,
    frame_count: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) !*HudNode {
        const self = try allocator.create(HudNode);
        self.allocator = allocator;
        self.frame_count = 0;
        
        rl.InitWindow(800, 600, "Moontide Motherboard Inspector");
        rl.SetTargetFPS(60);
        
        self.camera = .{
            .target = .{ .x = 0, .y = 0 },
            .offset = .{ .x = 400, .y = 300 },
            .rotation = 0,
            .zoom = 1.0,
        };
        
        return self;
    }

    pub fn deinit(self: *HudNode) void {
        rl.CloseWindow();
        self.allocator.destroy(self);
    }

    pub fn draw(self: *HudNode, orch: *orchestrator.Orchestrator) void {
        self.frame_count += 1;
        rl.BeginDrawing();
        rl.ClearBackground(rl.GetColor(0x181818FF));

        rl.BeginMode2D(self.camera);

        const node_spacing: f32 = 150.0;
        const level_spacing: f32 = 300.0;

        // Draw a big yellow circle at origin to verify world-space
        rl.DrawCircle(0, 0, 50, rl.YELLOW);
        rl.DrawText("WORLD ORIGIN", -40, 60, 10, rl.BLACK);

        // --- TRACKER VISUALIZATION ---
        if (orch.getWire("tracker.truth")) |w| {
            w.setAccess(std.posix.PROT.READ);
            const data: [*]f32 = @ptrCast(@alignCast(w.ptr()));
            const pos = data[0]; // pos
            rl.DrawCircleV(.{ .x = pos * 2.0, .y = 100 }, 10, rl.GREEN);
            rl.DrawText("TRUTH", @intFromFloat(pos * 2.0 - 20), 120, 10, rl.GREEN);
            w.setAccess(std.posix.PROT.NONE);
        }

        if (orch.getWire("tracker.sensor")) |w| {
            w.setAccess(std.posix.PROT.READ);
            const data: [*]f32 = @ptrCast(@alignCast(w.ptr()));
            const m_pos = data[0]; // measured_pos
            rl.DrawCircleV(.{ .x = m_pos * 2.0, .y = 100 }, 5, rl.RED);
            rl.DrawText("SENSOR", @intFromFloat(m_pos * 2.0 - 20), 80, 10, rl.RED);
            w.setAccess(std.posix.PROT.NONE);
        }

        if (orch.getWire("tracker.filter")) |w| {
            w.setAccess(std.posix.PROT.READ);
            const data: [*]f32 = @ptrCast(@alignCast(w.ptr()));
            const f_pos = data[0]; // pos
            const p00 = data[2];   // variance
            
            // Draw Estimate
            rl.DrawCircleV(.{ .x = f_pos * 2.0, .y = 150 }, 8, rl.SKYBLUE);
            rl.DrawText("KALMAN ESTIMATE", @intFromFloat(f_pos * 2.0 - 40), 170, 10, rl.SKYBLUE);
            
            // Draw Uncertainty (Variance)
            const width = @sqrt(p00) * 10.0;
            rl.DrawRectangleLines(@intFromFloat(f_pos * 2.0 - width/2.0), 140, @intFromFloat(width), 20, rl.BLUE);
            
            w.setAccess(std.posix.PROT.NONE);
        }

        // --- TF TREE VISUALIZATION (Robotic Arm) ---
        // Safety: Wait 1 second before reading TF wires to ensure animator has run
        if (self.frame_count > 60) {
            const tf_state_opt = orch.getWire("tf.state");
            if (tf_state_opt != null) {
                const tf_state = tf_state_opt.?;
                
                tf_state.setAccess(std.posix.PROT.READ);
                
                const ptr: [*]u8 = @ptrCast(tf_state.ptr());
                
                // Offsets based on: local_m:f32[16000];world_m:f32[16000];parents:i32[1000];count:i32
                const local_m_size = 16000 * 4;
                const world_m_size = 16000 * 4;
                const parents_size = 1000 * 4;
                
                const world_m: [*]f32 = @ptrCast(@alignCast(ptr + local_m_size));
                const parents: [*]i32 = @ptrCast(@alignCast(ptr + local_m_size + world_m_size));
                const count_ptr: *i32 = @ptrCast(@alignCast(ptr + local_m_size + world_m_size + parents_size));
                const count = count_ptr.*;
                
                if (count > 0 and count <= 1000) {
                    for (0..@as(usize, @intCast(count))) |i| {
                        const off = i * 16;
                        const px = world_m[off + 3] * 10.0;
                        const py = world_m[off + 7] * 10.0;
                        
                        const p_idx = parents[i];
                        if (p_idx >= 0 and p_idx < 1000) {
                            const p_off = @as(usize, @intCast(p_idx)) * 16;
                            const p_px = world_m[p_off + 3] * 10.0;
                            const p_py = world_m[p_off + 7] * 10.0;
                            rl.DrawLineV(.{ .x = p_px, .y = p_py }, .{ .x = px, .y = py }, rl.VIOLET);
                        }
                        rl.DrawCircleV(.{ .x = px, .y = py }, 2, rl.SKYBLUE);
                        
                        if (i >= 500) break; // Only draw first 500 for perf
                    }
                }
                
                tf_state.setAccess(std.posix.PROT.NONE);
            }
        }

        // 1. Draw Wires (Connections)
        var node_it = orch.nodes.valueIterator();
        while (node_it.next()) |n_ptr| {
            const n = n_ptr.*;
            var w_it = n.bound_wires.valueIterator();
            while (w_it.next()) |binding| {
                const w = binding.wire;
                const start_pos = self.getNodePos(orch, n);
                var other_node_it = orch.nodes.valueIterator();
                while (other_node_it.next()) |other_ptr| {
                    const other = other_ptr.*;
                    if (n == other) continue;
                    if (other.bound_wires.get(w.name)) |_| {
                        const end_pos = self.getNodePos(orch, other);
                        const color = if (binding.access & 2 != 0) rl.ORANGE else rl.DARKBLUE;
                        rl.DrawLineBezier(start_pos, end_pos, 2.0, color);
                    }
                }
            }
        }
        
        // 2. Draw Nodes
        for (orch.levels.items, 0..) |level, l_idx| {
            const x = @as(f32, @floatFromInt(l_idx)) * level_spacing;
            const start_y = -@as(f32, @floatFromInt(level.items.len)) * node_spacing / 2.0;

            for (level.items, 0..) |n, n_idx| {
                const y = start_y + @as(f32, @floatFromInt(n_idx)) * node_spacing;
                const color = if (n.is_jailed) rl.RED else rl.SKYBLUE;
                const fill = if (n.is_jailed) rl.MAROON else rl.DARKGRAY;

                rl.DrawCircleV(.{ .x = x, .y = y }, 30, fill);
                rl.DrawCircleLinesV(.{ .x = x, .y = y }, 30, color);
                
                const name_c = @as([*c]const u8, @ptrCast(n.name.ptr));
                rl.DrawText(name_c, @intFromFloat(x - 40), @intFromFloat(y + 40), 10, rl.RAYWHITE);
                
                if (n.is_jailed) {
                    rl.DrawText("JAILED", @intFromFloat(x - 20), @intFromFloat(y - 5), 10, rl.RED);
                } else if (n.strike_count > 0) {
                    var strike_buf: [16]u8 = undefined;
                    const strike_text = std.fmt.bufPrintZ(&strike_buf, "STRIKES: {d}", .{n.strike_count}) catch "ERR";
                    rl.DrawText(strike_text.ptr, @intFromFloat(x - 30), @intFromFloat(y - 5), 10, rl.ORANGE);
                }
            }
        }

        rl.EndMode2D();

        rl.DrawFPS(10, 10);
        rl.DrawText("Moontide v0.7.0 | Deterministic Parallelism ACTIVE", 10, 580, 10, rl.DARKGRAY);
        rl.EndDrawing();
    }

    fn getNodePos(self: *HudNode, orch: *orchestrator.Orchestrator, n: *node_pkg.Node) rl.Vector2 {
        _ = self;
        const l_spacing: f32 = 300.0;
        const n_spacing: f32 = 150.0;

        for (orch.levels.items, 0..) |level, l_idx| {
            const x = @as(f32, @floatFromInt(l_idx)) * l_spacing;
            const start_y = -@as(f32, @floatFromInt(level.items.len)) * n_spacing / 2.0;
            for (level.items, 0..) |ln, n_idx| {
                if (ln == n) {
                    const y = start_y + @as(f32, @floatFromInt(n_idx)) * n_spacing;
                    return .{ .x = x, .y = y };
                }
            }
        }
        return .{ .x = 0, .y = 0 };
    }

    pub fn pollEvents(self: *HudNode) bool {
        _ = self;
        if (rl.WindowShouldClose()) return false;
        return true;
    }
};

// --- ABI IMPLEMENTATION ---

var global_orch: ?*orchestrator.Orchestrator = null;

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.moontide_node_h {
    _ = name; _ = script_path;
    const node = HudNode.init(std.heap.c_allocator) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.moontide_node_h) void {
    if (handle == null) return;
    const node: *HudNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, schema: [*c]const u8, access: usize) abi.moontide_status_t {
    _ = handle; _ = name; _ = ptr; _ = schema; _ = access;
    return abi.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h, pulse_count: u64) abi.moontide_status_t {
    _ = pulse_count;
    const node: *HudNode = @ptrCast(@alignCast(handle));
    if (global_orch) |orch| {
        node.draw(orch);
    }
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
    const node: *HudNode = @ptrCast(@alignCast(handle));
    return node.pollEvents();
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
