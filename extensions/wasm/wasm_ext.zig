const std = @import("std");

const c = @cImport({
    @cInclude("wasmtime.h");
    @cInclude("invoke_abi.h");
});

const abi = c;

var global_log_handler: ?abi.invoke_log_fn = null;

const WasmNode = struct {
    engine: ?*c.wasm_engine_t,
    store: ?*c.wasmtime_store_t,
    context: ?*c.wasmtime_context_t,
    module: ?*c.wasmtime_module_t,
    instance: c.wasmtime_instance_t,
    name: []const u8,
    
    // CACHED EXPORTS
    memory: c.wasmtime_memory_t,
    has_memory: bool = false,
    tick_func: ?c.wasmtime_func_t = null,
    
    guest_offset: usize = 0,
    allocator: std.mem.Allocator,
    
    // HOT LOOP OPTIMIZATION: 
    // We use a flat array of bindings instead of a HashMap.
    // O(1) performance during tick.
    bindings: std.ArrayList(SyncBinding),

    const SyncBinding = struct {
        name: []const u8,
        host_ptr: [*]u8,
        guest_offset: usize,
        size: usize,
        is_output: bool,
    };

    pub fn init(allocator: std.mem.Allocator, name_c: [*c]const u8, script_path: [*c]const u8) !*WasmNode {
        const self = try allocator.create(WasmNode);
        self.allocator = allocator;
        self.name = try allocator.dupe(u8, std.mem.span(name_c));
        self.bindings = std.ArrayList(SyncBinding).init(allocator);
        
        self.engine = c.wasm_engine_new() orelse {
            std.debug.print("[WASM Ext] wasm_engine_new failed\n", .{});
            return error.WasmEngineNewFailed;
        };
        self.store = c.wasmtime_store_new(self.engine, null, null) orelse {
            std.debug.print("[WASM Ext] wasmtime_store_new failed\n", .{});
            return error.WasmStoreNewFailed;
        };
        self.context = c.wasmtime_store_context(self.store);

        const wasm_bytes = std.fs.cwd().readFileAlloc(allocator, std.mem.span(script_path), 10 * 1024 * 1024) catch |err| {
            std.debug.print("[WASM Ext] Failed to read script {s}: {any}\n", .{ script_path, err });
            return err;
        };
        defer allocator.free(wasm_bytes);

        var err: ?*c.wasmtime_error_t = null;
        err = c.wasmtime_module_new(self.engine, wasm_bytes.ptr, wasm_bytes.len, &self.module);
        if (err != null) {
            std.debug.print("[WASM Ext] wasmtime_module_new failed\n", .{});
            return error.WasmModuleNewFailed;
        }

        // CREATE HOST IMPORTS (invoke_log)
        // Signature: (i32, i32, i32) -> ()
        var params_arr: [3]*c.wasm_valtype_t = undefined;
        params_arr[0] = c.wasm_valtype_new(c.WASM_I32).?;
        params_arr[1] = c.wasm_valtype_new(c.WASM_I32).?;
        params_arr[2] = c.wasm_valtype_new(c.WASM_I32).?;
        
        var param_vec: c.wasm_valtype_vec_t = undefined;
        c.wasm_valtype_vec_new(&param_vec, 3, @ptrCast(&params_arr));
        
        var result_vec: c.wasm_valtype_vec_t = undefined;
        c.wasm_valtype_vec_new_empty(&result_vec);
        
        const functype = c.wasm_functype_new(&param_vec, &result_vec);
        
        var log_func: c.wasmtime_func_t = undefined;
        c.wasmtime_func_new(self.context, functype, @ptrCast(&wasm_log_callback), self, null, &log_func);
        c.wasm_functype_delete(functype);

        // In a real project, we'd use wasmtime_linker to handle imports properly.
        const imports: [1]c.wasmtime_extern_t = .{ .{ .kind = c.WASMTIME_EXTERN_FUNC, .of = .{ .func = log_func } } };

        var trap: ?*c.wasm_trap_t = null;
        err = c.wasmtime_instance_new(self.context, self.module, &imports, 1, &self.instance, &trap);
        if (err != null or trap != null) {
            std.debug.print("[WASM Ext] wasmtime_instance_new failed (err: {?}, trap: {?})\n", .{ err, trap });
            return error.WasmInstantiateFailed;
        }

        var export_val: c.wasmtime_extern_t = undefined;
        if (c.wasmtime_instance_export_get(self.context, &self.instance, "memory", 6, &export_val)) {
            if (export_val.kind == c.WASMTIME_EXTERN_MEMORY) {
                self.memory = export_val.of.memory;
                self.has_memory = true;
            }
        }

        if (c.wasmtime_instance_export_get(self.context, &self.instance, "tick", 4, &export_val)) {
            if (export_val.kind == c.WASMTIME_EXTERN_FUNC) {
                self.tick_func = export_val.of.func;
            }
        }

        if (c.wasmtime_instance_export_get(self.context, &self.instance, "get_wire_buffer", 15, &export_val)) {
            var results: [1]c.wasmtime_val_t = undefined;
            err = c.wasmtime_func_call(self.context, &export_val.of.func, null, 0, &results, 1, &trap);
            if (err == null and trap == null) {
                self.guest_offset = @intCast(results[0].of.i32);
                // std.debug.print("[WASM Ext] Guest wire buffer offset: 0x{X}\n", .{ self.guest_offset });
            } else {
                std.debug.print("[WASM Ext Error] get_wire_buffer call failed\n", .{});
            }
        } else {
            std.debug.print("[WASM Ext Error] 'get_wire_buffer' export not found!\n", .{});
        }

        return self;
    }

    pub fn deinit(self: *WasmNode) void {
        for (self.bindings.items) |b| {
            self.allocator.free(b.name);
        }
        self.bindings.deinit();
        if (self.module) |m| c.wasmtime_module_delete(m);
        if (self.store) |s| c.wasmtime_store_delete(s);
        if (self.engine) |e| c.wasm_engine_delete(e);
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }
};

fn wasm_log_callback(
    env: ?*anyopaque,
    caller: ?*c.wasmtime_caller_t,
    args: [*c]const c.wasmtime_val_t,
    nargs: usize,
    results: [*c]c.wasmtime_val_t,
    nresults: usize
) callconv(.C) ?*c.wasm_trap_t {
    _ = results; _ = nresults; _ = nargs;
    const self: *WasmNode = @ptrCast(@alignCast(env.?));
    const level: abi.invoke_log_level_t = @intCast(args[0].of.i32);
    const ptr: usize = @intCast(args[1].of.i32);
    const len: usize = @intCast(args[2].of.i32);

    const ctx = c.wasmtime_caller_context(caller);
    const data_ptr = c.wasmtime_memory_data(ctx, &self.memory);
    const message = data_ptr[ptr .. ptr + len];

    if (global_log_handler) |log| {
        // Null-terminate for C-ABI safety
        var buf: [1024]u8 = undefined;
        const safe_len = @min(message.len, 1023);
        @memcpy(buf[0..safe_len], message[0..safe_len]);
        buf[safe_len] = 0;
        log.?(level, self.name.ptr, &buf);
    }

    return null;
}

// --- ABI IMPLEMENTATION ---

export fn set_log_handler(handler: abi.invoke_log_fn) void {
    global_log_handler = handler;
}

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.invoke_node_h {
    const node = WasmNode.init(std.heap.c_allocator, name, script_path) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.invoke_node_h) void {
    const node: *WasmNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.invoke_node_h, name: [*c]const u8, ptr: ?*anyopaque, access: usize) abi.invoke_status_t {
    const node: *WasmNode = @ptrCast(@alignCast(handle));
    const wire_name = std.mem.span(name);
    const host_ptr_bytes: [*]u8 = @ptrCast(ptr.?);
    const is_output = (access & 2 != 0);

    // DEDUPLICATE BY NAME: Pointers rotate every frame!
    for (node.bindings.items) |*b| {
        if (std.mem.eql(u8, b.name, wire_name)) {
            b.host_ptr = host_ptr_bytes;
            b.is_output = b.is_output or is_output;
            return c.INVOKE_STATUS_OK;
        }
    }

    // New binding
    var current_offset: usize = 0;
    for (node.bindings.items) |b| {
        current_offset += (b.size + 15) & ~@as(usize, 15);
    }

    const size: usize = if (std.mem.indexOf(u8, wire_name, "stats") != null) 12 else 8;

    node.bindings.append(.{
        .name = node.allocator.dupe(u8, wire_name) catch return c.INVOKE_STATUS_ERROR,
        .host_ptr = host_ptr_bytes,
        .guest_offset = current_offset,
        .size = size,
        .is_output = is_output,
    }) catch return c.INVOKE_STATUS_ERROR;

    // std.debug.print("[WASM Ext] Bound wire '{s}' to guest offset 0x{X} (Output: {any})\n", .{ wire_name, current_offset, is_output });
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
        if (node.tick_func) |f| {
            var trap: ?*c.wasm_trap_t = null;
            const err = c.wasmtime_func_call(ctx, &f, null, 0, null, 0, &trap);
            if (err != null or trap != null) {
                std.debug.print("[WASM Ext Error] Tick failed (err: {?}, trap: {?})\n", .{ err, trap });
                return c.INVOKE_STATUS_ERROR;
            }
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
        .set_log_handler = set_log_handler,
    };
}
