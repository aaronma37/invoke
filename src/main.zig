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
    } else if (std.mem.eql(u8, command, "sdk")) {
        if (args.len < 3) {
            printUsage();
            return;
        }
        if (std.mem.eql(u8, args[2], "install")) {
            try cmdSdkInstall(allocator);
        } else {
            printUsage();
        }
    } else if (std.mem.eql(u8, command, "version")) {
        std.debug.print("Moontide Neural Oscillator v0.6.0\n", .{});
        std.debug.print("Silicon ABI v{d}\n", .{node.abi.MOONTIDE_ABI_VERSION});
    } else {
        printUsage();
    }
}

fn printUsage() void {
    std.debug.print(
        \\Moontide Neural: The Silicon Brain Motherboard
        \\
        \\Usage:
        \\  moontide run [topology.lua]   Boot the pulse oscillator
        \\  moontide init                Scaffold a new Neural project
        \\  moontide sdk install         Install SDK headers and runtimes globally
        \\  moontide version             Display version info
        \\
    , .{});
}

fn cmdInit() !void {
    std.debug.print("[CLI] Scaffolding new Moontide Neural project...\n", .{});
    
    try std.fs.cwd().makePath("ext");
    try std.fs.cwd().makePath("gen");
    
    const default_topo = 
        \\return {
        \\  namespaces = {
        \\    brain = {
        \\      wires = { reservoir = "potentials:f32[1024];thresholds:f32[1024]" },
        \\      nodes = {}
        \\    }
        \\  }
        \\}
    ;
    
    try std.fs.cwd().writeFile(.{ .sub_path = "topology.lua", .data = default_topo });
    std.debug.print("[CLI] Created topology.lua, ext/, and gen/.\n", .{});
}

fn cmdSdkInstall(allocator: std.mem.Allocator) !void {
    std.debug.print("[CLI] Installing Moontide SDK globally...\n", .{});

    // 1. Install Header
    const header_src = "sdk/moontide.h";
    const header_dst = "/usr/local/include/moontide.h";
    
    std.fs.cwd().access(header_src, .{}) catch {
        std.debug.print("[Error] Could not find {s}. Are you in the root of the Moontide repo?\n", .{header_src});
        return error.HeaderNotFound;
    };

    std.debug.print("  -> Copying header to {s}...\n", .{header_dst});
    const header_data = try std.fs.cwd().readFileAlloc(allocator, header_src, 1024 * 1024);
    defer allocator.free(header_data);

    std.fs.cwd().writeFile(.{ .sub_path = header_dst, .data = header_data }) catch |err| {
        if (err == error.AccessDenied) {
            std.debug.print("[Error] Permission denied. Please run with sudo: sudo ./zig-out/bin/moontide sdk install\n", .{});
        } else {
            std.debug.print("[Error] Failed to install header: {any}\n", .{err});
        }
        return err;
    };

    // 2. Install Runtimes (Extensions)
    const lib_dir_dst = "/usr/local/lib/moontide/ext/";
    std.debug.print("  -> Preparing runtime directory {s}...\n", .{lib_dir_dst});
    
    std.fs.cwd().makePath(lib_dir_dst) catch |err| {
        if (err == error.AccessDenied) {
            std.debug.print("[Error] Permission denied creating lib directory.\n", .{});
            return err;
        }
    };

    var ext_dir = std.fs.cwd().openDir("ext", .{ .iterate = true }) catch {
        std.debug.print("[Warning] No 'ext/' directory found. Skipping runtime installation. Run 'zig build' first.\n", .{});
        return;
    };
    defer ext_dir.close();

    var it = ext_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".so")) {
            std.debug.print("  -> Installing runtime: {s}\n", .{entry.name});
            const lib_data = try ext_dir.readFileAlloc(allocator, entry.name, 50 * 1024 * 1024);
            defer allocator.free(lib_data);
            
            const full_dst = try std.fs.path.join(allocator, &.{ lib_dir_dst, entry.name });
            defer allocator.free(full_dst);
            
            try std.fs.cwd().writeFile(.{ .sub_path = full_dst, .data = lib_data });
        }
    }

    std.debug.print("[CLI] SDK Installation Complete!\n", .{});
}

fn cmdRun(allocator: std.mem.Allocator, topo_path: []const u8) !void {
    std.debug.print("Initializing Moontide Neural Oscillator...\n", .{});

    // Register Signal Handler
    sandbox.initSignalHandler();

    var orch: orchestrator.Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();
    
    // Set current_orch before any reloadTopology calls!
    @import("core/extension.zig").current_orch = &orch;

    var last_topology_mtime: i128 = 0;
    var pulse_count: u32 = 0;

    while (true) {
        pulse_count += 1;
        
        // --- 0. OS EVENT POLLING ---
        var node_it = orch.nodes.valueIterator();
        while (node_it.next()) |n| {
            if (n.*.vtable.poll_events) |poll| {
                if (!poll(n.*.handle)) return; // Exit if window closed
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
            std.debug.print("\n[Kernel] Hot-swapping NEURAL TOPOLOGY...\n", .{});
            last_topology_mtime = stat.mtime;
            sandbox.is_recovering = false;
            reloadTopology(allocator, &orch, topo_path) catch |err| {
                std.debug.print("[Kernel Error] Failed to reload topology: {any}\n", .{err});
            };
        }

        // 2. RESILIENT NEURAL HEARTBEAT (1000Hz Pulse)
        sandbox.is_recovering = true;
        if (sandbox.c.setjmp(&sandbox.jump_buffer) == 0) {
            try orch.tick();
        } else {
            std.debug.print("\n[Kernel] RECOVERY (Pulse {d}): A Neural Node attempted a memory violation!\n", .{pulse_count});
        }
        sandbox.is_recovering = false;

        orch.swapAllWires();
        
        // 1ms = 1000Hz update frequency for Liquid State Machines
        std.time.sleep(1 * std.time.ns_per_ms);

        // 3. Monitor
        if (orch.getWire("brain.reservoir")) |w| {
            if (pulse_count % 100 == 0) {
                w.setAccess(std.posix.PROT.READ);
                const potentials: [*]f32 = @ptrCast(@alignCast(w.ptr()));
                std.debug.print("\r[Monitor] Pulse {d: >8} | Neuron 0 Pot: {d: >5.3} | Neuron 1 Pot: {d: >5.3}   ", 
                    .{ pulse_count, potentials[0], potentials[1] });
                w.setAccess(std.posix.PROT.NONE);
            }
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
    try c_headers.appendSlice("#ifndef MOONTIDE_WIRES_H\n#define MOONTIDE_WIRES_H\n\n#include <stdint.h>\n#include <stdbool.h>\n\n");

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
                const size = schema.CalculateSchemaSize(w_schema);
                const w = try orch.addWire(full_path, w_schema, size, w_buffered);

                if (std.mem.eql(u8, full_path, "brain.reservoir")) {
                    w.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
                    const base: [*]f32 = @ptrCast(@alignCast(w.backPtr()));
                    // Initialize thresholds to 0.5
                    for (1048576 .. 1048576 * 2) |i| {
                        base[i] = 0.5;
                    }
                    w.setAccess(std.posix.PROT.NONE);
                }
                
                if (std.mem.eql(u8, full_path, "brain.synapses")) {
                    w.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
                    const back_ptr: [*]u8 = @ptrCast(w.backPtr());
                    const base: [*]u32 = @ptrCast(@alignCast(back_ptr));
                    const weights: [*]f32 = @ptrCast(@alignCast(back_ptr + 33554432 * 4));
                    
                    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
                    const rand = prng.random();

                    for (0..1048576) |ni| {
                        for (0..32) |ci| {
                            const synapse_idx = ni * 32 + ci;
                            const offset = @as(i32, @intCast(rand.uintLessThan(u32, 200))) - 100;
                            const target = @as(u32, @intCast(@max(0, @min(1048575, @as(i32, @intCast(ni)) + offset))));
                            base[synapse_idx] = target;
                            weights[synapse_idx] = rand.float(f32) * 0.1;
                        }
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
                            }
                            l.lua_pop(L, 1);
                        }
                    }
                    l.lua_pop(L, 1);
                }

                allocator.free(n.script_path);
                n.script_path = try allocator.dupe(u8, n_script);

                l.lua_pop(L, 1); 
            }
        }
        l.lua_pop(L, 1); 
        l.lua_pop(L, 1); 
    }
    l.lua_pop(L, 1); 

    try orch.rebuildTaskGraph();
}
