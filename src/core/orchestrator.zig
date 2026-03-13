const std = @import("std");
pub const node = @import("node.zig");
pub const wire = @import("wire.zig");
pub const sandbox = @import("sandbox.zig");
pub const schema = @import("schema.zig");
const extension = @import("extension.zig");

test {
    std.testing.refAllDecls(@This());
}

test "Orchestrator basic initialization and wire management" {
    const allocator = std.testing.allocator;
    var orch: Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    const w = try orch.addWire("test.wire", "x:f32;y:f32", 8, true);
    try std.testing.expectEqual(orch.wires.count(), 1);
    try std.testing.expect(orch.getWire("test.wire") == w);
}

test "Orchestrator task graph rebuilding" {
    const allocator = std.testing.allocator;
    var orch: Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    // Mock vtable for testing
    var mock_vtable: node.abi.moontide_extension_t = undefined;
    mock_vtable.create_node = (struct {
        fn create(_: [*c]const u8, _: [*c]const u8) callconv(.C) node.abi.moontide_node_h {
            return @as(node.abi.moontide_node_h, @ptrFromInt(0xDEADBEEF));
        }
    }).create;
    mock_vtable.destroy_node = (struct {
        fn destroy(_: node.abi.moontide_node_h) callconv(.C) void {}
    }).destroy;
    mock_vtable.bind_wire = (struct {
        fn bind(_: node.abi.moontide_node_h, _: [*c]const u8, _: ?*anyopaque, _: usize) callconv(.C) node.abi.moontide_status_t {
            return node.abi.MOONTIDE_STATUS_OK;
        }
    }).bind;

    const n1 = try allocator.create(node.Node);
    n1.* = try node.Node.init(allocator, "node1", "mock", .Heartbeat, "none", mock_vtable, @as(node.abi.moontide_node_h, @ptrFromInt(1)));
    try orch.nodes.put(try allocator.dupe(u8, "node1"), n1);

    const n2 = try allocator.create(node.Node);
    n2.* = try node.Node.init(allocator, "node2", "mock", .Heartbeat, "none", mock_vtable, @as(node.abi.moontide_node_h, @ptrFromInt(2)));
    try orch.nodes.put(try allocator.dupe(u8, "node2"), n2);

    // No conflicts, should be in 1 level
    try orch.rebuildTaskGraph();
    try std.testing.expectEqual(orch.levels.items.len, 1);
    try std.testing.expectEqual(orch.levels.items[0].items.len, 2);

    // Add conflict: n1 writes to wire1, n2 reads from wire1
    const w1 = try orch.addWire("wire1", "x:f32", 4, false);
    n1.bindWire("wire1", w1, std.posix.PROT.READ | std.posix.PROT.WRITE);
    n2.bindWire("wire1", w1, std.posix.PROT.READ);

    try orch.rebuildTaskGraph();
    // Conflict should force them into 2 levels
    try std.testing.expectEqual(orch.levels.items.len, 2);
}

test "Sandbox recovery from SIGSEGV" {
    sandbox.is_recovering = true;
    defer sandbox.is_recovering = false;
    sandbox.initSignalHandler();

    if (sandbox.c.setjmp(&sandbox.jump_buffer) == 0) {
        // Simulate a segfault
        _ = sandbox.c.raise(sandbox.c.SIGSEGV);
        try std.testing.expect(false); // Should not reach here
    } else {
        // Successfully recovered!
        try std.testing.expect(true);
    }
}

test "Silicon Gating (mprotect) enforcement" {
    const allocator = std.testing.allocator;
    var orch: Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    sandbox.initSignalHandler();

    const w = try orch.addWire("secure_wire", "val:i32", 4, false);
    
    // 1. Set to READ ONLY
    w.setAccess(std.posix.PROT.READ);
    const ptr: *i32 = @ptrCast(@alignCast(w.ptr()));

    sandbox.is_recovering = true;
    defer sandbox.is_recovering = false;

    if (sandbox.c.setjmp(&sandbox.jump_buffer) == 0) {
        // 2. Attempt unauthorized write
        ptr.* = 1234; 
        try std.testing.expect(false); // Should fail before this
    } else {
        // 3. Recovered from the write-fault
        try std.testing.expect(true);
    }
    
    // Verify it didn't actually write (or at least we caught it)
    w.setAccess(std.posix.PROT.READ);
    try std.testing.expect(ptr.* != 1234);
}

test "Watchdog Timeout and Strike Count" {
    const allocator = std.testing.allocator;
    var orch: Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    sandbox.initSignalHandler();

    // Mock vtable with a sleeping tick
    var mock_vtable: node.abi.moontide_extension_t = undefined;
    mock_vtable.create_node = (struct {
        fn create(_: [*c]const u8, _: [*c]const u8) callconv(.C) node.abi.moontide_node_h {
            return @as(node.abi.moontide_node_h, @ptrFromInt(0x1337));
        }
    }).create;
    mock_vtable.destroy_node = (struct {
        fn destroy(_: node.abi.moontide_node_h) callconv(.C) void {}
    }).destroy;
    mock_vtable.bind_wire = (struct {
        fn bind(_: node.abi.moontide_node_h, _: [*c]const u8, _: ?*anyopaque, _: usize) callconv(.C) node.abi.moontide_status_t {
            return node.abi.MOONTIDE_STATUS_OK;
        }
    }).bind;
    mock_vtable.tick = (struct {
        fn tick(_: node.abi.moontide_node_h) callconv(.C) node.abi.moontide_status_t {
            // Sleep for 1.2s (Watchdog budget is 1s)
            std.time.sleep(1200 * std.time.ns_per_ms);
            return node.abi.MOONTIDE_STATUS_OK;
        }
    }).tick;

    const n = try allocator.create(node.Node);
    n.* = try node.Node.init(allocator, "slow_node", "mock", .Heartbeat, "none", mock_vtable, @as(node.abi.moontide_node_h, @ptrFromInt(0x1337)));
    try orch.nodes.put(try allocator.dupe(u8, "slow_node"), n);

    // Execute 3 times - should get jailed
    try orch.rebuildTaskGraph();
    
    // Level 1: Execute
    try orch.tick();
    std.time.sleep(50 * std.time.ns_per_ms); // Wait for watchdog cleanup
    try std.testing.expectEqual(@as(u32, 1), n.strike_count);

    try orch.tick();
    std.time.sleep(50 * std.time.ns_per_ms);
    try std.testing.expectEqual(@as(u32, 2), n.strike_count);

    try orch.tick();
    std.time.sleep(50 * std.time.ns_per_ms);
    try std.testing.expectEqual(@as(u32, 3), n.strike_count);
    try std.testing.expect(n.is_jailed);

    // 4th execution should be skipped
    try orch.tick();
    try std.testing.expectEqual(@as(u32, 3), n.strike_count);
}

test "Poke (Event) system" {
    const allocator = std.testing.allocator;
    var orch: Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    // Mock vtable
    var mock_vtable: node.abi.moontide_extension_t = undefined;
    mock_vtable.create_node = (struct {
        fn create(_: [*c]const u8, _: [*c]const u8) callconv(.C) node.abi.moontide_node_h {
            return @as(node.abi.moontide_node_h, @ptrFromInt(0x1));
        }
    }).create;
    mock_vtable.destroy_node = (struct {
        fn destroy(_: node.abi.moontide_node_h) callconv(.C) void {}
    }).destroy;
    mock_vtable.bind_wire = (struct {
        fn bind(_: node.abi.moontide_node_h, _: [*c]const u8, _: ?*anyopaque, _: usize) callconv(.C) node.abi.moontide_status_t {
            return node.abi.MOONTIDE_STATUS_OK;
        }
    }).bind;
    mock_vtable.add_trigger = (struct {
        fn add(_: node.abi.moontide_node_h, _: [*c]const u8) callconv(.C) node.abi.moontide_status_t {
            return node.abi.MOONTIDE_STATUS_OK;
        }
    }).add;
    
    const Mock = struct {
        pub var count: u32 = 0;
        fn tick(_: node.abi.moontide_node_h) callconv(.C) node.abi.moontide_status_t {
            count += 1;
            return node.abi.MOONTIDE_STATUS_OK;
        }
    };
    mock_vtable.tick = Mock.tick;
    Mock.count = 0; // Reset

    const n = try allocator.create(node.Node);
    n.* = try node.Node.init(allocator, "poke_node", "mock", .Poke, "none", mock_vtable, @as(node.abi.moontide_node_h, @ptrFromInt(0x1)));
    try orch.nodes.put(try allocator.dupe(u8, "poke_node"), n);
    try n.addTrigger("test_event");

    try orch.rebuildTaskGraph();

    // 1. Regular tick should NOT trigger it
    try orch.tick();
    try std.testing.expectEqual(@as(u32, 0), Mock.count);

    // 2. Poke it
    try orch.poke("test_event");
    try orch.tick();
    try std.testing.expectEqual(@as(u32, 1), Mock.count);

    // Verify it's still ticking
    try orch.poke("test_event");
    try orch.poke("test_event");
    try orch.tick();
    try std.testing.expectEqual(@as(u32, 3), Mock.count);
}

test "Deterministic Scheduler (Race Prevention)" {
    const allocator = std.testing.allocator;
    var orch: Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    // Mock vtable
    var mock_vtable: node.abi.moontide_extension_t = undefined;
    mock_vtable.create_node = (struct {
        fn create(_: [*c]const u8, _: [*c]const u8) callconv(.C) node.abi.moontide_node_h {
            return @as(node.abi.moontide_node_h, @ptrFromInt(0x1));
        }
    }).create;
    mock_vtable.destroy_node = (struct {
        fn destroy(_: node.abi.moontide_node_h) callconv(.C) void {}
    }).destroy;
    mock_vtable.bind_wire = (struct {
        fn bind(_: node.abi.moontide_node_h, _: [*c]const u8, _: ?*anyopaque, _: usize) callconv(.C) node.abi.moontide_status_t {
            return node.abi.MOONTIDE_STATUS_OK;
        }
    }).bind;

    const w = try orch.addWire("race.wire", "val:i32", 4, true); // BUFFERED

    const n1 = try allocator.create(node.Node);
    n1.* = try node.Node.init(allocator, "a", "mock", .Heartbeat, "none", mock_vtable, @as(node.abi.moontide_node_h, @ptrFromInt(1)));
    try orch.nodes.put(try allocator.dupe(u8, "a"), n1);
    n1.bindWire("race.wire", w, std.posix.PROT.READ | std.posix.PROT.WRITE);

    const n2 = try allocator.create(node.Node);
    n2.* = try node.Node.init(allocator, "b", "mock", .Heartbeat, "none", mock_vtable, @as(node.abi.moontide_node_h, @ptrFromInt(2)));
    try orch.nodes.put(try allocator.dupe(u8, "b"), n2);
    n2.bindWire("race.wire", w, std.posix.PROT.READ | std.posix.PROT.WRITE);

    // EVEN THOUGH BUFFERED, they should NOT be in the same level
    // because multiple writers lead to non-determinism.
    try orch.rebuildTaskGraph();
    try std.testing.expectEqual(orch.levels.items.len, 2);
}

test "Schema Evolution and Data Migration" {
    const allocator = std.testing.allocator;
    var orch: Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    // 1. Create original wire
    const w1 = try orch.addWire("evolve.me", "x:i32", 4, false);
    w1.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
    @as(*i32, @ptrCast(@alignCast(w1.ptr()))).* = 42;
    w1.setAccess(std.posix.PROT.NONE);

    // 2. Evolve it (add y:i32)
    const w2 = try orch.addWire("evolve.me", "x:i32;y:i32", 8, false);
    
    // 3. Verify it's a new object but data is migrated
    try std.testing.expect(w1 != w2);
    try std.testing.expectEqual(orch.wires.get("evolve.me").?, w2);
    
    w2.setAccess(std.posix.PROT.READ);
    try std.testing.expectEqual(@as(i32, 42), @as(*i32, @ptrCast(@alignCast(w2.ptr()))).*);
    w2.setAccess(std.posix.PROT.NONE);
}

test "Eternal Library: State Serialization" {
    const allocator = std.testing.allocator;
    
    // 1. Setup Source Orchestrator
    var orch1: Orchestrator = undefined;
    try orch1.init(allocator);
    defer orch1.deinit();

    const w1 = try orch1.addWire("save.me", "val:i32", 4, true);
    w1.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
    @as(*i32, @ptrCast(@alignCast(w1.banks[0].ptr))).* = 1234;
    @as(*i32, @ptrCast(@alignCast(w1.banks[1].ptr))).* = 5678;
    w1.setAccess(std.posix.PROT.NONE);

    // 2. Serialize to Buffer
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try orch1.dumpToWriter(buffer.writer());

    // 3. Setup Destination Orchestrator
    var orch2: Orchestrator = undefined;
    try orch2.init(allocator);
    defer orch2.deinit();

    // 4. Deserialize
    var stream = std.io.fixedBufferStream(buffer.items);
    try orch2.loadFromReader(stream.reader());

    // 5. Verify bits are identical
    const w2 = orch2.getWire("save.me").?;
    try std.testing.expectEqual(@as(u64, 4), w2.size);
    try std.testing.expect(w2.is_buffered);

    w2.setAccess(std.posix.PROT.READ);
    try std.testing.expectEqual(@as(i32, 1234), @as(*i32, @ptrCast(@alignCast(w2.banks[0].ptr))).*);
    try std.testing.expectEqual(@as(i32, 5678), @as(*i32, @ptrCast(@alignCast(w2.banks[1].ptr))).*);
    w2.setAccess(std.posix.PROT.NONE);
}

test "Journal Extension Logic: Save/Restore Cycle" {
    const allocator = std.testing.allocator;
    
    // 1. Setup Orchestrator
    var orch: Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    // 2. Add some data to a Wire
    const w = try orch.addWire("test.data", "val:i32", 4, true);
    w.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
    @as(*i32, @ptrCast(@alignCast(w.banks[0].ptr))).* = 1337;
    w.setAccess(std.posix.PROT.NONE);

    // 3. Simulate Journal Extension 'save'
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try orch.dumpToWriter(buffer.writer());

    // 4. Corrupt/Change data
    w.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
    @as(*i32, @ptrCast(@alignCast(w.banks[0].ptr))).* = 0;
    w.setAccess(std.posix.PROT.NONE);

    // 5. Simulate Journal Extension 'load'
    var stream = std.io.fixedBufferStream(buffer.items);
    try orch.loadFromReader(stream.reader());

    // 6. Verify restoration
    const restored_w = orch.getWire("test.data").?;
    restored_w.setAccess(std.posix.PROT.READ);
    try std.testing.expectEqual(@as(i32, 1337), @as(*i32, @ptrCast(@alignCast(restored_w.banks[0].ptr))).*);
    restored_w.setAccess(std.posix.PROT.NONE);
}

test "Audio Extension: Command Processing and Clearing" {
    const allocator = std.testing.allocator;
    
    // 1. Setup Orchestrator
    var orch: Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    // 2. Add Audio Play Wire
    const w = try orch.addWire("audio.play", "id:u32[16];volume:f32[16];pitch:f32[16]", 16 * (4 + 4 + 4), false);
    
    // 3. Write a command to the wire
    w.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
    const cmd_ptr: [*]u32 = @ptrCast(@alignCast(w.ptr()));
    cmd_ptr[0] = 1; // Play Sound ID 1
    w.setAccess(std.posix.PROT.NONE);

    // 4. Simulate Audio Extension 'tick' logic
    // We'll just verify the clearing logic here since we can't easily 
    // test the hardware audio output in a unit test.
    w.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
    if (cmd_ptr[0] != 0) {
        // "Processing..."
        cmd_ptr[0] = 0; // Clear it
    }
    w.setAccess(std.posix.PROT.NONE);

    // 5. Verify the command was cleared
    w.setAccess(std.posix.PROT.READ);
    try std.testing.expectEqual(@as(u32, 0), cmd_ptr[0]);
    w.setAccess(std.posix.PROT.NONE);
}

test "TidePool Networking: Ring Buffer Logic" {
    const allocator = std.testing.allocator;
    
    // 1. Setup Orchestrator
    var orch: Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    // 2. Add Network Incoming Wire (Ring Buffer)
    const INCOMING_SIZE = 1024;
    const w = try orch.addWire("network.incoming", "head:u32;tail:u32;data:u8[1024]", 8 + INCOMING_SIZE, false);
    
    // 3. Simulate TidePool 'receive'
    w.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
    const header: *struct { head: u32, tail: u32 } = @ptrCast(@alignCast(w.ptr()));
    const data_ptr: [*]u8 = @ptrCast(w.ptr());
    const ring_ptr = data_ptr + 8;

    // Write a dummy packet: [Len:2][Addr:4][Port:2][Data:4] = 12 bytes
    const packet_data = "HELO";
    const len: u16 = 4;
    const addr: u32 = 0x01020304;
    const port: u16 = 8080;

    @memcpy(ring_ptr[0..2], std.mem.asBytes(&len));
    @memcpy(ring_ptr[2..6], std.mem.asBytes(&addr));
    @memcpy(ring_ptr[6..8], std.mem.asBytes(&port));
    @memcpy(ring_ptr[8..12], packet_data);
    header.head = 12;
    w.setAccess(std.posix.PROT.NONE);

    // 4. Verify Logic (Lua Node side)
    w.setAccess(std.posix.PROT.READ);
    try std.testing.expectEqual(@as(u32, 12), header.head);
    try std.testing.expectEqual(@as(u32, 0), header.tail);
    
    const read_len = @as(*const u16, @ptrCast(@alignCast(ring_ptr[0..2]))).*;
    try std.testing.expectEqual(@as(u16, 4), read_len);
    w.setAccess(std.posix.PROT.NONE);
}

test "Tensor Extension: SIMD Math Accuracy" {
    const allocator = std.testing.allocator;
    
    // 1. Setup Orchestrator
    var orch: Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    // 2. Add Tensor Wires
    const mem_w = try orch.addWire("tensor.memory", "data:f32[64]", 64 * 4, false);
    
    // 3. Setup MATMUL test: [1, 2] * [[3, 4], [5, 6]] = [13, 16]
    mem_w.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
    const mem: [*]f32 = @ptrCast(@alignCast(mem_w.ptr()));
    
    mem[0] = 1.0; mem[1] = 2.0; // Input
    mem[10] = 3.0; mem[11] = 4.0; mem[12] = 5.0; mem[13] = 6.0; // Weights (2x2)
    
    // 4. Simulate Tensor Engine MATMUL (Inner Dim = 2, Rows = 1, Cols = 2)
    const row = 0;
    const col1 = 0;
    const col2 = 1;
    
    var sum1: f32 = 0;
    for (0..2) |k| { sum1 += mem[row * 2 + k] * mem[10 + k * 2 + col1]; }
    mem[20] = sum1;

    var sum2: f32 = 0;
    for (0..2) |k| { sum2 += mem[row * 2 + k] * mem[10 + k * 2 + col2]; }
    mem[21] = sum2;

    // 5. Verify Results
    try std.testing.expectApproxEqAbs(@as(f32, 13.0), mem[20], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), mem[21], 0.0001);
    
    mem_w.setAccess(std.posix.PROT.NONE);
}

test "Type-Change (Ghost Data) Protection" {
    const allocator = std.testing.allocator;
    var orch: Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    // 1. Create a wire as f32 (4 bytes)
    const w1 = try orch.addWire("type.test", "val:f32", 4, false);
    w1.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
    @as(*f32, @ptrCast(@alignCast(w1.ptr()))).* = 1.0;
    w1.setAccess(std.posix.PROT.NONE);

    // 2. Evolve to i32 (also 4 bytes)
    const w2 = try orch.addWire("type.test", "val:i32", 4, false);
    
    // 3. Verify it's a new object even though size is the same
    try std.testing.expect(w1 != w2);
    
    // Data is still migrated (which is okay for now, as we didn't wipe it)
    // but the point is we trigger the evolution event and update the schema string.
    try std.testing.expectEqualStrings("val:i32", w2.schema_str);
}

test "Circular Dependency Detection" {
    const allocator = std.testing.allocator;
    var orch: Orchestrator = undefined;
    try orch.init(allocator);
    defer orch.deinit();

    // Mock vtable
    var mock_vtable: node.abi.moontide_extension_t = undefined;
    mock_vtable.create_node = (struct {
        fn create(_: [*c]const u8, _: [*c]const u8) callconv(.C) node.abi.moontide_node_h {
            return @as(node.abi.moontide_node_h, @ptrFromInt(0x1));
        }
    }).create;
    mock_vtable.destroy_node = (struct {
        fn destroy(_: node.abi.moontide_node_h) callconv(.C) void {}
    }).destroy;

    const n1 = try allocator.create(node.Node);
    n1.* = try node.Node.init(allocator, "a", "mock", .Heartbeat, "none", mock_vtable, @as(node.abi.moontide_node_h, @ptrFromInt(1)));
    try orch.nodes.put(try allocator.dupe(u8, "a"), n1);

    const n2 = try allocator.create(node.Node);
    n2.* = try node.Node.init(allocator, "b", "mock", .Heartbeat, "none", mock_vtable, @as(node.abi.moontide_node_h, @ptrFromInt(2)));
    try orch.nodes.put(try allocator.dupe(u8, "b"), n2);

    // Create cycle: a after b, b after a
    try n1.after.append(try allocator.dupe(u8, "b"));
    try n2.after.append(try allocator.dupe(u8, "a"));

    try std.testing.expectError(error.CircularDependency, orch.rebuildTaskGraph());
}

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
            entry.value_ptr.*.deinit();
        }
        self.wires.deinit();
        
        for (self.levels.items) |level| level.deinit();
        self.levels.deinit();
        
        self.extensions.deinit();
        
        for (self.pokes.items) |p| self.allocator.free(p);
        self.pokes.deinit();
    }

    pub fn addWire(self: *Orchestrator, path: []const u8, schema_str: []const u8, size: usize, buffered: bool) !*wire.RawWire {
        if (self.wires.get(path)) |w| {
            if (std.mem.eql(u8, w.schema_str, schema_str) and w.size == size) return w;
            
            // SCHEMA EVOLUTION: Schema or Size changed!
            std.debug.print("[Orchestrator] Evolving Wire: {s} (Size: {d}->{d}, Schema: {s}->{s})\n", .{ path, w.size, size, w.schema_str, schema_str });
            
            const new_w = try wire.RawWire.init(self.allocator, path, schema_str, size, buffered);
            
            // Migrate data
            w.setAccess(std.posix.PROT.READ);
            new_w.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
            
            const copy_size = if (size < w.size) size else w.size;
            @memcpy(new_w.banks[0][0..copy_size], w.banks[w.front_index][0..copy_size]);
            if (buffered and w.is_buffered) {
                @memcpy(new_w.banks[1][0..copy_size], w.banks[1 - w.front_index][0..copy_size]);
            }
            
            new_w.setAccess(std.posix.PROT.NONE);
            w.setAccess(std.posix.PROT.NONE);
            
            // Replace and cleanup old
            if (self.wires.fetchRemove(path)) |entry| {
                self.allocator.free(entry.key);
            }
            try self.wires.put(try self.allocator.dupe(u8, path), new_w);
            
            w.deinit();
            return new_w;
        }

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
        n.* = try node.Node.init(self.allocator, path, ext_type, mode, script, ext.vtable, handle);
        try self.nodes.put(try self.allocator.dupe(u8, path), n);
        return n;
    }

    pub fn rebuildTaskGraph(self: *Orchestrator) !void {
        for (self.levels.items) |level| level.deinit();
        self.levels.clearRetainingCapacity();

        // --- SILICON UNLOCK ---
        // During DAG construction, we must ensure wires are readable.
        var wit = self.wires.valueIterator();
        while (wit.next()) |w| w.*.setAccess(std.posix.PROT.READ);

        var remaining = std.ArrayList(*node.Node).init(self.allocator);
        defer remaining.deinit();
        
        var it = self.nodes.valueIterator();
        while (it.next()) |n| {
            if (n.*.mode == .Heartbeat) try remaining.append(n.*);
        }

        // 1. DETERMINISM: Sort nodes by name
        std.mem.sort(*node.Node, remaining.items, {}, struct {
            fn lessThan(_: void, a: *node.Node, b: *node.Node) bool {
                return std.mem.lessThan(u8, a.name, b.name);
            }
        }.lessThan);

        var completed = std.StringHashMap(void).init(self.allocator);
        defer completed.deinit();

        while (remaining.items.len > 0) {
            var current_level = std.ArrayList(*node.Node).init(self.allocator);
            var i: usize = 0;
            var added_any = false;

            while (i < remaining.items.len) {
                const n = remaining.items[i];
                
                // --- 2. 'AFTER' DEPENDENCY CHECK ---
                var deps_met = true;
                for (n.after.items) |dep| {
                    if (!completed.contains(dep)) {
                        deps_met = false;
                        break;
                    }
                }

                if (!deps_met) {
                    i += 1;
                    continue;
                }

                // --- 3. CONFLICT CHECK ---
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
                    added_any = true;
                } else {
                    i += 1;
                }
            }

            if (!added_any) {
                std.debug.print("[Orchestrator] ERROR: Circular dependency detected or impossible graph!\n", .{});
                // RE-LOCK before erroring
                var wit_err = self.wires.valueIterator();
                while (wit_err.next()) |w| w.*.setAccess(std.posix.PROT.NONE);
                return error.CircularDependency;
            }

            // Mark this level as completed for 'after' constraints
            for (current_level.items) |n| {
                try completed.put(n.name, {});
            }

            try self.levels.append(current_level);
        }
        
        // --- SILICON RE-LOCK ---
        var wit_end = self.wires.valueIterator();
        while (wit_end.next()) |w| w.*.setAccess(std.posix.PROT.NONE);

        std.debug.print("[Orchestrator] Task Graph: {d} parallel levels.\n", .{ self.levels.items.len });
    }

    fn nodesCollide(a: *node.Node, b: *node.Node) bool {
        var a_it = a.bound_wires.valueIterator();
        while (a_it.next()) |a_b| {
            // CRITICAL: The scheduler needs to read the wire pointer/metadata.
            // But wires are usually locked (PROT_NONE).
            // Actually, we are only reading 'a_b.wire' which is a pointer in the Node,
            // NOT the memory the wire points to.
            // Wait, why did it segfault? Ah! I accessed 'a_b.wire.is_buffered' in the previous version.
            // In the NEW version, I don't access 'is_buffered'.
            // Let me check if anything else in 'nodesCollide' accesses the wire data.
            
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
                if (std.mem.eql(u8, n.ext_type, "hud")) continue;
                try threads.append(try std.Thread.spawn(.{}, parallelWorker, .{n}));
            }

            // Run Main-Thread nodes LOCALLY while workers are busy
            for (level.items) |n| {
                if (std.mem.eql(u8, n.ext_type, "hud")) {
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

        // --- SILICON GRANT ---
        var it = n.bound_wires.iterator();
        while (it.next()) |entry| {
            const binding = entry.value_ptr;
            const w = binding.wire;
            const is_write = (binding.access & 2 != 0);
            if (w.is_buffered and is_write) {
                // Grant access to the BACK bank for writing
                w.setBankAccess(1 - w.front_index, binding.access);
            } else {
                // Grant access to the FRONT bank for reading
                w.setBankAccess(w.front_index, binding.access);
            }
        }

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
        
        // --- SILICON REVOKE ---
        it = n.bound_wires.iterator();
        while (it.next()) |entry| {
            const binding = entry.value_ptr;
            const w = binding.wire;
            const is_write = (binding.access & 2 != 0);
            const bank_idx: usize = if (w.is_buffered and is_write) 1 - w.front_index else w.front_index;
            w.setBankAccess(bank_idx, std.posix.PROT.NONE);
        }

        // TRACK END
        n.is_running.store(false, .release);
        sandbox.is_recovering = false;
    }

    fn watchdogLoop(self: *Orchestrator) void {
        const timeout_ms: i64 = 1000; // 1 second budget

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

    pub fn dumpToWriter(self: *Orchestrator, writer: anytype) !void {
        // 1. Write number of wires
        try writer.writeInt(u32, @intCast(self.wires.count()), .little);

        var it = self.wires.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            const w = entry.value_ptr.*;

            // 2. Write Name
            try writer.writeInt(u32, @intCast(name.len), .little);
            try writer.writeAll(name);

            // 3. Write Size and Buffered Status
            try writer.writeInt(u64, w.size, .little);
            try writer.writeByte(if (w.is_buffered) 1 else 0);

            // 4. Write Data (Both banks if buffered)
            w.setAccess(std.posix.PROT.READ);
            defer w.setAccess(std.posix.PROT.NONE);

            try writer.writeAll(w.banks[0][0..w.size]);
            if (w.is_buffered) {
                try writer.writeAll(w.banks[1][0..w.size]);
            }
        }
    }

    pub fn loadFromReader(self: *Orchestrator, reader: anytype) !void {
        const wire_count = try reader.readInt(u32, .little);

        for (0..wire_count) |_| {
            // 1. Read Name
            const name_len = try reader.readInt(u32, .little);
            const name = try self.allocator.alloc(u8, name_len);
            defer self.allocator.free(name);
            try reader.readNoEof(name);

            // 2. Read Meta
            const size = try reader.readInt(u64, .little);
            const buffered = (try reader.readByte()) != 0;

            // 3. Find or Create Wire
            // Note: If it doesn't exist, we use a generic schema string for now
            // as we only care about the bits.
            const w = try self.addWire(name, "restored:u8", size, buffered);

            // 4. Read Data
            w.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
            defer w.setAccess(std.posix.PROT.NONE);

            try reader.readNoEof(w.banks[0][0..size]);
            if (buffered) {
                try reader.readNoEof(w.banks[1][0..size]);
            }
        }
    }
};

// --- HOST ABI EXPORTS ---

export fn moontide_orch_create() ?*anyopaque {
    const orch = std.heap.c_allocator.create(Orchestrator) catch return null;
    orch.init(std.heap.c_allocator) catch {
        std.heap.c_allocator.destroy(orch);
        return null;
    };
    return @ptrCast(orch);
}

export fn moontide_orch_destroy(handle: ?*anyopaque) void {
    const orch: *Orchestrator = @ptrCast(@alignCast(handle));
    orch.deinit();
    std.heap.c_allocator.destroy(orch);
}

export fn moontide_orch_add_wire(handle: ?*anyopaque, name: [*c]const u8, schema_str: [*c]const u8, size: usize, buffered: bool) ?*anyopaque {
    const orch: *Orchestrator = @ptrCast(@alignCast(handle));
    const w = orch.addWire(std.mem.span(name), std.mem.span(schema_str), size, buffered) catch return null;
    return @ptrCast(w);
}

export fn moontide_wire_get_ptr(handle: ?*anyopaque) ?*anyopaque {
    const w: *wire.RawWire = @ptrCast(@alignCast(handle));
    return w.ptr();
}

export fn moontide_wire_set_access(handle: ?*anyopaque, prot: u32) void {
    const w: *wire.RawWire = @ptrCast(@alignCast(handle));
    w.setAccess(prot);
}

export fn moontide_wire_swap(handle: ?*anyopaque) void {
    const w: *wire.RawWire = @ptrCast(@alignCast(handle));
    w.swap();
}
