const std = @import("std");
const core = @import("core");
const sandbox = core.sandbox;

const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lualib.h");
    @cInclude("lauxlib.h");
    @cInclude("moontide.h");
});

const abi = c;

var global_log_handler: ?abi.moontide_log_fn = null;
var global_poke_handler: ?abi.moontide_poke_fn = null;

const LuaNode = struct {
    L: *c.lua_State,
    name: []const u8,
    allocator: std.mem.Allocator,
    basal_mem: i32 = 0,

    pub fn init(allocator: std.mem.Allocator, name_c: [*c]const u8, script_path: [*c]const u8) !*LuaNode {
        const self = try allocator.create(LuaNode);
        const name_span = std.mem.span(name_c);
        self.allocator = allocator;
        self.name = try allocator.dupe(u8, name_span);
        
        self.L = c.luaL_newstate() orelse return error.LuaInitFailed;
        c.luaL_openlibs(self.L);
        
        // Ensure ffi is loaded
        _ = c.luaL_dostring(self.L, "ffi = require('ffi')");

        // Expose moontide table to Lua
        c.lua_newtable(self.L);
        
        c.lua_pushlightuserdata(self.L, self);
        c.lua_pushcclosure(self.L, luaLog, 1);
        c.lua_setfield(self.L, -2, "log");

        c.lua_setglobal(self.L, "moontide");

        const script_path_span = std.mem.span(script_path);
        if (!std.mem.eql(u8, script_path_span, "none")) {
            const script_path_z = try allocator.dupeZ(u8, script_path_span);
            defer allocator.free(script_path_z);

            if (c.luaL_loadfile(self.L, script_path_z.ptr) != c.LUA_OK or c.lua_pcall(self.L, 0, c.LUA_MULTRET, 0) != c.LUA_OK) {
                const err = c.lua_tolstring(self.L, -1, null);
                std.debug.print("[LuaJIT Extension Load Error] {s}\n", .{err});
            }
        }
        
        self.basal_mem = c.lua_gc(self.L, c.LUA_GCCOUNT, 0);
        return self;
    }

    pub fn deinit(self: *LuaNode) void {
        c.lua_close(self.L);
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }
};

fn luaLog(L: ?*c.lua_State) callconv(.C) i32 {
    const node: *LuaNode = @ptrCast(@alignCast(c.lua_touserdata(L, c.lua_upvalueindex(1))));
    const msg = c.lua_tolstring(L, 1, null);
    if (global_log_handler) |log| {
        log.?(c.MOONTIDE_LOG_INFO, node.name.ptr, msg);
    }
    return 0;
}

export fn set_log_handler(handler: abi.moontide_log_fn) void {
    global_log_handler = handler;
}

export fn set_poke_handler(handler: abi.moontide_poke_fn) void {
    global_poke_handler = handler;
}

export fn set_orchestrator_handler(orch: ?*anyopaque) void { _ = orch; }

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.moontide_node_h {
    const node = LuaNode.init(std.heap.c_allocator, name, script_path) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.moontide_node_h) void {
    if (handle == null) return;
    const node: *LuaNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, schema: [*c]const u8, access: usize) abi.moontide_status_t {
    sandbox.checkPoints();
    if (handle == null) return c.MOONTIDE_STATUS_ERROR;
    const node: *LuaNode = @ptrCast(@alignCast(handle));
    _ = access;

    const wire_name = std.mem.span(name);
    const schema_str = std.mem.span(schema);
    const base_ptr: [*]u8 = @ptrCast(ptr.?);

    var buf: [256]u8 = undefined;
    const global_name = std.fmt.bufPrintZ(&buf, "wire_{s}", .{wire_name}) catch return c.MOONTIDE_STATUS_ERROR;
    for (global_name) |*char| if (char.* == '.') { char.* = '_'; };

    // --- SOA VIEW GENERATION (LUA) ---
    c.lua_getglobal(node.L, global_name.ptr);
    if (c.lua_type(node.L, -1) != c.LUA_TTABLE) {
        c.lua_pop(node.L, 1);
        c.lua_newtable(node.L);
        c.lua_pushvalue(node.L, -1);
        c.lua_setglobal(node.L, global_name.ptr);
    }
    const table_idx = c.lua_gettop(node.L);

    c.lua_getglobal(node.L, "ffi");
    c.lua_getfield(node.L, -1, "cast");
    const cast_func_idx = c.lua_gettop(node.L);

    var current_offset: usize = 0;
    var it = std.mem.tokenizeAny(u8, schema_str, ";");
    while (it.next()) |entry| {
        var parts = std.mem.tokenizeAny(u8, entry, ":");
        const f_name = parts.next() orelse continue;
        const f_type_raw = parts.next() orelse continue;

        var f_type = f_type_raw;
        if (std.mem.indexOf(u8, f_type_raw, "[")) |idx| {
            f_type = f_type_raw[0..idx];
        }

        const c_type = if (std.mem.eql(u8, f_type, "f32")) "float*"
                  else if (std.mem.eql(u8, f_type, "f64")) "double*"
                  else if (std.mem.eql(u8, f_type, "i32")) "int32_t*"
                  else if (std.mem.eql(u8, f_type, "u32")) "uint32_t*"
                  else if (std.mem.eql(u8, f_type, "bool")) "bool*"
                  else "uint8_t*";

        c.lua_pushvalue(node.L, cast_func_idx);
        c.lua_pushlstring(node.L, c_type.ptr, c_type.len);
        c.lua_pushlightuserdata(node.L, base_ptr + current_offset);
        if (c.lua_pcall(node.L, 2, 1, 0) == c.LUA_OK) {
            const f_name_z = node.allocator.dupeZ(u8, f_name) catch continue;
            defer node.allocator.free(f_name_z);
            c.lua_setfield(node.L, table_idx, f_name_z.ptr);
        } else {
            c.lua_pop(node.L, 1);
        }

        var count: usize = 1;
        if (std.mem.indexOf(u8, f_type_raw, "[")) |idx| {
            const end = std.mem.indexOf(u8, f_type_raw, "]") orelse f_type_raw.len;
            count = std.fmt.parseInt(usize, f_type_raw[idx+1..end], 10) catch 1;
        }
        const base_size: usize = if (std.mem.eql(u8, f_type, "f32")) 4
                          else if (std.mem.eql(u8, f_type, "f64")) 8
                          else if (std.mem.eql(u8, f_type, "i32")) 4
                          else if (std.mem.eql(u8, f_type, "u32")) 4
                          else 1;
        current_offset += base_size * count;
    }
    c.lua_pop(node.L, 3);
    return c.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h, pulse_count: u64) abi.moontide_status_t {
    if (handle == null) return c.MOONTIDE_STATUS_OK;
    const node: *LuaNode = @ptrCast(@alignCast(handle));
    
    c.lua_getglobal(node.L, "tick");
    if (c.lua_type(node.L, -1) == c.LUA_TFUNCTION) {
        c.lua_pushinteger(node.L, @intCast(pulse_count));
        if (c.lua_pcall(node.L, 1, 0, 0) != c.LUA_OK) {
            const err = c.lua_tolstring(node.L, -1, null);
            std.debug.print("[LuaJIT Extension Error] {s}\n", .{err});
            c.lua_pop(node.L, 1);
            return c.MOONTIDE_STATUS_ERROR;
        }
    } else {
        c.lua_pop(node.L, 1);
    }
    
    return c.MOONTIDE_STATUS_OK;
}

export fn reload_node(handle: abi.moontide_node_h, script_path: [*c]const u8) abi.moontide_status_t {
    if (handle == null) return c.MOONTIDE_STATUS_OK;
    const node: *LuaNode = @ptrCast(@alignCast(handle));
    const path = std.mem.span(script_path);
    if (std.mem.eql(u8, path, "none")) return c.MOONTIDE_STATUS_OK;

    const path_z = node.allocator.dupeZ(u8, path) catch return c.MOONTIDE_STATUS_ERROR;
    defer node.allocator.free(path_z);

    if (c.luaL_loadfile(node.L, path_z.ptr) != c.LUA_OK or c.lua_pcall(node.L, 0, c.LUA_MULTRET, 0) != c.LUA_OK) {
        const err = c.lua_tolstring(node.L, -1, null);
        std.debug.print("[LuaJIT Reload Error] {s}\n", .{err});
        c.lua_pop(node.L, 1);
        return c.MOONTIDE_STATUS_ERROR;
    }
    
    return c.MOONTIDE_STATUS_OK;
}

export fn add_trigger(handle: abi.moontide_node_h, event_name: [*c]const u8) abi.moontide_status_t {
    _ = handle; _ = event_name;
    return c.MOONTIDE_STATUS_OK;
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
