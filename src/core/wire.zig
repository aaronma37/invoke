const std = @import("std");
const os = std.os.linux;

/// A RawWire is a page-aligned, contiguous memory buffer.
/// It uses 'mmap' to allow for hardware-enforced memory protection (mprotect).
pub const RawWire = struct {
    buffer: []u8,
    allocator: std.mem.Allocator,
    name: []const u8,
    
    // The actual mapped memory address (page-aligned)
    map_ptr: [*]u8,
    map_len: usize,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, size: usize) !*RawWire {
        const self = try allocator.create(RawWire);
        
        // Calculate page-aligned size
        const page_size = 4096;
        const aligned_size = (size + page_size - 1) & ~@as(usize, page_size - 1);
        
        // Allocate via mmap
        const mmap_ptr = try std.posix.mmap(
            null,
            aligned_size,
            std.posix.PROT.NONE, // Start locked!
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0
        );

        self.* = .{
            .buffer = mmap_ptr[0..size],
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .map_ptr = mmap_ptr.ptr,
            .map_len = aligned_size,
        };
        
        return self;
    }

    pub fn deinit(self: *RawWire) void {
        const slice = self.map_ptr[0..self.map_len];
        const aligned_slice: []align(4096) u8 = @alignCast(@as([]u8, @ptrCast(slice)));
        std.posix.munmap(aligned_slice);
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }

    /// Unlock memory for hardware access
    pub fn setAccess(self: *RawWire, prot: u32) void {
        const slice = self.map_ptr[0..self.map_len];
        const aligned_slice: []align(4096) u8 = @alignCast(@as([]u8, @ptrCast(slice)));
        _ = std.posix.mprotect(aligned_slice, prot) catch |err| {
            std.debug.print("[Wire {s}] mprotect failed: {any}\n", .{ self.name, err });
        };
    }

    pub fn ptr(self: *RawWire) *anyopaque {
        return @ptrCast(self.buffer.ptr);
    }
};
