const std = @import("std");
const node = @import("node.zig");
const wire = @import("wire.zig");
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
    ext_manager: extension.ExtensionManager,
    pokes: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) Orchestrator {
        return .{
            .allocator = allocator,
            .wires = std.StringHashMap(*wire.RawWire).init(allocator),
            .nodes = std.StringHashMap(node.Node).init(allocator),
            .ext_manager = extension.ExtensionManager.init(allocator),
            .pokes = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Orchestrator) void {
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
    }

    pub fn createNode(self: *Orchestrator, path: []const u8, ext_type: []const u8, mode: ExecutionMode, script_path: []const u8) !*node.Node {
        const ext = try self.ext_manager.getOrLoad(ext_type);
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);
        const script_z = try self.allocator.dupeZ(u8, script_path);
        defer self.allocator.free(script_z);

        const handle = ext.vtable.create_node.?(path_z.ptr, script_z.ptr);
        const n = try node.Node.init(self.allocator, path, mode, script_path, ext.vtable, handle);

        if (self.nodes.getPtr(path)) |existing| {
            existing.deinit();
            existing.* = n;
            return existing;
        }

        try self.nodes.put(try self.allocator.dupe(u8, path), n);
        return self.nodes.getPtr(path).?;
    }

    pub fn addWire(self: *Orchestrator, path: []const u8, size: usize) !*wire.RawWire {
        if (self.wires.get(path)) |existing| return existing;
        const w = try wire.RawWire.init(self.allocator, path, size);
        try self.wires.put(try self.allocator.dupe(u8, path), w);
        std.debug.print("[Orchestrator] Registered Wire: {s} ({d} bytes)\n", .{ path, size });
        return w;
    }

    pub fn poke(self: *Orchestrator, event: []const u8) !void {
        try self.pokes.append(try self.allocator.dupe(u8, event));
    }

    pub fn tick(self: *Orchestrator) !void {
        var node_it = self.nodes.valueIterator();
        while (node_it.next()) |n| {
            if (n.mode == .Heartbeat) try self.executeNode(n);
        }

        while (self.pokes.items.len > 0) {
            const event = self.pokes.orderedRemove(0);
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

    /// The 'Silicon Gating' wrapper. 
    /// Temporarily unlocks hardware-protected memory wires before execution.
    fn executeNode(self: *Orchestrator, n: *node.Node) !void {
        _ = self;
        // 1. UNLOCK WIRES
        // For simplicity in this demo, we unlock everything bound to the node.
        // In a strict build, we'd use PROT_READ for 'reads' and PROT_READ|PROT_WRITE for 'writes'.
        var it = n.bound_wires.valueIterator();
        while (it.next()) |w| {
            w.*.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
        }

        // 2. EXECUTE
        n.execute() catch |err| {
            std.debug.print("[Orchestrator] Node {s} failed: {any}\n", .{ n.name, err });
        };

        // 3. LOCK WIRES (Protect the Motherboard)
        it = n.bound_wires.valueIterator();
        while (it.next()) |w| {
            w.*.setAccess(std.posix.PROT.NONE);
        }
    }

    pub fn getWire(self: *Orchestrator, path: []const u8) ?*wire.RawWire {
        return self.wires.get(path);
    }
};
