const std = @import("std");

/// The Invoke WASM Guest SDK
/// This provides a clean interface for Zig WASM nodes to interact with the Motherboard.

// The host-generated wire headers
pub const wires = @cImport({
    @cInclude("wires.h");
    @cInclude("guest_offsets.h");
});

// The shared wire buffer
pub var wire_buffer: [2048]u8 align(16) = undefined;

/// Returns the address of the wire buffer to the host.
/// The host uses this to sync data in/out.
export fn get_wire_buffer() [*]u8 {
    return &wire_buffer;
}

/// Helper to get a typed pointer to a bound wire.
pub fn getWire(comptime T: type, comptime name: []const u8) *T {
    const offset = @field(wires, "OFFSET_" ++ name);
    return @ptrCast(@alignCast(&wire_buffer[offset]));
}

/// The main entry point for the node.
/// This is what the host calls every heartbeat.
// pub fn tick() void {}
