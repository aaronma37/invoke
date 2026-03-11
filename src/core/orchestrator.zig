const std = @import("std");
pub const node = @import("node.zig");
pub const wire = @import("wire.zig");
pub const sandbox = @import("sandbox.zig");
const extension = @import("extension.zig");

pub const ExecutionMode = enum {
    Heartbeat,
    Poke,
};

pub const Orchestrator = struct {
    allocator: std.mem.Allocator,
    nodes: std.StringHashMap(*node.Node),
    wires: std.StringHashMap(*wire.RawWire),
    extensions: extension.ExtensionManager,
    levels: std.ArrayList(std.ArrayList(*node.Node)),
    
    pokes: std.ArrayList([]const u8),
    pokes_mutex: std.Thread.Mutex,
    nodes_mutex: std.Thread.Mutex,
    
    watchdog_thread: ?std.Thread = null,
    watchdog_active: bool = false,

    pub fn init(self: *Orchestrator, allocator: std.mem.Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .nodes = std.StringHashMap(*node.Node).init(allocator),
            .wires = std.StringHashMap(*wire.RawWire).init(allocator),
            .extensions = extension.ExtensionManager.init(allocator),
            .levels = std.ArrayList(std.ArrayList(*node.Node)).init(allocator),
            .pokes = std.ArrayList([]const u8).init(allocator),
            .pokes_mutex = .{},
            .nodes_mutex = .{},
        };
        
        self.watchdog_active = true;
        self.watchdog_thread = try std.Thread.spawn(.{}, watchdogLoop, .{self});
    }

    pub fn deinit(self: *Orchestrator) void {
        self.watchdog_active = false;
        if (self.watchdog_thread) |t| t.join();

        var nit = self.nodes.iterator();
        while (nit.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.nodes.deinit();

        var wit = self.wires.iterator();
        while (wit.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.wires.deinit();
        
        for (self.levels.items) |level| level.deinit();
        self.levels.deinit();
        
        self.extensions.deinit();
        
        for (self.pokes.items) |p| self.allocator.free(p);
        self.pokes.deinit();
    }

    pub fn addWire(self: *Orchestrator, path: []const u8, schema_str: []const u8, size: usize, buffered: bool) !*wire.RawWire {
        if (self.wires.get(path)) |w| return w;

        const w = try wire.RawWire.init(self.allocator, path, schema_str, size, buffered);
        try self.wires.put(try self.allocator.dupe(u8, path), w);
        
        std.debug.print("[Orchestrator] Registered Wire: {s} ({d} bytes, Buffered: {any})\n", .{ path, size, buffered });
        return w;
    }

    pub fn createNode(self: *Orchestrator, path: []const u8, ext_type: []const u8, mode: ExecutionMode, script: []const u8) !*node.Node {
        if (self.nodes.get(path)) |n| return n;

        const ext = try self.extensions.getOrLoad(ext_type);
        const handle = ext.vtable.create_node.?(path.ptr, script.ptr);
        
        const n = try self.allocator.create(node.Node);
        n.* = try node.Node.init(self.allocator, path, mode, script, ext.vtable, handle);
        try self.nodes.put(try self.allocator.dupe(u8, path), n);
        return n;
    }

    pub fn rebuildTaskGraph(self: *Orchestrator) !void {
        for (self.levels.items) |level| level.deinit();
        self.levels.clearRetainingCapacity();

        var remaining = std.ArrayList(*node.Node).init(self.allocator);
        defer remaining.deinit();
        
        var it = self.nodes.valueIterator();
        while (it.next()) |n| {
            if (n.*.mode == .Heartbeat) try remaining.append(n.*);
        }

        while (remaining.items.len > 0) {
            var current_level = std.ArrayList(*node.Node).init(self.allocator);
            var i: usize = 0;
            while (i < remaining.items.len) {
                const n = remaining.items[i];
                var conflict = false;
                for (current_level.items) |other| {
                    if (nodesCollide(n, other)) {
                        conflict = true;
                        break;
                    }
                }

                if (!conflict) {
                    try current_level.append(n);
                    _ = remaining.swapRemove(i);
                } else {
                    i += 1;
                }
            }
            try self.levels.append(current_level);
        }
        
        std.debug.print("[Orchestrator] Task Graph: {d} parallel levels.\n", .{ self.levels.items.len });
    }

    fn nodesCollide(a: *node.Node, b: *node.Node) bool {
        var a_it = a.bound_wires.valueIterator();
        while (a_it.next()) |a_b| {
            if (a_b.wire.is_buffered) continue;
            if (a_b.access & 2 != 0) { // A writes
                var b_it = b.bound_wires.valueIterator();
                while (b_it.next()) |b_b| {
                    if (b_b.wire == a_b.wire) return true; // B uses same wire
                }
            } else { // A reads
                var b_it = b.bound_wires.valueIterator();
                while (b_it.next()) |b_b| {
                    if (b_b.wire == a_b.wire and b_b.access & 2 != 0) return true; // B writes same wire
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

    pub fn swapAllWires(self: *Orchestrator) void {
        var it = self.wires.valueIterator();
        while (it.next()) |w| w.*.swap();
    }

    pub fn tick(self: *Orchestrator) !void {
        // HEARTBEAT NODES
        for (self.levels.items) |level| {
            // 1. Level-wide Memory Grant
            for (level.items) |n| {
                if (n.is_jailed) continue;
                var it = n.bound_wires.iterator();
                while (it.next()) |entry| {
                    const binding = entry.value_ptr;
                    const w = binding.wire;
                    const is_write = (binding.access & 2 != 0);
                    const bank_idx: usize = if (w.is_buffered and is_write) 1 - w.front_index else w.front_index;
                    w.setBankAccess(bank_idx, binding.access);
                    
                    // Also bind for extensions
                    const name_z = try n.allocator.dupeZ(u8, entry.key_ptr.*);
                    defer n.allocator.free(name_z);
                    const ptr = if (w.is_buffered and is_write) w.backPtr() else w.frontPtr();
                    _ = n.vtable.bind_wire.?(n.handle, name_z.ptr, ptr, binding.access);
                }
            }

            var threads = try std.ArrayList(std.Thread).initCapacity(self.allocator, level.items.len);
            defer threads.deinit();

            for (level.items) |n| {
                if (std.mem.indexOf(u8, n.name, "visualizer") != null) continue;
                try threads.append(try std.Thread.spawn(.{}, parallelWorker, .{n}));
            }

            // Run Main-Thread nodes LOCALLY while workers are busy
            for (level.items) |n| {
                if (std.mem.indexOf(u8, n.name, "visualizer") != null) {
                    n.execute() catch |err| {
                        std.debug.print("[Orchestrator] Node {s} failed: {any}\n", .{ n.name, err });
                    };
                }
            }

            // BARRIER: Wait for level to complete
            for (threads.items) |t| t.join();

            // 2. Level-wide Memory Revoke
            for (level.items) |n| {
                var it = n.bound_wires.valueIterator();
                while (it.next()) |binding| {
                    const w = binding.wire;
                    const is_write = (binding.access & 2 != 0);
                    const bank_idx: usize = if (w.is_buffered and is_write) 1 - w.front_index else w.front_index;
                    w.setBankAccess(bank_idx, std.posix.PROT.NONE);
                }
            }
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
                if (n.*.mode == .Poke) {
                    for (n.*.triggers.items) |trigger| {
                        if (std.mem.eql(u8, trigger, event)) try self.executeNode(n.*);
                    }
                }
            }
        }
    }

    fn parallelWorker(n: *node.Node) void {
        if (n.is_jailed) return;

        // TRACK START
        n.running_thread.store(std.Thread.getCurrentId(), .monotonic);
        n.start_time.store(std.time.milliTimestamp(), .monotonic);
        n.is_running.store(true, .release);

        sandbox.is_recovering = true;
        const code = sandbox.c.setjmp(&sandbox.jump_buffer);
        if (code == 0) {
            n.execute() catch |err| {
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
                if (n.*.is_running.load(.acquire)) {
                    const elapsed = std.time.milliTimestamp() - n.*.start_time.load(.monotonic);
                    if (elapsed > timeout_ms) {
                        const thread_id = n.*.running_thread.load(.monotonic);
                        std.debug.print("[Watchdog] Node {s} EXCEEDED budget ({d}ms). Terminating thread {d}...\n", .{ n.*.name, elapsed, thread_id });
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
