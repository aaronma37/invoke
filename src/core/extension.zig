const std = @import("std");
const node = @import("node.zig");
const sandbox = @import("sandbox.zig");

const orchestrator = @import("orchestrator.zig");

pub var current_orch: ?*orchestrator.Orchestrator = null;

fn kernelLog(level: node.abi.moontide_log_level_t, node_name: [*c]const u8, message: [*c]const u8) callconv(.C) void {
    sandbox.checkPoints();
    const level_str = switch (level) {
        node.abi.MOONTIDE_LOG_DEBUG => "DEBUG",
        node.abi.MOONTIDE_LOG_INFO => "INFO ",
        node.abi.MOONTIDE_LOG_WARN => "WARN ",
        node.abi.MOONTIDE_LOG_ERROR => "ERROR",
        node.abi.MOONTIDE_LOG_FATAL => "FATAL",
        else => "?????",
    };
    
    // In a real project, we'd use a colorized, timestamped logger here.
    std.debug.print("[{s}] [{s}] {s}\n", .{ level_str, std.mem.span(node_name), std.mem.span(message) });
}

fn kernelPoke(event_name: [*c]const u8) callconv(.C) void {
    sandbox.checkPoints();
    if (current_orch) |orch| {
        orch.poke(std.mem.span(event_name)) catch {};
    }
}

pub const Extension = struct {
    lib: std.DynLib,
    vtable: node.abi.moontide_extension_t,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !*Extension {
        var self = try allocator.create(Extension);
        self.allocator = allocator;
        
        // 1. Load the shared library
        self.lib = try std.DynLib.open(path);
        
        // 2. Look up the entry point
        const init_fn = self.lib.lookup(node.abi.moontide_ext_init_fn, "moontide_ext_init") 
            orelse return error.ExtensionInitSymbolNotFound;
            
        // 3. Get the VTable (The Handshake)
        self.vtable = init_fn.?();
        
        // 4. Inject Host Services (v1.1)
        if (self.vtable.set_log_handler) |set_log| {
            set_log(kernelLog);
        }
        if (self.vtable.set_poke_handler) |set_poke| {
            set_poke(kernelPoke);
        }
        if (self.vtable.set_orchestrator_handler) |set_orch| {
            if (current_orch) |orch| {
                set_orch(orch);
            }
        }
        
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

        const lib_name = try std.fmt.allocPrint(self.allocator, "lib{s}_ext.so", .{ext_type});
        defer self.allocator.free(lib_name);

        // --- LOOKUP ORDER ---
        // 1. Local ./ext/
        // 2. User Global ~/.local/lib/moontide/ext/
        // 3. System Global /usr/local/lib/moontide/ext/

        const paths = [_][]const u8{
            "./ext/",
            "/usr/local/lib/moontide/ext/",
        };

        for (paths) |base_path| {
            const full_path = try std.fs.path.join(self.allocator, &.{ base_path, lib_name });
            defer self.allocator.free(full_path);

            if (Extension.init(self.allocator, full_path)) |ext| {
                try self.extensions.put(try self.allocator.dupe(u8, ext_type), ext);
                std.debug.print("[ExtensionManager] Loaded Runtime: {s} (from {s})\n", .{ ext_type, base_path });
                return ext;
            } else |_| {
                continue;
            }
        }

        // Try User Global if HOME is set
        const home_env = std.process.getEnvVarOwned(self.allocator, "HOME") catch null;
        if (home_env) |home| {
            defer self.allocator.free(home);
            const user_path = try std.fs.path.join(self.allocator, &.{ home, ".local/lib/moontide/ext/" });
            defer self.allocator.free(user_path);
            
            const full_path = try std.fs.path.join(self.allocator, &.{ user_path, lib_name });
            defer self.allocator.free(full_path);

            if (Extension.init(self.allocator, full_path)) |ext| {
                try self.extensions.put(try self.allocator.dupe(u8, ext_type), ext);
                std.debug.print("[ExtensionManager] Loaded Runtime: {s} (from user global)\n", .{ ext_type });
                return ext;
            } else |_| {}
        }

        std.debug.print("[ExtensionManager] ERROR: Could not find runtime '{s}' in any standard path.\n", .{ext_type});
        return error.ExtensionNotFound;
    }
};
