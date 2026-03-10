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

    pub fn init(allocator: std.mem.Allocator, name: []const u8, schema_str: []const u8, size: usize, buffered: bool) !*RawWire {
        const self = try allocator.create(RawWire);
        const page_size = 4096;
        const aligned_size = (size + page_size - 1) & ~@as(usize, page_size - 1);
        
        self.* = .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .schema_str = try allocator.dupe(u8, schema_str),
            .size = size,
            .is_buffered = buffered,
            .banks = undefined,
            .maps = undefined,
        };

        // Allocate Bank 0
        self.maps[0] = try std.posix.mmap(
            null,
            aligned_size,
            std.posix.PROT.NONE,
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0
        );
        self.banks[0] = self.maps[0][0..size];

        if (buffered) {
            // Allocate Bank 1
            self.maps[1] = try std.posix.mmap(
                null,
                aligned_size,
                std.posix.PROT.NONE,
                .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
                -1,
                0
            );
            self.banks[1] = self.maps[1][0..size];
        } else {
            self.banks[1] = &[_]u8{};
            self.maps[1] = self.maps[0][0..0];
        }
        
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
    pub fn swap(self: *RawWire) void {
        if (!self.is_buffered) return;
        
        // 1. Ensure Back bank has everything from Front bank before we start the next frame
        // This is necessary for read-modify-write operations (x += 1).
        // In a strictly "pure" model we wouldn't do this, but for "vibe coding" it's required.
        self.setAccess(std.posix.PROT.READ | std.posix.PROT.WRITE);
        const front = self.banks[self.front_index];
        const back = self.banks[1 - self.front_index];
        @memcpy(back[0..self.size], front[0..self.size]);
        self.setAccess(std.posix.PROT.NONE);

        self.front_index = 1 - self.front_index;
    }

    pub fn setAccess(self: *RawWire, prot: u32) void {
        for (0..2) |i| {
            if (self.maps[i].len > 0) {
                _ = std.posix.mprotect(self.maps[i], prot) catch |err| {
                    std.debug.print("[Wire {s}] mprotect bank {d} failed: {any}\n", .{ self.name, i, err });
                };
            }
        }
    }

    /// Set access for a specific bank
    pub fn setBankAccess(self: *RawWire, bank_idx: usize, prot: u32) void {
        if (self.maps[bank_idx].len > 0) {
            _ = std.posix.mprotect(self.maps[bank_idx], prot) catch {};
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
