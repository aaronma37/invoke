const std = @import("std");

const c = @cImport({
    @cInclude("wasmtime.h");
    @cInclude("invoke_abi.h");
});

const abi = c;

const WasmNode = struct {
    engine: ?*c.wasm_engine_t,
    store: ?*c.wasmtime_store_t,
    context: ?*c.wasmtime_context_t,
    module: ?*c.wasmtime_module_t,
    instance: c.wasmtime_instance_t,
    memory: c.wasmtime_memory_t,
    has_memory: bool = false,
    guest_offset: usize = 0,
    allocator: std.mem.Allocator,
    
    // HOT LOOP OPTIMIZATION: 
    // We use a flat array of bindings instead of a HashMap.
    // O(1) performance during tick.
    bindings: std.ArrayList(SyncBinding),

    const SyncBinding = struct {
        host_ptr: [*]u8,
        guest_offset: usize,
        size: usize,
        is_output: bool,
    };

    pub fn init(allocator: std.mem.Allocator, name: [*c]const u8, script_path: [*c]const u8) !*WasmNode {
        const self = try allocator.create(WasmNode);
        self.allocator = allocator;
        self.bindings = std.ArrayList(SyncBinding).init(allocator);
        
        self.engine = c.wasm_engine_new() orelse return error.WasmEngineNewFailed;
        self.store = c.wasmtime_store_new(self.engine, null, null) orelse return error.WasmStoreNewFailed;
        self.context = c.wasmtime_store_context(self.store);

        const wasm_bytes = try std.fs.cwd().readFileAlloc(allocator, std.mem.span(script_path), 10 * 1024 * 1024);
        defer allocator.free(wasm_bytes);

        var err: ?*c.wasmtime_error_t = null;
        err = c.wasmtime_module_new(self.engine, wasm_bytes.ptr, wasm_bytes.len, &self.module);
        if (err != null) return error.WasmModuleNewFailed;

        var trap: ?*c.wasm_trap_t = null;
        err = c.wasmtime_instance_new(self.context, self.module, null, 0, &self.instance, &trap);
        if (err != null or trap != null) return error.WasmInstantiateFailed;

        var export_val: c.wasmtime_extern_t = undefined;
        if (c.wasmtime_instance_export_get(self.context, &self.instance, "memory", 6, &export_val)) {
            if (export_val.kind == c.WASMTIME_EXTERN_MEMORY) {
                self.memory = export_val.of.memory;
                self.has_memory = true;
            }
        }

        if (c.wasmtime_instance_export_get(self.context, &self.instance, "get_wire_buffer", 15, &export_val)) {
            var results: [1]c.wasmtime_val_t = undefined;
            err = c.wasmtime_func_call(self.context, &export_val.of.func, null, 0, &results, 1, &trap);
            if (err == null and trap == null) {
                self.guest_offset = @intCast(results[0].of.i32);
            }
        }

        _ = name;
        return self;
    }

    pub fn deinit(self: *WasmNode) void {
        self.bindings.deinit();
        if (self.module) |m| c.wasmtime_module_delete(m);
        if (self.store) |s| c.wasmtime_store_delete(s);
        if (self.engine) |e| c.wasm_engine_delete(e);
        self.allocator.destroy(self);
    }
};

// --- ABI IMPLEMENTATION ---

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.invoke_node_h {
    const node = WasmNode.init(std.heap.c_allocator, name, script_path) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.invoke_node_h) void {
    const node: *WasmNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.invoke_node_h, name: [*c]const u8, ptr: ?*anyopaque, size: usize) abi.invoke_status_t {
    const node: *WasmNode = @ptrCast(@alignCast(handle));
    
    // DYNAMIC OFFSET CALCULATION:
    // We calculate the offset based on the previous bindings + alignment.
    var current_offset: usize = 0;
    for (node.bindings.items) |b| {
        current_offset += (b.size + 15) & ~@as(usize, 15); // 16-byte alignment
    }

    // For now, we assume all bound wires are synced in/out.
    // In a real 'Pro' engine, the kernel would tell us if it's 'reads' or 'writes'.
    node.bindings.append(.{
        .host_ptr = @ptrCast(ptr.?),
        .guest_offset = current_offset,
        .size = size,
        .is_output = true, // Simplified: always sync back for now
    }) catch return c.INVOKE_STATUS_ERROR;

    std.debug.print("[WASM Ext] Bound wire '{s}' to guest offset 0x{X}\n", .{ std.mem.span(name), current_offset });
    return c.INVOKE_STATUS_OK;
}

export fn tick(handle: abi.invoke_node_h) abi.invoke_status_t {
    const node: *WasmNode = @ptrCast(@alignCast(handle));
    const ctx = node.context;

    if (node.has_memory) {
        const data_ptr = c.wasmtime_memory_data(ctx, &node.memory);
        const base = data_ptr + node.guest_offset;
        
        // 1. O(1) SYNC IN: No string lookups!
        for (node.bindings.items) |b| {
            @memcpy(base[b.guest_offset .. b.guest_offset + b.size], b.host_ptr[0..b.size]);
        }

        // 2. CALL GUEST
        var func_val: c.wasmtime_extern_t = undefined;
        if (c.wasmtime_instance_export_get(ctx, &node.instance, "tick", 4, &func_val)) {
            var trap: ?*c.wasm_trap_t = null;
            const err = c.wasmtime_func_call(ctx, &func_val.of.func, null, 0, null, 0, &trap);
            if (err != null or trap != null) return c.INVOKE_STATUS_ERROR;
        }

        // 3. O(1) SYNC OUT: No string lookups!
        for (node.bindings.items) |b| {
            if (b.is_output) {
                @memcpy(b.host_ptr[0..b.size], base[b.guest_offset .. b.guest_offset + b.size]);
            }
        }
    }

    return c.INVOKE_STATUS_OK;
}

export fn reload_node(handle: abi.invoke_node_h, script_path: [*c]const u8) abi.invoke_status_t {
    _ = handle;
    _ = script_path;
    return c.INVOKE_STATUS_OK;
}

export fn add_trigger(handle: abi.invoke_node_h, event_name: [*c]const u8) abi.invoke_status_t {
    _ = handle;
    _ = event_name;
    return c.INVOKE_STATUS_OK;
}

export fn invoke_ext_init() abi.invoke_extension_t {
    return .{
        .create_node = create_node,
        .destroy_node = destroy_node,
        .bind_wire = bind_wire,
        .tick = tick,
        .reload_node = reload_node,
        .add_trigger = add_trigger,
    };
}
