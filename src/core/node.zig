const std = @import("std");
const wire = @import("wire.zig");
const orchestrator = @import("orchestrator.zig");

// Import the stable ABI
pub const abi = @cImport({
    @cInclude("moontide.h");
});

pub const WireBinding = struct {
    wire: *wire.RawWire,
    access: u32,
};

/// A Node is now a generic 'Socket'. 
/// it doesn't know about Lua or WASM; it only knows about the Handshake.
pub const Node = struct {
    name: []const u8,
    ext_type: []const u8,
    mode: orchestrator.ExecutionMode,
    script_path: []const u8,
    allocator: std.mem.Allocator,
    
    // The Opaque Handshake
    handle: abi.moontide_node_h,
    vtable: abi.moontide_extension_t,
    
    // Metadata
    triggers: std.ArrayList([]const u8),
    after: std.ArrayList([]const u8),
    bound_wires: std.StringHashMap(WireBinding),
    last_mtime: i128 = 0,
    
    // FAULT TOLERANCE
    strike_count: u32 = 0,
    is_jailed: bool = false,
    
    // WATCHDOG
    is_running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    start_time: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),
    running_thread: std.atomic.Value(std.Thread.Id) = std.atomic.Value(std.Thread.Id).init(0),

    pub fn init(
        allocator: std.mem.Allocator, 
        name: []const u8, 
        ext_type: []const u8,
        mode: orchestrator.ExecutionMode, 
        script_path: []const u8,
        vtable: abi.moontide_extension_t,
        handle: abi.moontide_node_h
    ) !Node {
        return Node{
            .name = try allocator.dupe(u8, name),
            .ext_type = try allocator.dupe(u8, ext_type),
            .mode = mode,
            .script_path = try allocator.dupe(u8, script_path),
            .allocator = allocator,
            .vtable = vtable,
            .handle = handle,
            .triggers = std.ArrayList([]const u8).init(allocator),
            .after = std.ArrayList([]const u8).init(allocator),
            .bound_wires = std.StringHashMap(WireBinding).init(allocator),
        };
    }

    pub fn deinit(self: *Node) void {
        self.vtable.destroy_node.?(self.handle);
        self.allocator.free(self.name);
        self.allocator.free(self.ext_type);
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

        for (self.after.items) |t| {
            self.allocator.free(t);
        }
        self.after.deinit();
    }

    pub fn addTrigger(self: *Node, event: []const u8) !void {
        try self.triggers.append(try self.allocator.dupe(u8, event));
        const event_z = try self.allocator.dupeZ(u8, event);
        defer self.allocator.free(event_z);
        _ = self.vtable.add_trigger.?(self.handle, event_z.ptr);
    }

    pub fn bindWire(self: *Node, wire_name: []const u8, w: *wire.RawWire, access: u32) void {
        // Track binding for Silicon Gating (mprotect)
        if (self.bound_wires.getPtr(wire_name)) |existing| {
            existing.wire = w;
            existing.access |= access;
        } else {
            self.bound_wires.put(self.allocator.dupe(u8, wire_name) catch return, .{
                .wire = w,
                .access = access,
            }) catch return;
        }

        self.refreshBindings();
    }

    pub fn refreshBindings(self: *Node) void {
        var it = self.bound_wires.iterator();
        while (it.next()) |entry| {
            const wire_name = entry.key_ptr.*;
            const binding = entry.value_ptr;
            const w = binding.wire;
            
            const name_z = self.allocator.dupeZ(u8, wire_name) catch continue;
            defer self.allocator.free(name_z);

            const is_write = (binding.access & 2 != 0);
            const ptr = if (w.is_buffered and is_write) w.banks[1 - w.front_index].ptr else w.banks[w.front_index].ptr;
            
            _ = self.vtable.bind_wire.?(self.handle, name_z.ptr, ptr, binding.access);
        }
    }

    pub fn execute(self: *Node) !void {
        if (self.is_jailed) return;

        // 1. Hardware Watcher: Check if we need to hot-reload logic
        if (!std.mem.eql(u8, self.script_path, "none")) {
            const file = std.fs.cwd().openFile(self.script_path, .{}) catch |err| {
                if (err == error.FileNotFound) return;
                return err;
            };
            const stat = try file.stat();
            file.close();

            if (stat.mtime > self.last_mtime) {
                std.debug.print("[Node {s}] Hot-reloading script: {s}\n", .{ self.name, self.script_path });
                self.last_mtime = stat.mtime;
                
                // RESET FAULTS ON FIX
                self.strike_count = 0;
                self.is_jailed = false;

                const path_z = try self.allocator.dupeZ(u8, self.script_path);
                defer self.allocator.free(path_z);
                _ = self.vtable.reload_node.?(self.handle, path_z.ptr);
            }
        }

        // 2. Refresh pointers (Bank Swap recovery)
        self.refreshBindings();

        // 3. Perform the Tick
        _ = self.vtable.tick.?(self.handle);
    }
};
