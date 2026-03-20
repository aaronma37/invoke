const std = @import("std");
const core = @import("core");
const sandbox = core.sandbox;

const c = @cImport({
    @cInclude("wasmtime.h");
    @cInclude("moontide.h");
});

const abi = c;

var global_log_handler: ?abi.moontide_log_fn = null;
var global_poke_handler: ?abi.moontide_poke_fn = null;

const SyncBinding = struct {
    host_ptr: [*]u8,
    guest_offset: usize,
    size: usize,
    is_output: bool,
};

const WasmNode = struct {
    engine: *c.wasm_engine_t,
    store: *c.wasmtime_store_t,
    context: *c.wasmtime_context_t,
    module: ?*c.wasmtime_module_t,
    instance: ?c.wasmtime_instance_t,
    memory: ?c.wasmtime_memory_t,
    tick_func: ?c.wasmtime_func_t,
    
    name: []const u8,
    allocator: std.mem.Allocator,
    bindings: std.StringHashMap(SyncBinding),
    guest_offset: usize = 0,

    pub fn init(allocator: std.mem.Allocator, name_c: [*c]const u8, script_path: [*c]const u8) !*WasmNode {
        const self = try allocator.create(WasmNode);
        self.allocator = allocator;
        self.name = try allocator.dupe(u8, std.mem.span(name_c));
        self.bindings = std.StringHashMap(SyncBinding).init(allocator);
        self.module = null;
        self.instance = null;
        self.memory = null;
        self.tick_func = null;

        self.engine = c.wasm_engine_new() orelse return error.WasmInitFailed;
        self.store = c.wasmtime_store_new(self.engine, null, null) orelse return error.WasmInitFailed;
        self.context = c.wasmtime_store_context(self.store).?;

        const script_path_span = std.mem.span(script_path);
        if (std.mem.eql(u8, script_path_span, "none")) return self;

        const file_content = try std.fs.cwd().readFileAlloc(allocator, script_path_span, 10 * 1024 * 1024);
        defer allocator.free(file_content);

        var module_ptr: ?*c.wasmtime_module_t = null;
        const err = c.wasmtime_module_new(self.engine, file_content.ptr, file_content.len, &module_ptr);
        if (err != null) return error.WasmModuleFailed;
        self.module = module_ptr;

        var trap: ?*c.wasm_trap_t = null;
        var instance: c.wasmtime_instance_t = undefined;
        const inst_err = c.wasmtime_instance_new(self.context, self.module.?, null, 0, &instance, &trap);
        if (inst_err != null or trap != null) return error.WasmInstanceFailed;
        self.instance = instance;

        var item: c.wasmtime_extern_t = undefined;
        if (c.wasmtime_instance_export_get(self.context, &self.instance.?, "memory", 6, &item)) {
            if (item.kind == c.WASMTIME_EXTERN_MEMORY) {
                self.memory = item.of.memory;
            }
        }

        if (c.wasmtime_instance_export_get(self.context, &self.instance.?, "tick", 4, &item)) {
            if (item.kind == c.WASMTIME_EXTERN_FUNC) {
                self.tick_func = item.of.func;
            }
        }

        if (c.wasmtime_instance_export_get(self.context, &self.instance.?, "get_wire_buffer", 15, &item)) {
            if (item.kind == c.WASMTIME_EXTERN_FUNC) {
                var results: [1]c.wasmtime_val_t = undefined;
                _ = c.wasmtime_func_call(self.context, &item.of.func, null, 0, &results, 1, &trap);
                self.guest_offset = @intCast(results[0].of.i32);
            }
        }

        return self;
    }

    pub fn deinit(self: *WasmNode) void {
        var it = self.bindings.keyIterator();
        while (it.next()) |k| self.allocator.free(k.*);
        self.bindings.deinit();
        if (self.module) |m| c.wasmtime_module_delete(m);
        c.wasmtime_store_delete(self.store);
        c.wasm_engine_delete(self.engine);
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }
};

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.moontide_node_h {
    const node = WasmNode.init(std.heap.c_allocator, name, script_path) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.moontide_node_h) void {
    if (handle == null) return;
    const node: *WasmNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, schema: [*c]const u8, access: usize) abi.moontide_status_t {
    sandbox.checkPoints();
    if (handle == null) return c.MOONTIDE_STATUS_ERROR;
    const node: *WasmNode = @ptrCast(@alignCast(handle));
    const wire_name = std.mem.span(name);
    const schema_str = std.mem.span(schema);
    const host_ptr_bytes: [*]u8 = @ptrCast(ptr.?);
    const is_output = (access & 2 != 0);

    var current_wire_offset: usize = 0;
    var it = std.mem.tokenizeAny(u8, schema_str, ";");
    while (it.next()) |entry| {
        var parts = std.mem.tokenizeAny(u8, entry, ":");
        const f_name = parts.next() orelse continue;
        const f_type_raw = parts.next() orelse continue;

        var f_type = f_type_raw;
        var count: usize = 1;
        if (std.mem.indexOf(u8, f_type_raw, "[")) |idx| {
            f_type = f_type_raw[0..idx];
            const end = std.mem.indexOf(u8, f_type_raw, "]") orelse f_type_raw.len;
            count = std.fmt.parseInt(usize, f_type_raw[idx+1..end], 10) catch 1;
        }

        const base_size: usize = if (std.mem.eql(u8, f_type, "f32")) 4
                          else if (std.mem.eql(u8, f_type, "f64")) 8
                          else if (std.mem.eql(u8, f_type, "i32")) 4
                          else if (std.mem.eql(u8, f_type, "u32")) 4
                          else 1;
        const col_size = base_size * count;

        const full_name = std.fmt.allocPrint(node.allocator, "{s}_{s}", .{wire_name, f_name}) catch return c.MOONTIDE_STATUS_ERROR;
        
        if (node.bindings.getPtr(full_name)) |b| {
            b.host_ptr = host_ptr_bytes + current_wire_offset;
            b.is_output = b.is_output or is_output;
            node.allocator.free(full_name);
        } else {
            var guest_off: usize = 0;
            var bit = node.bindings.valueIterator();
            while (bit.next()) |b| {
                guest_off += (b.size + 15) & ~@as(usize, 15);
            }

            node.bindings.put(full_name, .{
                .host_ptr = host_ptr_bytes + current_wire_offset,
                .guest_offset = guest_off,
                .size = col_size,
                .is_output = is_output,
            }) catch return c.MOONTIDE_STATUS_ERROR;
        }

        current_wire_offset += col_size;
    }

    return c.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h) abi.moontide_status_t {
    if (handle == null) return c.MOONTIDE_STATUS_OK;
    const node: *WasmNode = @ptrCast(@alignCast(handle));
    if (node.instance == null or node.memory == null) return c.MOONTIDE_STATUS_OK;
    
    const ctx = node.context;
    const data_ptr = c.wasmtime_memory_data(ctx, &node.memory.?);
    const base = data_ptr + node.guest_offset;
    
    var it = node.bindings.valueIterator();
    while (it.next()) |b| {
        @memcpy(base[b.guest_offset .. b.guest_offset + b.size], b.host_ptr[0..b.size]);
    }

    if (node.tick_func) |f| {
        var trap: ?*c.wasm_trap_t = null;
        _ = c.wasmtime_func_call(ctx, &f, null, 0, null, 0, &trap);
    }

    it = node.bindings.valueIterator();
    while (it.next()) |b| {
        if (b.is_output) {
            @memcpy(b.host_ptr[0..b.size], base[b.guest_offset .. b.guest_offset + b.size]);
        }
    }

    return c.MOONTIDE_STATUS_OK;
}

export fn reload_node(handle: abi.moontide_node_h, script_path: [*c]const u8) abi.moontide_status_t {
    _ = handle; _ = script_path;
    return abi.MOONTIDE_STATUS_OK;
}

export fn add_trigger(handle: abi.moontide_node_h, event_name: [*c]const u8) abi.moontide_status_t {
    _ = handle; _ = event_name;
    return c.MOONTIDE_STATUS_OK;
}

export fn poll_events(handle: abi.moontide_node_h) bool {
    _ = handle;
    return true;
}

export fn set_log_handler(handler: abi.moontide_log_fn) void { _ = handler; }
export fn set_poke_handler(handler: abi.moontide_poke_fn) void { _ = handler; }
export fn set_orchestrator_handler(orch: ?*anyopaque) void { _ = orch; }

export fn moontide_ext_init() abi.moontide_extension_t {
    return .{
        .abi_version = abi.MOONTIDE_ABI_VERSION,
        .create_node = create_node,
        .destroy_node = destroy_node,
        .bind_wire = bind_wire,
        .tick = tick,
        .reload_node = reload_node,
        .add_trigger = add_trigger,
        .set_log_handler = set_log_handler,
        .set_poke_handler = set_poke_handler,
        .set_orchestrator_handler = set_orchestrator_handler,
        .poll_events = poll_events,
    };
}
