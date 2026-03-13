const std = @import("std");
const core = @import("core");
const sandbox = core.sandbox;
const Orchestrator = core.Orchestrator;

const abi = @cImport({
    @cInclude("moontide.h");
});

const sql = @cImport({
    @cInclude("sqlite3.h");
});

var global_orch: ?*Orchestrator = null;

const SQLiteNode = struct {
    allocator: std.mem.Allocator,
    db: ?*sql.sqlite3,
    
    cmd_wire: ?[*]u8 = null, // Command string wire (1KB)
    res_wire: ?[*]u8 = null, // Result string wire (1KB)

    pub fn init(allocator: std.mem.Allocator) !*SQLiteNode {
        const self = try allocator.create(SQLiteNode);
        self.allocator = allocator;
        
        if (sql.sqlite3_open(":memory:", &self.db) != sql.SQLITE_OK) {
            std.debug.print("[SQLite Ext] Failed to open in-memory database.\n", .{});
            return error.SQLiteInitFailed;
        }

        std.debug.print("[SQLite Ext] SOTA Data Intelligence Bridge Initialized.\n", .{});
        return self;
    }

    pub fn deinit(self: *SQLiteNode) void {
        _ = sql.sqlite3_close(self.db);
        self.allocator.destroy(self);
    }

    pub fn executeCommand(self: *SQLiteNode) void {
        const cmd_ptr = self.cmd_wire orelse return;
        const res_ptr = self.res_wire orelse return;

        if (cmd_ptr[0] == 0) return;

        const cmd_str = std.mem.span(@as([*c]u8, @ptrCast(cmd_ptr)));

        // Note: For full SOTA, we'd implement a Virtual Table here to read other Wires.
        // For v0.1, we'll execute the raw SQL command and return the first result as a string.
        
        var stmt: ?*sql.sqlite3_stmt = null;
        if (sql.sqlite3_prepare_v2(self.db, cmd_str.ptr, -1, &stmt, null) == sql.SQLITE_OK) {
            if (sql.sqlite3_step(stmt) == sql.SQLITE_ROW) {
                const text = sql.sqlite3_column_text(stmt, 0);
                const text_len = std.mem.span(text).len;
                const copy_len = if (text_len > 1023) 1023 else text_len;
                @memcpy(res_ptr[0..copy_len], text[0..copy_len]);
                res_ptr[copy_len] = 0;
            }
            _ = sql.sqlite3_finalize(stmt);
        } else {
            const err = sql.sqlite3_errmsg(self.db);
            std.debug.print("[SQLite Ext] SQL Error: {s}\n", .{err});
        }

        // Clear command
        cmd_ptr[0] = 0;
    }
};

// --- ABI IMPLEMENTATION ---

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.moontide_node_h {
    _ = name; _ = script_path;
    const node = SQLiteNode.init(std.heap.c_allocator) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.moontide_node_h) void {
    const node: *SQLiteNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, access: usize) abi.moontide_status_t {
    const node: *SQLiteNode = @ptrCast(@alignCast(handle));
    const wire_name = std.mem.span(name);
    _ = access;

    if (std.mem.eql(u8, wire_name, "sqlite.commands")) {
        node.cmd_wire = @ptrCast(@alignCast(ptr));
    } else if (std.mem.eql(u8, wire_name, "sqlite.results")) {
        node.res_wire = @ptrCast(@alignCast(ptr));
    }

    return abi.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h) abi.moontide_status_t {
    const node: *SQLiteNode = @ptrCast(@alignCast(handle));
    node.executeCommand();
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
