const std = @import("std");
const abi = @cImport({
    @cInclude("invoke_abi.h");
});
const core = @import("core");
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
        rl.InitWindow(800, 600, "Invoke Motherboard Visualizer");
        rl.SetTargetFPS(60);
        
        return self;
    }

    pub fn deinit(self: *HudNode) void {
        rl.CloseWindow();
        self.allocator.destroy(self);
    }

    pub fn draw(self: *HudNode) void {
        if (rl.WindowShouldClose()) return;

        // Interaction
        if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_RIGHT)) {
            const delta = rl.GetMouseDelta();
            self.camera.target.x -= delta.x / self.camera.zoom;
            self.camera.target.y -= delta.y / self.camera.zoom;
        }
        self.camera.zoom += rl.GetMouseWheelMove() * 0.1;
        if (self.camera.zoom < 0.1) self.camera.zoom = 0.1;

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.GetColor(0x181818FF));

        rl.BeginMode2D(self.camera);
        
        if (global_orch) |orch| {
            const level_spacing: f32 = 300.0;
            const node_spacing: f32 = 100.0;

            // 1. Draw Wires (Connections)
            // For now, we'll just draw the nodes and their levels.
            
            // 2. Draw Nodes
            for (orch.levels.items, 0..) |level, l_idx| {
                const x = @as(f32, @floatFromInt(l_idx)) * level_spacing;
                const start_y = -@as(f32, @floatFromInt(level.items.len)) * node_spacing / 2.0;

                for (level.items, 0..) |n, n_idx| {
                    const y = start_y + @as(f32, @floatFromInt(n_idx)) * node_spacing;
                    
                    // Draw node circle
                    rl.DrawCircleV(.{ .x = x, .y = y }, 30, rl.DARKGRAY);
                    rl.DrawCircleLinesV(.{ .x = x, .y = y }, 30, rl.SKYBLUE);
                    
                    // Draw name
                    const name_c = @as([*c]const u8, @ptrCast(n.name.ptr));
                    rl.DrawText(name_c, @intFromFloat(x - 40), @intFromFloat(y + 40), 10, rl.RAYWHITE);
                    
                    // Draw "Last Tick" status (glow if executing)
                    // (Requires adding a 'last_tick_time' to node struct)
                }
            }
        } else {
            rl.DrawText("Awaiting Motherboard Handshake...", -100, 0, 20, rl.GRAY);
        }

        rl.EndMode2D();

        // Overlay
        rl.DrawFPS(10, 10);
        rl.DrawText("Invoke v0.6.0 | Deterministic Parallelism ACTIVE", 10, 580, 10, rl.DARKGRAY);
    }
};

// --- ABI IMPLEMENTATION ---

export fn set_orchestrator_handler(orch: ?*anyopaque) void {
    global_orch = @ptrCast(@alignCast(orch));
}

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.invoke_node_h {
    _ = name; _ = script_path;
    const node = HudNode.init(std.heap.c_allocator) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.invoke_node_h) void {
    const node: *HudNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.invoke_node_h, name: [*c]const u8, ptr: ?*anyopaque, access: usize) abi.invoke_status_t {
    _ = handle; _ = name; _ = ptr; _ = access;
    return abi.INVOKE_STATUS_OK;
}

export fn tick(handle: abi.invoke_node_h) abi.invoke_status_t {
    const node: *HudNode = @ptrCast(@alignCast(handle));
    node.draw();
    return abi.INVOKE_STATUS_OK;
}

export fn reload_node(handle: abi.invoke_node_h, script_path: [*c]const u8) abi.invoke_status_t {
    _ = handle; _ = script_path;
    return abi.INVOKE_STATUS_OK;
}

export fn add_trigger(handle: abi.invoke_node_h, event_name: [*c]const u8) abi.invoke_status_t {
    _ = handle; _ = event_name;
    return abi.INVOKE_STATUS_OK;
}

export fn set_log_handler(handler: abi.invoke_log_fn) void { _ = handler; }
export fn set_poke_handler(handler: abi.invoke_poke_fn) void { _ = handler; }

export fn invoke_ext_init() abi.invoke_extension_t {
    return .{
        .create_node = create_node,
        .destroy_node = destroy_node,
        .bind_wire = bind_wire,
        .tick = tick,
        .reload_node = reload_node,
        .add_trigger = add_trigger,
        .set_log_handler = set_log_handler,
        .set_poke_handler = set_poke_handler,
        .set_orchestrator_handler = set_orchestrator_handler,
    };
}
