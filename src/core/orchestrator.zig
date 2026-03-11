const std = @import("std");
pub const node = @import("node.zig");
pub const wire = @import("wire.zig");
pub const sandbox = @import("sandbox.zig");
const extension = @import("extension.zig");

pub const ExecutionMode = enum {
    Heartbeat,
    Poke,
};

/// The Orchestrator manages the 'Namespaced Topology', 'Poke' Event Bus, and Extensions.
pub const Orchestrator = struct {
    allocator: std.mem.Allocator,
    wires: std.StringHashMap(*wire.RawWire),
    nodes: std.StringHashMap(node.Node),
    nodes_mutex: std.Thread.Mutex = .{},
    ext_manager: extension.ExtensionManager,
    pokes: std.ArrayList([]const u8),
    pokes_mutex: std.Thread.Mutex = .{},
    
    // THE TASK GRAPH
    levels: std.ArrayList(std.ArrayList(*node.Node)),
    
    // WATCHDOG
    watchdog_thread: ?std.Thread = null,
    watchdog_active: bool = true,

    pub fn init(self: *Orchestrator, allocator: std.mem.Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .wires = std.StringHashMap(*wire.RawWire).init(allocator),
            .nodes = std.StringHashMap(node.Node).init(allocator),
            .ext_manager = extension.ExtensionManager.init(allocator),
            .pokes = std.ArrayList([]const u8).init(allocator),
            .levels = std.ArrayList(std.ArrayList(*node.Node)).init(allocator),
        };
        
        // Start Watchdog
        self.watchdog_thread = try std.Thread.spawn(.{}, watchdogLoop, .{self});
    }

    pub fn deinit(self: *Orchestrator) void {
        self.watchdog_active = false;
        if (self.watchdog_thread) |t| t.join();

        var wire_it = self.wires.iterator();
        while (wire_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
        }
        
        var node_it = self.nodes.iterator();
        while (node_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
        }
        
        for (self.pokes.items) |p| self.allocator.free(p);
        self.pokes.deinit();
        self.ext_manager.deinit();
        self.wires.deinit();
        self.nodes.deinit();

        self.clearLevels();
        self.levels.deinit();
    }

    pub fn createNode(self: *Orchestrator, path: []const u8, ext_type: []const u8, mode: ExecutionMode, script_path: []const u8) !*node.Node {
        const ext = try self.ext_manager.getOrLoad(ext_type);
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);
        const script_z = try self.allocator.dupeZ(u8, script_path);
        defer self.allocator.free(script_z);

        const handle = ext.vtable.create_node.?(path_z.ptr, script_z.ptr) orelse return error.NodeCreationFailed;
        
        const n = try node.Node.init(self.allocator, path, mode, script_path, ext.vtable, handle);
        
        self.nodes_mutex.lock();
        defer self.nodes_mutex.unlock();
        try self.nodes.put(try self.allocator.dupe(u8, path), n);
        return self.nodes.getPtr(path).?;
    }

    pub fn addWire(self: *Orchestrator, path: []const u8, schema_str: []const u8, size: usize, buffered: bool) !*wire.RawWire {
        if (self.wires.get(path)) |existing| {
            if (std.mem.eql(u8, existing.schema_str, schema_str)) return existing;

            // SCHEMA EVOLUTION: Migrate data!
            std.debug.print("[Orchestrator] Schema changed for {s}! Migrating data...\n", .{path});
            const new_wire = try wire.RawWire.init(self.allocator, path, schema_str, size, buffered);
            
            try self.migrateData(existing, new_wire);

            _ = self.wires.remove(path);
            existing.deinit();
            try self.wires.put(try self.allocator.dupe(u8, path), new_wire);
            return new_wire;
        }

        const w = try wire.RawWire.init(self.allocator, path, schema_str, size, buffered);
        try self.wires.put(try self.allocator.dupe(u8, path), w);
        std.debug.print("[Orchestrator] Registered Wire: {s} ({d} bytes, Buffered: {any})\n", .{ path, size, buffered });
        return w;
    }

    pub fn swapAllWires(self: *Orchestrator) void {
        var it = self.wires.valueIterator();
        while (it.next()) |w| {
            w.*.swap();
        }
    }

    fn migrateData(self: *Orchestrator, old: *wire.RawWire, new: *wire.RawWire) !void {
        _ = self;
        const schema = @import("schema.zig");
        
        old.setAccess(std.posix.PROT.READ);
        new.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
        defer {
            old.setAccess(std.posix.PROT.NONE);
            new.setAccess(std.posix.PROT.NONE);
        }

        var new_it = std.mem.tokenizeAny(u8, new.schema_str, ";");
        var new_offset: usize = 0;
        while (new_it.next()) |new_entry| {
            var new_parts = std.mem.tokenizeAny(u8, new_entry, ":");
            const name = new_parts.next() orelse continue;
            const type_str = new_parts.next() orelse continue;
            const size = schema.GetTypeSize(type_str);

            var old_it = std.mem.tokenizeAny(u8, old.schema_str, ";");
            var old_offset: usize = 0;
            var found = false;
            while (old_it.next()) |old_entry| {
                var old_parts = std.mem.tokenizeAny(u8, old_entry, ":");
                const old_name = old_parts.next() orelse continue;
                const old_type = old_parts.next() orelse continue;
                const old_size = schema.GetTypeSize(old_type);

                if (std.mem.eql(u8, name, old_name)) {
                    const copy_size = @min(size, old_size);
                    const old_ptr: [*]u8 = @ptrCast(old.ptr());
                    const new_ptr: [*]u8 = @ptrCast(new.ptr());
                    @memcpy(new_ptr[new_offset .. new_offset + copy_size], old_ptr[old_offset .. old_offset + copy_size]);
                    found = true;
                    break;
                }
                old_offset += old_size;
            }
            new_offset += size;
        }
    }

    fn clearLevels(self: *Orchestrator) void {
        for (self.levels.items) |level| level.deinit();
        self.levels.clearRetainingCapacity();
    }

    pub fn rebuildTaskGraph(self: *Orchestrator) !void {
        self.clearLevels();
        
        self.nodes_mutex.lock();
        defer self.nodes_mutex.unlock();

        var remaining_nodes = std.ArrayList(*node.Node).init(self.allocator);
        defer remaining_nodes.deinit();
        var it = self.nodes.valueIterator();
        while (it.next()) |n| if (n.mode == .Heartbeat) try remaining_nodes.append(n);

        while (remaining_nodes.items.len > 0) {
            var current_level = std.ArrayList(*node.Node).init(self.allocator);
            var i: usize = 0;
            var changed = false;
            while (i < remaining_nodes.items.len) {
                const n = remaining_nodes.items[i];
                var depends = false;
                for (remaining_nodes.items) |other| {
                    if (n == other) continue;
                    if (self.dependsOn(n, other)) { depends = true; break; }
                }
                if (!depends) {
                    try current_level.append(n);
                    _ = remaining_nodes.swapRemove(i);
                    changed = true;
                } else i += 1;
            }
            if (!changed) break;
            try self.levels.append(current_level);
        }
        std.debug.print("[Orchestrator] Task Graph: {d} parallel levels.\n", .{self.levels.items.len});
    }

    fn dependsOn(self: *Orchestrator, a: *node.Node, b: *node.Node) bool {
        _ = self;
        if (a == b) return false;
        var a_it = a.bound_wires.valueIterator();
        while (a_it.next()) |a_b| {
            if (a_b.wire.is_buffered) continue;
            if (a_b.access & 1 != 0) {
                var b_it = b.bound_wires.valueIterator();
                while (b_it.next()) |b_b| {
                    if (b_b.wire == a_b.wire and b_b.access & 2 != 0) return true;
                }
            }
        }
        return false;
    }

    pub fn poke(self: *Orchestrator, event: []const u8) !void {
        self.pokes_mutex.lock();
        defer self.pokes_mutex.unlock();
        try self.pokes.append(try self.allocator.dupe(u8, event));
    }

    pub fn tick(self: *Orchestrator) !void {
        // HEARTBEAT NODES
        for (self.levels.items) |level| {
            var threads = try std.ArrayList(std.Thread).initCapacity(self.allocator, level.items.len);
            defer threads.deinit();

            for (level.items) |n| {
                if (std.mem.indexOf(u8, n.name, "visualizer") != null) continue;
                try threads.append(try std.Thread.spawn(.{}, parallelWorker, .{ self, n }));
            }

            // Run Main-Thread nodes LOCALLY while workers are busy
            for (level.items) |n| {
                if (std.mem.indexOf(u8, n.name, "visualizer") != null) {
                    try self.executeNode(n);
                }
            }

            // BARRIER: Wait for level to complete
            for (threads.items) |t| t.join();
        }

        // POKE NODES
        while (true) {
            self.pokes_mutex.lock();
            if (self.pokes.items.len == 0) {
                self.pokes_mutex.unlock();
                break;
            }
            const event = self.pokes.orderedRemove(0);
            self.pokes_mutex.unlock();
            
            defer self.allocator.free(event);
            var it = self.nodes.valueIterator();
            while (it.next()) |n| {
                if (n.mode == .Poke) {
                    for (n.triggers.items) |trigger| {
                        if (std.mem.eql(u8, trigger, event)) try self.executeNode(n);
                    }
                }
            }
        }
    }

    fn parallelWorker(self: *Orchestrator, n: *node.Node) void {
        if (n.is_jailed) return;

        // TRACK START
        n.running_thread.store(std.Thread.getCurrentId(), .monotonic);
        n.start_time.store(std.time.milliTimestamp(), .monotonic);
        n.is_running.store(true, .release);

        sandbox.is_recovering = true;
        const code = sandbox.c.setjmp(&sandbox.jump_buffer);
        if (code == 0) {
            self.executeNode(n) catch |err| {
                std.debug.print("[Parallel] Node {s} failed: {any}\n", .{ n.name, err });
            };
        } else {
            // CRITICAL: DO NOT ALLOCATE OR FREE HERE.
            n.strike_count += 1;
            if (n.strike_count >= 3) n.is_jailed = true;
            std.debug.print("[Parallel] RECOVERY for {s}.\n", .{ n.name });
        }
        
        // TRACK END
        n.is_running.store(false, .release);
        sandbox.is_recovering = false;
    }

    fn watchdogLoop(self: *Orchestrator) void {
        const timeout_ms: i64 = 100; // 100ms budget

        while (self.watchdog_active) {
            std.time.sleep(20 * std.time.ns_per_ms);
            
            self.nodes_mutex.lock();
            var it = self.nodes.valueIterator();
            while (it.next()) |n| {
                if (n.is_running.load(.acquire)) {
                    const elapsed = std.time.milliTimestamp() - n.start_time.load(.monotonic);
                    if (elapsed > timeout_ms) {
                        const thread_id = n.running_thread.load(.monotonic);
                        std.debug.print("[Watchdog] Node {s} EXCEEDED budget ({d}ms). Terminating thread {d}...\n", .{ n.name, elapsed, thread_id });
                        _ = std.os.linux.tkill(@intCast(thread_id), std.posix.SIG.USR1);
                    }
                }
            }
            self.nodes_mutex.unlock();
        }
    }

    fn executeNode(self: *Orchestrator, n: *node.Node) !void {
        _ = self;
        if (n.is_jailed) return;

        var it = n.bound_wires.iterator();
        while (it.next()) |entry| {
            const binding = entry.value_ptr;
            const w = binding.wire;
            const is_write = (binding.access & 2 != 0);
            const bank_idx: usize = if (w.is_buffered and is_write) 1 - w.front_index else w.front_index;
            const ptr = if (w.is_buffered and is_write) w.backPtr() else w.frontPtr();
            
            const name_z = try n.allocator.dupeZ(u8, entry.key_ptr.*);
            defer n.allocator.free(name_z);
            _ = n.vtable.bind_wire.?(n.handle, name_z.ptr, ptr, binding.access);
            w.setBankAccess(bank_idx, binding.access);
        }

        n.execute() catch |err| {
            std.debug.print("[Orchestrator] Node {s} failed: {any}\n", .{ n.name, err });
        };

        it = n.bound_wires.iterator();
        while (it.next()) |entry| {
            const binding = entry.value_ptr;
            const w = binding.wire;
            const is_write = (binding.access & 2 != 0);
            const bank_idx: usize = if (w.is_buffered and is_write) 1 - w.front_index else w.front_index;
            w.setBankAccess(bank_idx, std.posix.PROT.NONE);
        }
    }

    pub fn getWire(self: *Orchestrator, path: []const u8) ?*wire.RawWire {
        return self.wires.get(path);
    }
};
