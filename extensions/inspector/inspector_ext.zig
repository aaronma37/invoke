const std = @import("std");
const core = @import("core");
const schema = core.schema;
const Orchestrator = core.Orchestrator;
const wire_pkg = core.wire;

const abi = @cImport({
    @cInclude("moontide.h");
});

const rl = @cImport({
    @cInclude("raylib.h");
});

var global_orch: ?*Orchestrator = null;

const InspectorNode = struct {
    allocator: std.mem.Allocator,
    selected_wire: ?[]const u8 = null,
    scroll_y: f32 = 0,

    pub fn init(allocator: std.mem.Allocator) !*InspectorNode {
        const self = try allocator.create(InspectorNode);
        self.allocator = allocator;
        self.selected_wire = null;
        self.scroll_y = 0;

        rl.InitWindow(400, 800, "Moontide Motherboard Inspector");
        rl.SetTargetFPS(60);
        return self;
    }

    pub fn deinit(self: *InspectorNode) void {
        rl.CloseWindow();
        self.allocator.destroy(self);
    }

    pub fn draw(self: *InspectorNode) void {
        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.GetColor(0x181818FF));
        
        var y: f32 = 20 + self.scroll_y;
        rl.DrawText("MOTHERBOARD INSPECTOR", 10, @intFromFloat(y), 20, rl.SKYBLUE);
        y += 40;

        if (global_orch) |orch| {
            // --- WIRE LIST ---
            var it = orch.wires.iterator();
            while (it.next()) |entry| {
                const name = entry.key_ptr.*;
                const w = entry.value_ptr.*;
                
                const is_selected = if (self.selected_wire) |sel| std.mem.eql(u8, sel, name) else false;
                const color = if (is_selected) rl.YELLOW else rl.RAYWHITE;
                const bg_color = if (is_selected) rl.DARKBLUE else rl.DARKGRAY;

                // Simple Button Logic
                const rect = rl.Rectangle{ .x = 10, .y = y, .width = 380, .height = 30 };
                rl.DrawRectangleRec(rect, bg_color);
                rl.DrawRectangleLinesEx(rect, 1, color);
                rl.DrawText(name.ptr, 20, @intFromFloat(y + 5), 15, color);

                if (rl.CheckCollisionPointRec(rl.GetMousePosition(), rect)) {
                    if (rl.IsMouseButtonPressed(rl.MOUSE_LEFT_BUTTON)) {
                        self.selected_wire = name;
                    }
                }
                y += 35;

                // --- IF SELECTED: DRAW FIELDS ---
                if (is_selected) {
                    w.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
                    defer w.setAccess(std.posix.PROT.NONE);

                    var s_it = schema.SchemaIterator.init(w.schema_str);
                    const ptr: [*]u8 = @ptrCast(w.ptr());

                    while (s_it.next()) |field| {
                        rl.DrawText(field.name.ptr, 30, @intFromFloat(y), 15, rl.GRAY);
                        
                        var val_buf: [64]u8 = undefined;
                        const val_text = switch (field.type_tag) {
                            .f32 => std.fmt.bufPrintZ(&val_buf, "{d:.4}", .{@as(*f32, @ptrCast(@alignCast(ptr + field.offset))).*}) catch "ERR",
                            .i32 => std.fmt.bufPrintZ(&val_buf, "{d}", .{@as(*i32, @ptrCast(@alignCast(ptr + field.offset))).*}) catch "ERR",
                            .u32 => std.fmt.bufPrintZ(&val_buf, "{d}", .{@as(*u32, @ptrCast(@alignCast(ptr + field.offset))).*}) catch "ERR",
                            .bool => std.fmt.bufPrintZ(&val_buf, "{}", .{@as(*bool, @ptrCast(@alignCast(ptr + field.offset))).*}) catch "ERR",
                            else => "...",
                        };

                        rl.DrawText(val_text.ptr, 200, @intFromFloat(y), 15, rl.WHITE);
                        
                        // "POKE" Interaction (Very basic for now)
                        if (rl.CheckCollisionPointRec(rl.GetMousePosition(), .{ .x = 200, .y = y, .width = 100, .height = 20 })) {
                            if (rl.IsMouseButtonPressed(rl.MOUSE_LEFT_BUTTON)) {
                                if (field.type_tag == .f32) {
                                    @as(*f32, @ptrCast(@alignCast(ptr + field.offset))).* += 1.0;
                                } else if (field.type_tag == .i32) {
                                    @as(*i32, @ptrCast(@alignCast(ptr + field.offset))).* += 1;
                                }
                            }
                        }

                        y += 20;
                    }
                    y += 20; // Extra spacing after selected wire
                }
            }
        } else {
            rl.DrawText("Awaiting Motherboard...", 10, @intFromFloat(y), 20, rl.DARKGRAY);
        }

        // Scroll Input
        const wheel = rl.GetMouseWheelMove();
        self.scroll_y += wheel * 20.0;
        if (self.scroll_y > 0) self.scroll_y = 0;
    }
};

// --- ABI IMPLEMENTATION ---

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.moontide_node_h {
    _ = name; _ = script_path;
    const node = InspectorNode.init(std.heap.c_allocator) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.moontide_node_h) void {
    const node: *InspectorNode = @ptrCast(@alignCast(handle));
    node.deinit();
}
export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, schema_str: [*c]const u8, access: usize) abi.moontide_status_t {
    _ = handle; _ = name; _ = ptr; _ = schema_str; _ = access;
    return abi.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h, pulse_count: u64) abi.moontide_status_t {
    _ = pulse_count;
    const node: *InspectorNode = @ptrCast(@alignCast(handle));
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
export fn set_orchestrator_handler(orch: ?*anyopaque) void {
    global_orch = @ptrCast(@alignCast(orch));
}

export fn poll_events(handle: abi.moontide_node_h) bool {
    _ = handle;
    rl.PollInputEvents();
    return !rl.WindowShouldClose();
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
