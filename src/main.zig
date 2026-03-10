const std = @import("std");
const orchestrator = @import("core/orchestrator.zig");
const wire = @import("core/wire.zig");
const node = @import("core/node.zig");
const schema = @import("core/schema.zig");

// --- SIGNAL RECOVERY SYSTEM ---
const c = @cImport({
    @cInclude("signal.h");
    @cInclude("setjmp.h");
});

var jump_buffer: c.jmp_buf = undefined;
var is_recovering: bool = false;

fn segfault_handler(sig: c_int) callconv(.C) void {
    _ = sig;
    if (is_recovering) {
        c.longjmp(&jump_buffer, 1);
    } else {
        std.debug.print("\n[CRITICAL] Unrecoverable Segfault outside of Node execution.\n", .{});
        std.process.exit(1);
    }
}

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
        const topo_path = if (args.len > 2) args[2] else "topology.json";
        try cmdRun(allocator, topo_path);
    } else if (std.mem.eql(u8, command, "init")) {
        try cmdInit();
    } else if (std.mem.eql(u8, command, "version")) {
        std.debug.print("Invoke Kernel v0.4.0\n", .{});
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
        \\  invoke run [topology.json]  Boot the pure silicon kernel
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
        \\{
        \\  "namespaces": {
        \\    "app": {
        \\      "wires": { "stats": "x:f32;y:f32" },
        \\      "nodes": []
        \\    }
        \\  }
        \\}
    ;
    
    try std.fs.cwd().writeFile(.{ .sub_path = "topology.json", .data = default_topo });
    std.debug.print("[CLI] Created topology.json, ext/, and gen/.\n", .{});
}

fn cmdRun(allocator: std.mem.Allocator, topo_path: []const u8) !void {
    std.debug.print("Initializing Invoke Kernel (Indestructible Mode)...\n", .{});

    // Register Signal Handler
    var sa: c.struct_sigaction = std.mem.zeroes(c.struct_sigaction);
    sa.__sigaction_handler.sa_handler = segfault_handler;
    _ = c.sigaction(c.SIGSEGV, &sa, null);

    var orch = orchestrator.Orchestrator.init(allocator);
    defer orch.deinit();

    var last_topology_mtime: i128 = 0;
    var frame_count: u32 = 0;

    while (true) {
        frame_count += 1;

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
            std.debug.print("\n[Kernel] Hot-swapping GRAPH TOPOLOGY...\n", .{});
            last_topology_mtime = stat.mtime;
            try reloadTopology(allocator, &orch, topo_path);
        }

        if (frame_count % 10 == 0) try orch.poke("on_collision");

        // 2. RESILIENT HEARTBEAT
        is_recovering = true;
        if (c.setjmp(&jump_buffer) == 0) {
            try orch.tick();
        } else {
            std.debug.print("\n[Kernel] RECOVERY (Frame {d}): A Node attempted a memory violation! Motherboard survives.\n", .{frame_count});
        }
        is_recovering = false;
        
        // 3. Monitor
        if (orch.getWire("player.stats")) |w| {
            w.setAccess(std.posix.PROT.READ);
            const ptr: [*]u8 = @ptrCast(w.ptr());
            const x = @as(*f32, @ptrCast(@alignCast(ptr))).*;
            const health_offset: usize = if (std.mem.indexOf(u8, w.schema_str, "z:f32") != null) 12 else 8;
            const health = @as(*i32, @ptrCast(@alignCast(ptr + health_offset))).*;
            std.debug.print("[Monitor] Frame {d} | Player X: {d: >5.2} | HP: {d}\n", .{ frame_count, x, health });
            w.setAccess(std.posix.PROT.NONE);
        }

        std.time.sleep(1 * std.time.ns_per_s);
    }
}

fn reloadTopology(allocator: std.mem.Allocator, orch: *orchestrator.Orchestrator, path: []const u8) !void {
    const file_content = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(file_content);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, file_content, .{});
    defer parsed.deinit();
    const namespaces = parsed.value.object.get("namespaces") orelse return error.NoNamespaces;

    // Phase 1: Wires & Header Synthesis
    var c_headers = std.ArrayList(u8).init(allocator);
    defer c_headers.deinit();
    try c_headers.appendSlice("#ifndef INVOKE_WIRES_H\n#define INVOKE_WIRES_H\n\n#include <stdint.h>\n#include <stdbool.h>\n\n");

    var ns_it = namespaces.object.iterator();
    while (ns_it.next()) |ns_entry| {
        const ns_name = ns_entry.key_ptr.*;
        if (ns_entry.value_ptr.*.object.get("wires")) |wires| {
            var wire_it = wires.object.iterator();
            while (wire_it.next()) |w_entry| {
                const w_name = w_entry.key_ptr.*;
                const w_schema = w_entry.value_ptr.*.string;
                const full_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns_name, w_name });
                defer allocator.free(full_path);
                const w_existed = orch.getWire(full_path) != null;
                const size = schema.CalculateSchemaSize(w_schema);
                const w = try orch.addWire(full_path, w_schema, size);
                
                // Initialize health if it's a NEW player.stats wire
                if (!w_existed and std.mem.eql(u8, full_path, "player.stats")) {
                    w.setAccess(std.posix.PROT.WRITE);
                    const base_ptr: [*]u8 = @ptrCast(w.ptr());
                    // Health is at index 8 for the original schema, index 12 for the evolved one.
                    // We detect based on schema string.
                    const health_offset: usize = if (std.mem.indexOf(u8, w_schema, "z:f32") != null) 12 else 8;
                    const health_ptr: *i32 = @ptrCast(@alignCast(base_ptr + health_offset));
                    health_ptr.* = 100;
                    w.setAccess(std.posix.PROT.NONE);
                }
                
                const struct_def = try schema.generateCStruct(allocator, full_path, w_schema);
                defer allocator.free(struct_def);
                try c_headers.appendSlice(struct_def);
            }
        }
    }
    try c_headers.appendSlice("#endif\n");
    try std.fs.cwd().makePath("gen");
    try std.fs.cwd().writeFile(.{ .sub_path = "gen/wires.h", .data = c_headers.items });

    var lua_headers = std.ArrayList(u8).init(allocator);
    defer lua_headers.deinit();
    try lua_headers.appendSlice("local ffi = require(\"ffi\")\nffi.cdef[[\ntypedef int int32_t;\ntypedef unsigned int uint32_t;\n\n");
    ns_it = namespaces.object.iterator();
    while (ns_it.next()) |ns_entry| {
        const ns_name = ns_entry.key_ptr.*;
        if (ns_entry.value_ptr.*.object.get("wires")) |wires| {
            var wire_it = wires.object.iterator();
            while (wire_it.next()) |w_entry| {
                const w_schema = w_entry.value_ptr.*.string;
                const full_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns_name, w_entry.key_ptr.* });
                defer allocator.free(full_path);
                const struct_def = try schema.generateCStruct(allocator, full_path, w_schema);
                defer allocator.free(struct_def);
                try lua_headers.appendSlice(struct_def);
            }
        }
    }
    try lua_headers.appendSlice("]]\nreturn {}\n");
    try std.fs.cwd().writeFile(.{ .sub_path = "gen_wires.lua", .data = lua_headers.items });
    std.debug.print("[Kernel] Header Synthesis Complete: gen/wires.h, gen_wires.lua\n", .{});

    // Phase 2: Nodes
    ns_it = namespaces.object.iterator();
    while (ns_it.next()) |ns_entry| {
        const ns_name = ns_entry.key_ptr.*;
        if (ns_entry.value_ptr.*.object.get("nodes")) |nodes| {
            for (nodes.array.items) |n_val| {
                const n_obj = n_val.object;
                const n_name = n_obj.get("name").?.string;
                const ext_type = n_obj.get("type").?.string;
                const n_mode_str = n_obj.get("mode").?.string;
                const n_script = n_obj.get("script").?.string;
                const full_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns_name, n_name });
                defer allocator.free(full_path);
                const mode = if (std.mem.eql(u8, n_mode_str, "Poke")) orchestrator.ExecutionMode.Poke else orchestrator.ExecutionMode.Heartbeat;
                const n = try orch.createNode(full_path, ext_type, mode, n_script);
                if (n_obj.get("triggers")) |triggers| {
                    for (triggers.array.items) |t_val| try n.addTrigger(t_val.string);
                }

                var guest_offsets = std.ArrayList(u8).init(allocator);
                defer guest_offsets.deinit();
                try guest_offsets.appendSlice("#ifndef GUEST_OFFSETS_H\n#define GUEST_OFFSETS_H\n\n");
                var current_offset: usize = 0;

                var bound_paths = std.StringHashMap(void).init(allocator);
                defer {
                    var it = bound_paths.keyIterator();
                    while (it.next()) |k| allocator.free(k.*);
                    bound_paths.deinit();
                }

                inline for (.{ "reads", "writes" }) |field| {
                    if (n_obj.get(field)) |wires| {
                        for (wires.array.items) |w_val| {
                            const wire_ref = w_val.string;
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
                                    current_offset += (w.buffer.len + 15) & ~@as(usize, 15);
                                }
                            }
                        }
                    }
                }
                try guest_offsets.appendSlice("\n#endif\n");
                if (std.mem.eql(u8, ext_type, "wasm")) {
                    const offset_filename = try std.fmt.allocPrint(allocator, "gen/{s}_offsets.h", .{n_name});
                    defer allocator.free(offset_filename);
                    try std.fs.cwd().writeFile(.{ .sub_path = offset_filename, .data = guest_offsets.items });
                }
            }
        }
    }
}
