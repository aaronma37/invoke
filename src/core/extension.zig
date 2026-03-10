const std = @import("std");
const node = @import("node.zig");

pub const Extension = struct {
    lib: std.DynLib,
    vtable: node.abi.invoke_extension_t,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !*Extension {
        var self = try allocator.create(Extension);
        self.allocator = allocator;
        
        // 1. Load the shared library
        self.lib = try std.DynLib.open(path);
        
        // 2. Look up the entry point
        const init_fn = self.lib.lookup(node.abi.invoke_ext_init_fn, "invoke_ext_init") 
            orelse return error.ExtensionInitSymbolNotFound;
            
        // 3. Get the VTable (The Handshake)
        self.vtable = init_fn.?();
        
        return self;
    }

    pub fn deinit(self: *Extension) void {
        self.lib.close();
        self.allocator.destroy(self);
    }
};

pub const ExtensionManager = struct {
    allocator: std.mem.Allocator,
    extensions: std.StringHashMap(*Extension),

    pub fn init(allocator: std.mem.Allocator) ExtensionManager {
        return .{
            .allocator = allocator,
            .extensions = std.StringHashMap(*Extension).init(allocator),
        };
    }

    pub fn deinit(self: *ExtensionManager) void {
        var it = self.extensions.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
        }
        self.extensions.deinit();
    }

    pub fn getOrLoad(self: *ExtensionManager, ext_type: []const u8) !*Extension {
        if (self.extensions.get(ext_type)) |ext| return ext;

        // Path convention: ext/lib<type>_ext.so
        const path = try std.fmt.allocPrint(self.allocator, "ext/lib{s}_ext.so", .{ext_type});
        defer self.allocator.free(path);

        const ext = try Extension.init(self.allocator, path);
        try self.extensions.put(try self.allocator.dupe(u8, ext_type), ext);
        
        std.debug.print("[ExtensionManager] Loaded Runtime: {s}\n", .{ext_type});
        return ext;
    }
};
