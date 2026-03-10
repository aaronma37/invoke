const std = @import("std");

const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lualib.h");
    @cInclude("lauxlib.h");
    @cInclude("invoke_abi.h");
});

const abi = c;

const LuaNode = struct {
    L: *c.lua_State,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: [*c]const u8, script_path: [*c]const u8) !*LuaNode {
        const self = try allocator.create(LuaNode);
        self.allocator = allocator;
        
        self.L = c.luaL_newstate() orelse return error.LuaInitFailed;
        c.luaL_openlibs(self.L);
        
        _ = name;
        // Initial load
        _ = c.luaL_loadfile(self.L, script_path);
        _ = c.lua_pcall(self.L, 0, c.LUA_MULTRET, 0);
        
        return self;
    }

    pub fn deinit(self: *LuaNode) void {
        c.lua_close(self.L);
        self.allocator.destroy(self);
    }
};

// --- ABI IMPLEMENTATION ---

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.invoke_node_h {
    const node = LuaNode.init(std.heap.c_allocator, name, script_path) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.invoke_node_h) void {
    const node: *LuaNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.invoke_node_h, name: [*c]const u8, ptr: ?*anyopaque, size: usize) abi.invoke_status_t {
    const node: *LuaNode = @ptrCast(@alignCast(handle));
    _ = size;

    c.lua_pushlightuserdata(node.L, ptr);
    
    // Format global name: wire_<name> (replacing dots with underscores)
    var buf: [256]u8 = undefined;
    const wire_name = std.mem.span(name);
    const global_name = std.fmt.bufPrintZ(&buf, "wire_{s}", .{wire_name}) catch return c.INVOKE_STATUS_ERROR;
    for (global_name) |*char| {
        if (char.* == '.') char.* = '_';
    }

    c.lua_setglobal(node.L, global_name.ptr);
    return c.INVOKE_STATUS_OK;
}

export fn tick(handle: abi.invoke_node_h) abi.invoke_status_t {
    const node: *LuaNode = @ptrCast(@alignCast(handle));
    
    c.lua_getglobal(node.L, "tick");
    if (c.lua_type(node.L, -1) == c.LUA_TFUNCTION) {
        if (c.lua_pcall(node.L, 0, 0, 0) != c.LUA_OK) {
            const err = c.lua_tolstring(node.L, -1, null);
            std.debug.print("[LuaJIT Extension Error] {s}\n", .{err});
            c.lua_pop(node.L, 1);
            return c.INVOKE_STATUS_ERROR;
        }
    } else {
        c.lua_pop(node.L, 1);
    }
    
    return c.INVOKE_STATUS_OK;
}

export fn reload_node(handle: abi.invoke_node_h, script_path: [*c]const u8) abi.invoke_status_t {
    const node: *LuaNode = @ptrCast(@alignCast(handle));
    
    if (c.luaL_loadfile(node.L, script_path) != c.LUA_OK or c.lua_pcall(node.L, 0, c.LUA_MULTRET, 0) != c.LUA_OK) {
        const err = c.lua_tolstring(node.L, -1, null);
        std.debug.print("[LuaJIT Extension Reload Error] {s}\n", .{err});
        c.lua_pop(node.L, 1);
        return c.INVOKE_STATUS_ERROR;
    }
    
    return c.INVOKE_STATUS_OK;
}

export fn add_trigger(handle: abi.invoke_node_h, event_name: [*c]const u8) abi.invoke_status_t {
    _ = handle;
    _ = event_name;
    return c.INVOKE_STATUS_OK;
}

// --- ENTRY POINT ---

export fn invoke_ext_init() abi.invoke_extension_t {
    return .{
        .create_node = create_node,
        .destroy_node = destroy_node,
        .bind_wire = bind_wire,
        .tick = tick,
        .reload_node = reload_node,
        .add_trigger = add_trigger,
    };
}
