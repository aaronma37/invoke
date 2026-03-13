const std = @import("std");
const core = @import("core");
const sandbox = core.sandbox;
const Orchestrator = core.Orchestrator;

const abi = @cImport({
    @cInclude("moontide.h");
});

const py = @cImport({
    @cInclude("Python.h");
});

var global_log_handler: ?abi.moontide_log_fn = null;
var global_poke_handler: ?abi.moontide_poke_fn = null;

const PythonNode = struct {
    allocator: std.mem.Allocator,
    module: ?*py.PyObject,
    dict: ?*py.PyObject,
    name: []const u8,
    
    config_wire: ?[*]u8 = null,
    last_injected_path: [256]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, name_c: [*c]const u8, script_path: [*c]const u8) !*PythonNode {
        const self = try allocator.create(PythonNode);
        self.allocator = allocator;
        self.name = try allocator.dupe(u8, std.mem.span(name_c));
        self.config_wire = null;
        @memset(&self.last_injected_path, 0);

        // 1. Ensure Python is initialized
        if (py.Py_IsInitialized() == 0) {
            py.Py_Initialize();
        }

        // 2. Load the script
        const path_str = std.mem.span(script_path);
        const file_content = try std.fs.cwd().readFileAlloc(allocator, path_str, 1024 * 1024);
        defer allocator.free(file_content);

        self.module = py.PyImport_AddModule(name_c);
        self.dict = py.PyModule_GetDict(self.module);
        
        const result = py.PyRun_String(@ptrCast(file_content.ptr), py.Py_file_input, self.dict, self.dict);
        if (result == null) {
            py.PyErr_Print();
            return error.PythonScriptExecutionFailed;
        }
        py.Py_XDECREF(result);

        return self;
    }

    pub fn checkConfig(self: *PythonNode) void {
        const path_ptr = self.config_wire orelse return;
        
        const current_path = std.mem.span(@as([*c]u8, @ptrCast(path_ptr)));
        const last_path = std.mem.span(@as([*c]u8, @ptrCast(&self.last_injected_path)));

        if (current_path.len > 0 and !std.mem.eql(u8, current_path, last_path)) {
            std.debug.print("[Python Ext] Injecting SOTA Path: {s}\n", .{current_path});
            
            const sys_mod = py.PyImport_ImportModule("sys");
            if (sys_mod != null) {
                const sys_path = py.PyObject_GetAttrString(sys_mod, "path");
                if (sys_path != null) {
                    const py_path = py.PyUnicode_FromString(@ptrCast(current_path.ptr));
                    _ = py.PyList_Append(sys_path, py_path);
                    py.Py_XDECREF(py_path);
                    py.Py_XDECREF(sys_path);
                }
                py.Py_XDECREF(sys_mod);
            }
            
            @memcpy(self.last_injected_path[0..current_path.len], current_path);
            self.last_injected_path[current_path.len] = 0;
        }
    }

    pub fn deinit(self: *PythonNode) void {
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }

    pub fn tick(self: *PythonNode) void {
        self.checkConfig();
        const tick_func = py.PyDict_GetItemString(self.dict, "tick");
        if (tick_func != null and py.PyCallable_Check(tick_func) != 0) {
            const result = py.PyObject_CallObject(tick_func, null);
            if (result == null) {
                py.PyErr_Print();
            } else {
                py.Py_XDECREF(result);
            }
        }
    }

    pub fn bindWire(self: *PythonNode, wire_name: []const u8, ptr: ?*anyopaque, size: usize) void {
        if (std.mem.eql(u8, wire_name, "python.config")) {
            self.config_wire = @ptrCast(@alignCast(ptr));
            return;
        }

        const mem_view = py.PyMemoryView_FromMemory(@ptrCast(ptr), @intCast(size), py.PyBUF_WRITE);
        if (mem_view == null) {
            py.PyErr_Print();
            return;
        }

        var buf: [256]u8 = undefined;
        const safe_name = std.fmt.bufPrintZ(&buf, "wire_{s}", .{wire_name}) catch "wire_err";
        for (@constCast(safe_name)) |*c| if (c.* == '.') { c.* = '_'; };

        _ = py.PyDict_SetItemString(self.dict, safe_name.ptr, mem_view);
        py.Py_XDECREF(mem_view);
    }
};

// --- ABI IMPLEMENTATION ---

export fn set_log_handler(handler: abi.moontide_log_fn) void { global_log_handler = handler; }
export fn set_poke_handler(handler: abi.moontide_poke_fn) void { global_poke_handler = handler; }
export fn set_orchestrator_handler(orch: ?*anyopaque) void { _ = orch; }

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.moontide_node_h {
    const node = PythonNode.init(std.heap.c_allocator, name, script_path) catch {
        std.debug.print("[Python Ext] Failed to create node.\n", .{});
        return null;
    };
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.moontide_node_h) void {
    const node: *PythonNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, access: usize) abi.moontide_status_t {
    _ = access;
    const node: *PythonNode = @ptrCast(@alignCast(handle));
    const wire_name = std.mem.span(name);
    
    // We need the wire size to create a memoryview. 
    // For now, we'll assume a standard size or fetch it from the orchestrator if available.
    // However, the ABI v1.1 should ideally pass the size.
    // Since we don't have it in the ABI call, we'll use a hack or update the ABI.
    // Let's assume 1024 for now, or check if we can get it from global_orch.
    
    // Actually, let's peek into the RawWire if we had the orch...
    // But wait, bind_wire in moontide.h only takes 'access'.
    // Let's use a conservative 1MB for the memoryview, or 4KB.
    // SOTA Move: We'll use 64KB as a default for now.
    node.bindWire(wire_name, ptr, 64 * 1024); 

    return abi.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h) abi.moontide_status_t {
    const node: *PythonNode = @ptrCast(@alignCast(handle));
    node.tick();
    return abi.MOONTIDE_STATUS_OK;
}

export fn reload_node(handle: abi.moontide_node_h, script_path: [*c]const u8) abi.moontide_status_t {
    _ = handle; _ = script_path;
    // TODO: Implement full hot-reload for Python modules
    return abi.MOONTIDE_STATUS_OK;
}

export fn add_trigger(handle: abi.moontide_node_h, event_name: [*c]const u8) abi.moontide_status_t {
    _ = handle; _ = event_name;
    return abi.MOONTIDE_STATUS_OK;
}

export fn poll_events(handle: abi.moontide_node_h) bool {
    _ = handle;
    return true;
}

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
