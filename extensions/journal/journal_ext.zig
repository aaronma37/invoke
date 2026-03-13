const std = @import("std");
const core = @import("core");
const sandbox = core.sandbox;
const Orchestrator = core.Orchestrator;

const abi = @cImport({
    @cInclude("moontide.h");
});

var global_orch: ?*Orchestrator = null;
var last_save_ms: i64 = 0;

const JournalNode = struct {
    allocator: std.mem.Allocator,
    save_path: []const u8,
    interval_ms: i64 = 5000,
    config_ptr: ?*JournalConfig = null,

    const JournalConfig = extern struct {
        interval_ms: i32,
        force_save: i32,
        force_load: i32,
    };

    pub fn init(allocator: std.mem.Allocator) !*JournalNode {
        const self = try allocator.create(JournalNode);
        self.allocator = allocator;
        self.save_path = try allocator.dupe(u8, "journal.bin");
        self.config_ptr = null;
        return self;
    }

    pub fn deinit(self: *JournalNode) void {
        self.allocator.free(self.save_path);
        self.allocator.destroy(self);
    }

    pub fn save(self: *JournalNode) !void {
        if (global_orch) |orch| {
            std.debug.print("[Journal] Saving Eternal State to '{s}'...\n", .{self.save_path});
            const file = try std.fs.cwd().createFile(self.save_path, .{});
            defer file.close();
            try orch.dumpToWriter(file.writer());
            last_save_ms = std.time.milliTimestamp();
        }
    }

    pub fn load(self: *JournalNode) !void {
        if (global_orch) |orch| {
            std.debug.print("[Journal] Loading Eternal State from '{s}'...\n", .{self.save_path});
            const file = std.fs.cwd().openFile(self.save_path, .{}) catch |err| {
                if (err == error.FileNotFound) {
                    std.debug.print("[Journal] Error: Snapshot not found. Skipping load.\n", .{});
                    return;
                }
                return err;
            };
            defer file.close();
            try orch.loadFromReader(file.reader());
        }
    }
};

// --- ABI IMPLEMENTATION ---

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.moontide_node_h {
    _ = name; _ = script_path;
    const node = JournalNode.init(std.heap.c_allocator) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.moontide_node_h) void {
    const node: *JournalNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, access: usize) abi.moontide_status_t {
    const node: *JournalNode = @ptrCast(@alignCast(handle));
    const wire_name = std.mem.span(name);
    _ = access;

    if (std.mem.eql(u8, wire_name, "journal.config")) {
        node.config_ptr = @ptrCast(@alignCast(ptr));
    }

    return abi.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h) abi.moontide_status_t {
    const node: *JournalNode = @ptrCast(@alignCast(handle));
    const now = std.time.milliTimestamp();
    
    // 1. Sync Interval from Wire
    if (node.config_ptr) |config| {
        if (config.interval_ms > 0) node.interval_ms = config.interval_ms;
        
        // 2. Handle forced commands from Wire
        if (config.force_save != 0) {
            config.force_save = 0;
            node.save() catch {};
        }
        if (config.force_load != 0) {
            config.force_load = 0;
            node.load() catch {};
        }
    }

    // 3. Auto-save check
    if (now - last_save_ms > node.interval_ms) {
        node.save() catch |err| {
            std.debug.print("[Journal] Save failed: {any}\n", .{err});
        };
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

export fn set_poke_handler(handler: abi.moontide_poke_fn) void {
    _ = handler;
    // Note: To listen for pokes, the Orchestrator would need a central 
    // event registry that extensions can register for. For now, we'll
    // rely on the tick-based auto-save.
}

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
