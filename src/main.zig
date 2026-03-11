const std = @import("std");
const orchestrator = @import("core/orchestrator.zig");
const wire = @import("core/wire.zig");
const node = @import("core/node.zig");
const schema = @import("core/schema.zig");
const sandbox = @import("core/sandbox.zig");

const l = @cImport({
    @cInclude("lua.h");
    @cInclude("lualib.h");
    @cInclude("lauxlib.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "run")) {
        const topo_path = if (args.len > 2) args[2] else "topology.lua";
        try cmdRun(allocator, topo_path);
    } else if (std.mem.eql(u8, command, "init")) {
        try cmdInit();
    } else if (std.mem.eql(u8, command, "version")) {
        std.debug.print("Invoke Kernel v0.5.0 (Lua-Config Edition)\n", .{});
        std.debug.print("Silicon ABI v{d}\n", .{node.abi.INVOKE_ABI_VERSION});
    } else {
        printUsage();
    }
}

fn printUsage() void {
    std.debug.print(
        \\Invoke: The AI-Native Runtime Engine
        \\
        \\Usage:
        \\  invoke run [topology.lua]   Boot the pure silicon kernel
        \\  invoke init                Scaffold a new Invoke project
        \\  invoke version             Display version info
        \\
    , .{});
}

fn cmdInit() !void {
    std.debug.print("[CLI] Scaffolding new Invoke project...\n", .{});
    
    try std.fs.cwd().makePath("ext");
    try std.fs.cwd().makePath("gen");
    
    const default_topo = 
        \\return {
        \\  namespaces = {
        \\    app = {
        \\      wires = { stats = "x:f32;y:f32" },
        \\      nodes = {}
        \\    }
        \\  }
        \\}
    ;
    
    try std.fs.cwd().writeFile(.{ .sub_path = "topology.lua", .data = default_topo });
    std.debug.print("[CLI] Created topology.lua, ext/, and gen/.\n", .{});
}

fn cmdRun(allocator: std.mem.Allocator, topo_path: []const u8) !void {
    std.debug.print("Initializing Invoke Kernel (Lua-Config Mode)...\n", .{});

    // Register Signal Handler
    sandbox.initSignalHandler();

    var orch: orchestrator.Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();
    
    @import("core/extension.zig").current_orch = &orch;

    var last_topology_mtime: i128 = 0;
    var frame_count: u32 = 0;

    while (true) {
        frame_count += 1;
        
        // --- 0. OS EVENT POLLING ---
        var node_it = orch.nodes.valueIterator();
        while (node_it.next()) |n| {
            if (n.vtable.poll_events) |poll| {
                if (!poll(n.handle)) return; // Exit if window closed
            }
        }
        
        // 1. Hot-Reloading Check
        const topo_file = std.fs.cwd().openFile(topo_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("Waiting for {s}...\n", .{topo_path});
                std.time.sleep(1 * std.time.ns_per_s);
                continue;
            } else return err;
        };
        const stat = try topo_file.stat();
        topo_file.close();

        if (stat.mtime > last_topology_mtime) {
            std.debug.print("\n[Kernel] Hot-swapping GRAPH TOPOLOGY (Lua)...\n", .{});
            last_topology_mtime = stat.mtime;
            sandbox.is_recovering = false;
            reloadTopology(allocator, &orch, topo_path) catch |err| {
                std.debug.print("[Kernel Error] Failed to reload topology: {any}\n", .{err});
            };
        }

        if (frame_count % 10 == 0) try orch.poke("on_collision");

        // 2. RESILIENT HEARTBEAT
        sandbox.is_recovering = true;
        if (sandbox.c.setjmp(&sandbox.jump_buffer) == 0) {
            try orch.tick();
        } else {
            std.debug.print("\n[Kernel] RECOVERY (Frame {d}): A Node attempted a memory violation! Motherboard survives.\n", .{frame_count});
        }
        sandbox.is_recovering = false;

        orch.swapAllWires();
        
        // 3. Monitor
        if (orch.getWire("swarm.boids_north")) |w| {
            w.setAccess(std.posix.PROT.READ);
            const ptr: [*]u8 = @ptrCast(w.ptr());
            const count = @as(*i32, @ptrCast(@alignCast(ptr))).*;
            const x = @as(*f32, @ptrCast(@alignCast(ptr + 4))).*;
            const y = @as(*f32, @ptrCast(@alignCast(ptr + 4004))).*;
            std.debug.print("[Monitor] Boids North: {d} | First Boid: ({d: >5.2}, {d: >5.2})\n", .{ count, x, y });
            w.setAccess(std.posix.PROT.NONE);
        } else if (orch.getWire("player.stats")) |w| {
            w.setAccess(std.posix.PROT.READ);
            const ptr: [*]u8 = @ptrCast(w.ptr());
            const x = @as(*f32, @ptrCast(@alignCast(ptr))).*;
            const health_offset: usize = if (std.mem.indexOf(u8, w.schema_str, "z:f32") != null) 12 else 8;
            const health = @as(*i32, @ptrCast(@alignCast(ptr + health_offset))).*;
            std.debug.print("[Monitor] Frame {d} | Player X: {d: >5.2} | HP: {d}\n", .{ frame_count, x, health });
            w.setAccess(std.posix.PROT.NONE);
        }
    }
}

fn reloadTopology(allocator: std.mem.Allocator, orch: *orchestrator.Orchestrator, path: []const u8) !void {
    const L = l.luaL_newstate() orelse return error.LuaInitFailed;
    defer l.lua_close(L);
    l.luaL_openlibs(L);

    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    if (l.luaL_dofile(L, path_z.ptr)) {
        const err_msg = l.lua_tolstring(L, -1, null);
        std.debug.print("[Kernel Error] Lua Topology Error: {s}\n", .{err_msg});
        return error.LuaTopologyError;
    }

    if (l.lua_type(L, -1) != l.LUA_TTABLE) return error.TopologyMustReturnTable;

    // Phase 1: Wires & Header Synthesis
    var c_headers = std.ArrayList(u8).init(allocator);
    defer c_headers.deinit();
    try c_headers.appendSlice("#ifndef INVOKE_WIRES_H\n#define INVOKE_WIRES_H\n\n#include <stdint.h>\n#include <stdbool.h>\n\n");

    var lua_headers = std.ArrayList(u8).init(allocator);
    defer lua_headers.deinit();
    try lua_headers.appendSlice("local ffi = require(\"ffi\")\nffi.cdef[[\ntypedef int int32_t;\ntypedef unsigned int uint32_t;\n\n");

    l.lua_getfield(L, -1, "namespaces");
    if (l.lua_type(L, -1) != l.LUA_TTABLE) return error.NoNamespaces;

    // Iterate over namespaces
    l.lua_pushnil(L);
    while (l.lua_next(L, -2) != 0) {
        const ns_name = std.mem.span(l.lua_tolstring(L, -2, null));
        
        l.lua_getfield(L, -1, "wires");
        if (l.lua_type(L, -1) == l.LUA_TTABLE) {
            l.lua_pushnil(L);
            while (l.lua_next(L, -2) != 0) {
                const w_name = std.mem.span(l.lua_tolstring(L, -2, null));
                var w_schema: []const u8 = undefined;
                var w_buffered = false;

                if (l.lua_type(L, -1) == l.LUA_TSTRING) {
                    w_schema = std.mem.span(l.lua_tolstring(L, -1, null));
                } else {
                    l.lua_getfield(L, -1, "schema");
                    w_schema = std.mem.span(l.lua_tolstring(L, -1, null));
                    l.lua_pop(L, 1);
                    l.lua_getfield(L, -1, "buffered");
                    w_buffered = if (l.lua_type(L, -1) == l.LUA_TBOOLEAN) l.lua_toboolean(L, -1) != 0 else false;
                    l.lua_pop(L, 1);
                }

                const full_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns_name, w_name });
                defer allocator.free(full_path);
                const w_existed = orch.getWire(full_path) != null;
                const size = schema.CalculateSchemaSize(w_schema);
                const w = try orch.addWire(full_path, w_schema, size, w_buffered);
                
                if (!w_existed and std.mem.eql(u8, full_path, "player.stats")) {
                    w.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
                    const base_ptr: [*]u8 = @ptrCast(w.backPtr());
                    const health_ptr: *i32 = @ptrCast(@alignCast(base_ptr + 8));
                    health_ptr.* = 100;
                    w.setAccess(std.posix.PROT.NONE);
                }

                if (!w_existed and std.mem.startsWith(u8, full_path, "swarm.boids")) {
                    w.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
                    const base_ptr: [*]u8 = @ptrCast(w.backPtr());
                    const count_ptr: *i32 = @ptrCast(@alignCast(base_ptr));
                    count_ptr.* = 100;

                    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
                    const rand = prng.random();
                    const is_north = std.mem.indexOf(u8, full_path, "north") != null;
                    const y_offset: f32 = if (is_north) 150.0 else -150.0;

                    for (0..100) |i| {
                        const px_ptr: *f32 = @ptrCast(@alignCast(base_ptr + 4 + (i * 4)));
                        const py_ptr: *f32 = @ptrCast(@alignCast(base_ptr + 4004 + (i * 4)));
                        const vx_ptr: *f32 = @ptrCast(@alignCast(base_ptr + 8004 + (i * 4)));
                        const vy_ptr: *f32 = @ptrCast(@alignCast(base_ptr + 12004 + (i * 4)));

                        px_ptr.* = rand.float(f32) * 400.0 - 200.0;
                        py_ptr.* = rand.float(f32) * 200.0 - 100.0 + y_offset;
                        vx_ptr.* = rand.float(f32) * 2.0 - 1.0;
                        vy_ptr.* = rand.float(f32) * 2.0 - 1.0;
                    }
                    w.setAccess(std.posix.PROT.NONE);
                }
                
                const struct_def = try schema.generateCStruct(allocator, full_path, w_schema);
                defer allocator.free(struct_def);
                try c_headers.appendSlice(struct_def);
                try lua_headers.appendSlice(struct_def);

                l.lua_pop(L, 1); 
            }
        }
        l.lua_pop(L, 1); 
        l.lua_pop(L, 1); 
    }
    l.lua_pop(L, 1); 

    try c_headers.appendSlice("#endif\n");
    try std.fs.cwd().makePath("gen");
    try std.fs.cwd().writeFile(.{ .sub_path = "gen/wires.h", .data = c_headers.items });

    try lua_headers.appendSlice("]]\nreturn {}\n");
    try std.fs.cwd().writeFile(.{ .sub_path = "gen_wires.lua", .data = lua_headers.items });

    // Phase 2: Nodes
    l.lua_getfield(L, -1, "namespaces");
    l.lua_pushnil(L);
    while (l.lua_next(L, -2) != 0) {
        const ns_name = std.mem.span(l.lua_tolstring(L, -2, null));
        l.lua_getfield(L, -1, "nodes");
        if (l.lua_type(L, -1) == l.LUA_TTABLE) {
            const n_count = l.lua_objlen(L, -1);
            for (1..n_count + 1) |i| {
                l.lua_pushinteger(L, @intCast(i));
                l.lua_gettable(L, -2); 

                l.lua_getfield(L, -1, "name");
                const n_name = std.mem.span(l.lua_tolstring(L, -1, null));
                l.lua_pop(L, 1);

                l.lua_getfield(L, -1, "type");
                const ext_type = std.mem.span(l.lua_tolstring(L, -1, null));
                l.lua_pop(L, 1);

                l.lua_getfield(L, -1, "mode");
                const n_mode_str = if (l.lua_type(L, -1) == l.LUA_TSTRING) std.mem.span(l.lua_tolstring(L, -1, null)) else "Heartbeat";
                l.lua_pop(L, 1);

                l.lua_getfield(L, -1, "script");
                const n_script = if (l.lua_type(L, -1) == l.LUA_TSTRING) std.mem.span(l.lua_tolstring(L, -1, null)) else "none";
                l.lua_pop(L, 1);

                const full_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns_name, n_name });
                defer allocator.free(full_path);
                const mode = if (std.mem.eql(u8, n_mode_str, "Poke")) orchestrator.ExecutionMode.Poke else orchestrator.ExecutionMode.Heartbeat;
                
                // BOOTLOADER FIX: Create node with "none" first
                const n = try orch.createNode(full_path, ext_type, mode, "none");
                
                l.lua_getfield(L, -1, "triggers");
                if (l.lua_type(L, -1) == l.LUA_TTABLE) {
                    const t_count = l.lua_objlen(L, -1);
                    for (1..t_count + 1) |ti| {
                        l.lua_pushinteger(L, @intCast(ti));
                        l.lua_gettable(L, -2);
                        try n.addTrigger(std.mem.span(l.lua_tolstring(L, -1, null)));
                        l.lua_pop(L, 1);
                    }
                }
                l.lua_pop(L, 1);

                var guest_offsets = std.ArrayList(u8).init(allocator);
                defer guest_offsets.deinit();
                try guest_offsets.appendSlice("#ifndef GUEST_OFFSETS_H\n#define GUEST_OFFSETS_H\n\n");
                var current_offset: usize = 0;

                var bound_paths = std.StringHashMap(void).init(allocator);
                defer {
                    var bit = bound_paths.keyIterator();
                    while (bit.next()) |k| allocator.free(k.*);
                    bound_paths.deinit();
                }

                inline for (.{ "reads", "writes" }) |field| {
                    l.lua_getfield(L, -1, field);
                    if (l.lua_type(L, -1) == l.LUA_TTABLE) {
                        const w_count = l.lua_objlen(L, -1);
                        for (1..w_count + 1) |wi| {
                            l.lua_pushinteger(L, @intCast(wi));
                            l.lua_gettable(L, -2);
                            const wire_ref = std.mem.span(l.lua_tolstring(L, -1, null));
                            const wire_path = if (std.mem.indexOf(u8, wire_ref, ".") != null) try allocator.dupe(u8, wire_ref) else try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns_name, wire_ref });
                            defer allocator.free(wire_path);

                            const access: u32 = if (std.mem.eql(u8, field, "reads")) std.posix.PROT.READ else (std.posix.PROT.READ | std.posix.PROT.WRITE);

                            if (orch.getWire(wire_path)) |w| {
                                n.bindWire(wire_ref, w, access);
                                
                                if (!bound_paths.contains(wire_path)) {
                                    try bound_paths.put(try allocator.dupe(u8, wire_path), {});
                                    const safe_ref = try allocator.dupe(u8, wire_ref);
                                    defer allocator.free(safe_ref);
                                    for (safe_ref) |*char| if (char.* == '.') { char.* = '_'; };
                                    try guest_offsets.writer().print("#define OFFSET_{s} 0x{X}\n", .{ safe_ref, current_offset });
                                    current_offset += (w.size + 15) & ~@as(usize, 15);
                                }
                            }
                            l.lua_pop(L, 1);
                        }
                    }
                    l.lua_pop(L, 1);
                }

                // FINALIZE: Set real script path so it loads after wires are bound
                allocator.free(n.script_path);
                n.script_path = try allocator.dupe(u8, n_script);

                try guest_offsets.appendSlice("\n#endif\n");
                if (std.mem.eql(u8, ext_type, "wasm")) {
                    const offset_filename = try std.fmt.allocPrint(allocator, "gen/{s}_offsets.h", .{n_name});
                    defer allocator.free(offset_filename);
                    try std.fs.cwd().writeFile(.{ .sub_path = offset_filename, .data = guest_offsets.items });
                }

                l.lua_pop(L, 1); 
            }
        }
        l.lua_pop(L, 1); 
        l.lua_pop(L, 1); 
    }
    l.lua_pop(L, 1); 

    try orch.rebuildTaskGraph();
}
