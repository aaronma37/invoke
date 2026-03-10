const std = @import("std");
const wire = @import("wire.zig");
const orchestrator = @import("orchestrator.zig");

// Import the stable ABI
pub const abi = @cImport({
    @cInclude("invoke_abi.h");
});

/// A Node is now a generic 'Socket'. 
/// it doesn't know about Lua or WASM; it only knows about the Handshake.
pub const Node = struct {
    name: []const u8,
    mode: orchestrator.ExecutionMode,
    script_path: []const u8,
    allocator: std.mem.Allocator,
    
    // The Opaque Handshake
    handle: abi.invoke_node_h,
    vtable: abi.invoke_extension_t,
    
    // Metadata
    triggers: std.ArrayList([]const u8),
    bound_wires: std.StringHashMap(*wire.RawWire),
    last_mtime: i128 = 0,

    pub fn init(
        allocator: std.mem.Allocator, 
        name: []const u8, 
        mode: orchestrator.ExecutionMode, 
        script_path: []const u8,
        vtable: abi.invoke_extension_t,
        handle: abi.invoke_node_h
    ) !Node {
        return Node{
            .name = try allocator.dupe(u8, name),
            .mode = mode,
            .script_path = try allocator.dupe(u8, script_path),
            .allocator = allocator,
            .vtable = vtable,
            .handle = handle,
            .triggers = std.ArrayList([]const u8).init(allocator),
            .bound_wires = std.StringHashMap(*wire.RawWire).init(allocator),
        };
    }

    pub fn deinit(self: *Node) void {
        self.vtable.destroy_node.?(self.handle);
        self.allocator.free(self.name);
        self.allocator.free(self.script_path);
        
        var it = self.bound_wires.keyIterator();
        while (it.next()) |k| {
            self.allocator.free(k.*);
        }
        self.bound_wires.deinit();

        for (self.triggers.items) |t| {
            self.allocator.free(t);
        }
        self.triggers.deinit();
    }

    pub fn addTrigger(self: *Node, event: []const u8) !void {
        try self.triggers.append(try self.allocator.dupe(u8, event));
        const event_z = try self.allocator.dupeZ(u8, event);
        defer self.allocator.free(event_z);
        _ = self.vtable.add_trigger.?(self.handle, event_z.ptr);
    }

    pub fn bindWire(self: *Node, wire_name: []const u8, w: *wire.RawWire) void {
        const name_z = self.allocator.dupeZ(u8, wire_name) catch return;
        defer self.allocator.free(name_z);
        
        _ = self.vtable.bind_wire.?(self.handle, name_z.ptr, w.ptr(), w.buffer.len);
        
        // Track binding for Silicon Gating
        self.bound_wires.put(self.allocator.dupe(u8, wire_name) catch return, w) catch return;

        std.debug.print("[Node {s}] Wire bound via ABI: {s}\n", .{ self.name, wire_name });
    }

    pub fn execute(self: *Node) !void {
        // 1. Hardware Watcher: Check if we need to hot-reload logic
        const file = std.fs.cwd().openFile(self.script_path, .{}) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        const stat = try file.stat();
        file.close();

        if (stat.mtime > self.last_mtime) {
            std.debug.print("[Node {s}] Hot-reloading script: {s}\n", .{ self.name, self.script_path });
            self.last_mtime = stat.mtime;
            const path_z = try self.allocator.dupeZ(u8, self.script_path);
            defer self.allocator.free(path_z);
            _ = self.vtable.reload_node.?(self.handle, path_z.ptr);
        }

        // 2. Perform the Tick
        _ = self.vtable.tick.?(self.handle);
    }
};
