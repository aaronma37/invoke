const std = @import("std");

/// The Moontide WASM Guest SDK
/// This provides a clean interface for Zig WASM nodes to interact with the Motherboard.

// Host Imports (Injected by WASM Extension)
extern fn moontide_log(level: i32, ptr: [*]const u8, len: usize) void;
extern fn moontide_poke(ptr: [*]const u8, len: usize) void;

pub const LogLevel = enum(i32) {
    Debug = 0,
    Info = 1,
    Warn = 2,
    Error = 3,
    Fatal = 4,
};

pub fn log(level: LogLevel, message: []const u8) void {
    moontide_log(@intFromEnum(level), message.ptr, message.len);
}

pub fn info(message: []const u8) void { log(.Info, message); }
pub fn warn(message: []const u8) void { log(.Warn, message); }
pub fn err(message: []const u8) void { log(.Error, message); }

pub fn poke(event_name: []const u8) void {
    moontide_poke(event_name.ptr, event_name.len);
}

// The shared wire buffer
pub var wire_buffer: [2048]u8 align(16) = undefined;

/// Returns the address of the wire buffer to the host.
/// The host uses this to sync data in/out.
export fn get_wire_buffer() [*]u8 {
    return &wire_buffer;
}

/// Helper to get a typed pointer to a bound wire.
pub fn getWire(comptime T: type, comptime offset: usize) *T {
    return @ptrCast(@alignCast(&wire_buffer[offset]));
}
