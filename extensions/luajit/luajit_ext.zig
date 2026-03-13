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

    pub fn init(allocator: std.mem.Allocator, name: [*c]const u8, script_path: [*c]const u8) !*LuaNode {
        const self = try allocator.create(LuaNode);
        self.allocator = allocator;
        self.name = try allocator.dupe(u8, std.mem.span(name));
        
        self.L = c.luaL_newstate() orelse return error.LuaInitFailed;
        c.luaL_openlibs(self.L);
        
        // Expose moontide table to Lua
        c.lua_newtable(self.L);
        
        c.lua_pushlightuserdata(self.L, self);
        c.lua_pushcclosure(self.L, luaLog, 1);
        c.lua_setfield(self.L, -2, "log");
        
        c.lua_pushcfunction(self.L, luaPoke);
        c.lua_setfield(self.L, -2, "poke");

        c.lua_pushcfunction(self.L, luaSleep);
        c.lua_setfield(self.L, -2, "sleep");
        
        c.lua_setglobal(self.L, "moontide");

        const s_path = std.mem.span(script_path);
        if (!std.mem.eql(u8, s_path, "none")) {
            // Initial load
            if (c.luaL_loadfile(self.L, script_path) != 0 or c.lua_pcall(self.L, 0, c.LUA_MULTRET, 0) != 0) {
                const err = c.lua_tolstring(self.L, -1, null);
                std.debug.print("[LuaJIT Init Error] {s}\n", .{err});
            }
        }
        
        return self;
    }

    pub fn deinit(self: *LuaNode) void {
        c.lua_close(self.L);
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }
};

fn luaLog(L: ?*c.lua_State) callconv(.C) c_int {
    const node_ptr: *LuaNode = @ptrCast(@alignCast(c.lua_touserdata(L, c.lua_upvalueindex(1))));
    const message = c.luaL_checklstring(L, 1, null);
    
    if (global_log_handler) |log| {
        log.?(c.MOONTIDE_LOG_INFO, node_ptr.name.ptr, message);
    }
    return 0;
}

fn luaPoke(L: ?*c.lua_State) callconv(.C) c_int {
    const event_name = c.luaL_checklstring(L, 1, null);
    if (global_poke_handler) |poke| {
        poke.?(event_name);
    }
    return 0;
}

fn luaSleep(L: ?*c.lua_State) callconv(.C) c_int {
    const ms = c.luaL_checkinteger(L, 1);
    std.time.sleep(@intCast(ms * std.time.ns_per_ms));
    return 0;
}

// --- ABI IMPLEMENTATION ---

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
    const node: *LuaNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, access: usize) abi.moontide_status_t {
    sandbox.checkPoints();
    const node: *LuaNode = @ptrCast(@alignCast(handle));
    _ = access;

    c.lua_pushlightuserdata(node.L, ptr);
    
    var buf: [256]u8 = undefined;
    const wire_name = std.mem.span(name);
    const global_name = std.fmt.bufPrintZ(&buf, "wire_{s}", .{wire_name}) catch return c.MOONTIDE_STATUS_ERROR;
    for (global_name) |*char| if (char.* == '.') { char.* = '_'; };

    c.lua_setglobal(node.L, global_name.ptr);
    return c.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h) abi.moontide_status_t {
    const node: *LuaNode = @ptrCast(@alignCast(handle));
    
    c.lua_getglobal(node.L, "tick");
    if (c.lua_type(node.L, -1) == c.LUA_TFUNCTION) {
        if (c.lua_pcall(node.L, 0, 0, 0) != c.LUA_OK) {
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
    const node: *LuaNode = @ptrCast(@alignCast(handle));
    
    if (c.luaL_loadfile(node.L, script_path) != c.LUA_OK or c.lua_pcall(node.L, 0, c.LUA_MULTRET, 0) != c.LUA_OK) {
        const err = c.lua_tolstring(node.L, -1, null);
        std.debug.print("[LuaJIT Extension Reload Error] {s}\n", .{err});
        c.lua_pop(node.L, 1);
        return c.MOONTIDE_STATUS_ERROR;
    }
    
    return c.MOONTIDE_STATUS_OK;
}

export fn add_trigger(handle: abi.moontide_node_h, event_name: [*c]const u8) abi.moontide_status_t {
    _ = handle;
    _ = event_name;
    return c.MOONTIDE_STATUS_OK;
}

export fn poll_events(handle: abi.moontide_node_h) bool {
    _ = handle;
    return true;
}

// --- ENTRY POINT ---

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
