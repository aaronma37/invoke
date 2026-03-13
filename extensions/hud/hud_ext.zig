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

var global_orch: ?*orchestrator.Orchestrator = null;

const HudNode = struct {
    allocator: std.mem.Allocator,
    camera: rl.Camera2D,

    pub fn init(allocator: std.mem.Allocator) !*HudNode {
        const self = try allocator.create(HudNode);
        self.allocator = allocator;
        self.camera = .{
            .offset = .{ .x = 400, .y = 300 },
            .target = .{ .x = 0, .y = 0 },
            .rotation = 0,
            .zoom = 1.0,
        };

        // Initialize Raylib
        rl.InitWindow(800, 600, "Moontide Motherboard Visualizer");
        rl.SetTargetFPS(60);
        
        return self;
    }

    pub fn deinit(self: *HudNode) void {
        rl.CloseWindow();
        self.allocator.destroy(self);
    }

    pub fn draw(self: *HudNode) void {
        // Interaction (Only if window is alive)
        if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_RIGHT)) {
            const delta = rl.GetMouseDelta();
            self.camera.target.x -= delta.x / self.camera.zoom;
            self.camera.target.y -= delta.y / self.camera.zoom;
        }
        self.camera.zoom += rl.GetMouseWheelMove() * 0.1;
        if (self.camera.zoom < 0.1) self.camera.zoom = 0.1;

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.MAROON);

        rl.BeginMode2D(self.camera);
        
        if (global_orch) |orch| {
            const level_spacing: f32 = 300.0;
            const node_spacing: f32 = 100.0;

            // Draw a big yellow circle at origin to verify world-space
            rl.DrawCircle(0, 0, 50, rl.YELLOW);
            rl.DrawText("WORLD ORIGIN", -40, 60, 10, rl.BLACK);

            if (orch.getWire("world.particles")) |w| {
                w.setAccess(std.posix.PROT.READ);
                const ptr: [*]u8 = @ptrCast(w.ptr());
                const count = @as(*i32, @ptrCast(@alignCast(ptr))).*;
                var count_buf: [32]u8 = undefined;
                const count_text = std.fmt.bufPrintZ(&count_buf, "PARTICLES ON WIRE: {d}", .{count}) catch "ERR";
                rl.DrawText(count_text.ptr, -100, -100, 20, rl.GREEN);
                w.setAccess(std.posix.PROT.NONE);
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
        } else {
            rl.DrawText("Awaiting Motherboard Handshake...", -100, 0, 20, rl.GRAY);
        }

        rl.EndMode2D();

        rl.DrawFPS(10, 10);
        rl.DrawText("Moontide v0.7.0 | Deterministic Parallelism ACTIVE", 10, 580, 10, rl.DARKGRAY);
    }

    fn getNodePos(self: *HudNode, orch: *orchestrator.Orchestrator, n: *node_pkg.Node) rl.Vector2 {
        _ = self;
        const level_spacing: f32 = 300.0;
        const node_spacing: f32 = 100.0;

        for (orch.levels.items, 0..) |level, l_idx| {
            const x = @as(f32, @floatFromInt(l_idx)) * level_spacing;
            const start_y = -@as(f32, @floatFromInt(level.items.len)) * node_spacing / 2.0;
            for (level.items, 0..) |ln, n_idx| {
                if (ln == n) {
                    const y = start_y + @as(f32, @floatFromInt(n_idx)) * node_spacing;
                    return .{ .x = x, .y = y };
                }
            }
        }
        return .{ .x = 0, .y = 0 };
    }

    pub fn pollEvents(self: *HudNode) bool {
        _ = self;
        rl.PollInputEvents();
        return !rl.WindowShouldClose();
    }
};

// --- ABI IMPLEMENTATION ---

export fn poll_events(handle: abi.moontide_node_h) bool {
    const node = @as(*HudNode, @ptrCast(@alignCast(handle)));
    return node.pollEvents();
}

export fn set_orchestrator_handler(orch: ?*anyopaque) void {
    global_orch = @ptrCast(@alignCast(orch));
}

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.moontide_node_h {
    _ = name; _ = script_path;
    const node = HudNode.init(std.heap.c_allocator) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.moontide_node_h) void {
    const node: *HudNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, access: usize) abi.moontide_status_t {
    _ = handle; _ = name; _ = ptr; _ = access;
    sandbox.checkPoints();
    return abi.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h) abi.moontide_status_t {
    const node: *HudNode = @ptrCast(@alignCast(handle));
    node.draw();
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
