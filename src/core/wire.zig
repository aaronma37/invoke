const std = @import("std");
const os = std.os.linux;

/// A RawWire is a page-aligned, contiguous memory buffer.
/// It uses 'mmap' to allow for hardware-enforced memory protection (mprotect).
pub const RawWire = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    schema_str: []const u8,
    size: usize,
    
    // The two banks
    banks: [2][]u8,
    front_index: u8 = 0,
    is_buffered: bool,
    
    // Page-aligned mapping info for mprotect
    maps: [2][]align(4096) u8,
    full_mapping_size: usize = 0,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, schema_str: []const u8, size: usize, buffered: bool) !*RawWire {
        const self = try allocator.create(RawWire);
        const page_size = 4096;
        var aligned_size = (size + page_size - 1) & ~@as(usize, page_size - 1);
        if (aligned_size == 0) aligned_size = page_size;
        
        // We allocate an EXTRA page for the Guard Zone
        const total_alloc_size = aligned_size + page_size;

        self.* = .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .schema_str = try allocator.dupe(u8, schema_str),
            .size = size,
            .is_buffered = buffered,
            .banks = undefined,
            .maps = undefined,
            .full_mapping_size = total_alloc_size,
        };

        // Allocate Bank 0 + Guard
        self.maps[0] = try std.posix.mmap(
            null,
            total_alloc_size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0
        );
        self.banks[0] = self.maps[0][0..size];
        
        // LOCK THE GUARD PAGE (The last 4KB)
        const guard0 = @as([]align(4096) u8, @alignCast(self.maps[0][aligned_size..]));
        _ = std.posix.mprotect(guard0, std.posix.PROT.NONE) catch {};

        if (buffered) {
            // Allocate Bank 1 + Guard
            self.maps[1] = try std.posix.mmap(
                null,
                total_alloc_size,
                std.posix.PROT.READ | std.posix.PROT.WRITE,
                .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
                -1,
                0
            );
            self.banks[1] = self.maps[1][0..size];
            const guard1 = @as([]align(4096) u8, @alignCast(self.maps[1][aligned_size..]));
            _ = std.posix.mprotect(guard1, std.posix.PROT.NONE) catch {};
        } else {
            self.banks[1] = &[_]u8{};
            self.maps[1] = self.maps[0][0..0];
        }
        
        return self;
    }

    pub fn initExternal(allocator: std.mem.Allocator, name: []const u8, schema_str: []const u8, size: usize, external_ptr: ?*anyopaque) !*RawWire {
        const self = try allocator.create(RawWire);
        self.* = .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .schema_str = try allocator.dupe(u8, schema_str),
            .size = size,
            .is_buffered = false,
            .banks = undefined,
            .maps = undefined,
            .full_mapping_size = 0,
        };
        self.banks[0] = @as([*]u8, @ptrCast(external_ptr))[0..size];
        self.banks[1] = &[_]u8{};
        self.maps[0] = self.maps[0][0..0];
        self.maps[1] = self.maps[0][0..0];
        return self;
    }

    pub fn deinit(self: *RawWire) void {
        for (0..2) |i| {
            if (self.maps[i].len > 0) {
                std.posix.munmap(self.maps[i]);
            }
        }
        self.allocator.free(self.name);
        self.allocator.free(self.schema_str);
        self.allocator.destroy(self);
    }

    /// Flip the banks! Back becomes Front.
    /// In Moontide Neural, this is the 'Synchronous Pulse Barrier'.
    pub fn swap(self: *RawWire) void {
        if (!self.is_buffered) return;

        // 1. Flip the index so current Back becomes the new Front
        self.front_index = 1 - self.front_index;

        // 2. Synchronize the new Back buffer with the new Front buffer
        // FUTURE: For massive reservoirs, we should use a sparse 'Dirty Page' tracker
        // or a SIMD-accelerated copy to minimize Infinity Fabric traffic.
        self.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
        @memcpy(self.banks[1 - self.front_index][0..self.size], self.banks[self.front_index][0..self.size]);
        self.setAccess(std.posix.PROT.NONE);
    }
    pub fn setAccess(self: *RawWire, prot: u32) void {
        const page_size = 4096;
        const aligned_size = (self.size + page_size - 1) & ~@as(usize, page_size - 1);

        for (0..2) |i| {
            if (self.maps[i].len > 0) {
                // We ONLY mprotect the USABLE part, leaving the guard page locked.
                const usable = @as([]align(4096) u8, @alignCast(self.maps[i][0..aligned_size]));
                _ = std.posix.mprotect(usable, prot) catch |err| {
                    std.debug.print("[Wire {s}] mprotect bank {d} failed: {any}\n", .{ self.name, i, err });
                };
            }
        }
    }

    /// Set access for a specific bank
    pub fn setBankAccess(self: *RawWire, bank_idx: usize, prot: u32) void {
        if (self.maps[bank_idx].len > 0) {
            const page_size = 4096;
            const aligned_size = (self.size + page_size - 1) & ~@as(usize, page_size - 1);
            const usable = @as([]align(4096) u8, @alignCast(self.maps[bank_idx][0..aligned_size]));
            _ = std.posix.mprotect(usable, prot) catch {};
        }
    }

    pub fn frontPtr(self: *RawWire) *anyopaque {
        return @ptrCast(self.banks[self.front_index].ptr);
    }

    pub fn backPtr(self: *RawWire) *anyopaque {
        if (!self.is_buffered) return self.frontPtr();
        return @ptrCast(self.banks[1 - self.front_index].ptr);
    }

    // Legacy helper for the monitor
    pub fn ptr(self: *RawWire) *anyopaque {
        return self.frontPtr();
    }
};

test "RawWire allocation and swapping" {
    const allocator = std.testing.allocator;
    const wire = try RawWire.init(allocator, "test_wire", "x:f32;y:f32", 8, true);
    defer wire.deinit();

    try std.testing.expect(wire.is_buffered);
    try std.testing.expectEqual(@as(usize, 8), wire.size);

    // Initial state: Front and Back should be different
    const front1 = wire.frontPtr();
    const back1 = wire.backPtr();
    try std.testing.expect(front1 != back1);

    // Write to back
    wire.setBankAccess(1 - wire.front_index, std.posix.PROT.READ | std.posix.PROT.WRITE);
    const back_slice: []u8 = @as([*]u8, @ptrCast(back1))[0..8];
    back_slice[0] = 42;
    wire.setBankAccess(1 - wire.front_index, std.posix.PROT.NONE);

    // Swap
    wire.swap();

    // Now Front should have the value
    wire.setBankAccess(wire.front_index, std.posix.PROT.READ);
    const front_slice: []u8 = @as([*]u8, @ptrCast(wire.frontPtr()))[0..8];
    try std.testing.expectEqual(@as(u8, 42), front_slice[0]);
    wire.setBankAccess(wire.front_index, std.posix.PROT.NONE);
}

test "RawWire unbuffered" {
    const allocator = std.testing.allocator;
    const wire = try RawWire.init(allocator, "test_unbuffered", "x:f32", 4, false);
    defer wire.deinit();

    try std.testing.expect(!wire.is_buffered);
    try std.testing.expectEqual(wire.frontPtr(), wire.backPtr());
}

test "RawWire Guard Page (Buffer Overflow)" {
    const sandbox = @import("sandbox.zig");
    const allocator = std.testing.allocator;
    const wire = try RawWire.init(allocator, "overflow_test", "x:f32", 4, false);
    defer wire.deinit();

    // Grant read/write to the USABLE part
    wire.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);

    // Calculate where the guard page starts (4KB aligned)
    const page_size = 4096;
    const aligned_size = page_size; // because size=4 fits in 1st page
    
    const base_ptr: [*]u8 = @ptrCast(wire.frontPtr());
    const guard_ptr = base_ptr + aligned_size;

    // Verify we can write to the usable part
    base_ptr[0] = 10;
    try std.testing.expectEqual(@as(u8, 10), base_ptr[0]);

    // Test Guard Page Violation
    sandbox.initSignalHandler();
    sandbox.is_recovering = true;
    defer sandbox.is_recovering = false;

    if (sandbox.c.setjmp(&sandbox.jump_buffer) == 0) {
        // This should trigger SIGSEGV because guard_ptr is PROT_NONE
        guard_ptr[0] = 99;
        try std.testing.expect(false); // Should not reach here
    } else {
        // Recovered!
        try std.testing.expect(true);
    }
}
