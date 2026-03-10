const std = @import("std");
const node = @import("node.zig");

/// The Sandbox is responsible for managing the lifetime and memory access limits
/// for every node in the runtime, ensuring no node takes too long or writes outside
/// its allocated Wire.
pub const Sandbox = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Sandbox {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Sandbox) void {
        _ = self;
    }

    pub fn validateExecutionTime(self: *Sandbox, n: *node.Node, execution_time_ns: u64, max_time_ns: u64) !void {
        _ = self;
        if (execution_time_ns > max_time_ns) {
            std.debug.print("Sandbox Violation: Node {s} exceeded execution time! Terminating.\n", .{n.name});
            return error.ExecutionTimeout;
        }
    }

    pub fn validateMemoryAccess(self: *Sandbox, n: *node.Node, offset: usize, max_offset: usize) !void {
        _ = self;
        if (offset >= max_offset) {
            std.debug.print("Sandbox Violation: Node {s} attempted out-of-bounds memory access! Terminating.\n", .{n.name});
            return error.MemoryOutOfBounds;
        }
    }
};
