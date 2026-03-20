const std = @import("std");
const core = @import("core");
const sandbox = core.sandbox;
const Orchestrator = core.Orchestrator;

const abi = @cImport({
    @cInclude("moontide.h");
});

const wgpu = @cImport({
    @cInclude("webgpu.h");
    @cInclude("wgpu.h");
});

var global_orch: ?*Orchestrator = null;

const WebGPUNode = struct {
    allocator: std.mem.Allocator,
    instance: wgpu.WGPUInstance,
    adapter: wgpu.WGPUAdapter,
    device: wgpu.WGPUDevice,
    queue: wgpu.WGPUQueue,
    
    // VRAM Wire
    reservoir_ptr: ?[*]f32 = null,
    vram_buffer: wgpu.WGPUBuffer = null,
    
    const NEURON_COUNT: usize = 1048576;
    const BUFFER_SIZE: usize = NEURON_COUNT * 4;

    pub fn init(allocator: std.mem.Allocator) !*WebGPUNode {
        const self = try allocator.create(WebGPUNode);
        self.allocator = allocator;
        self.reservoir_ptr = null;

        // 1. Create WebGPU Instance
        const instance_desc = wgpu.WGPUInstanceDescriptor{
            .nextInChain = null,
        };
        self.instance = wgpu.wgpuCreateInstance(&instance_desc) orelse return error.WGPUInstanceFailed;

        // 2. Request Adapter (GPU)
        const adapter_options = wgpu.WGPURequestAdapterOptions{
            .nextInChain = null,
            .compatibleSurface = null,
            .powerPreference = wgpu.WGPUPowerPreference_HighPerformance,
            .backendType = wgpu.WGPUBackendType_Vulkan,
            .forceFallbackAdapter = 0, // false in C-style bool
        };
        
        // Synchronous wrapper for requestAdapter (simulated for simplicity)
        var adapter: ?wgpu.WGPUAdapter = null;
        const OnAdapterRequest = struct {
            fn callback(status: wgpu.WGPURequestAdapterStatus, res: wgpu.WGPUAdapter, msg: [*c]const u8, userdata: ?*anyopaque) callconv(.C) void {
                _ = msg;
                if (status == wgpu.WGPURequestAdapterStatus_Success) {
                    const ptr = @as(*?wgpu.WGPUAdapter, @ptrCast(@alignCast(userdata.?)));
                    ptr.* = res;
                }
            }
        };
        wgpu.wgpuInstanceRequestAdapter(self.instance, &adapter_options, OnAdapterRequest.callback, &adapter);
        self.adapter = adapter orelse return error.WGPUAdapterFailed;

        // 3. Request Device
        const device_desc = wgpu.WGPUDeviceDescriptor{
            .nextInChain = null,
            .label = "Moontide SOTA Device",
            .requiredFeatureCount = 0,
            .requiredFeatures = null,
            .requiredLimits = null,
            .defaultQueue = wgpu.WGPUQueueDescriptor{
                .nextInChain = null,
                .label = "Main Queue",
            },
            .deviceLostCallback = null,
            .deviceLostUserdata = null,
        };
        
        var device: ?wgpu.WGPUDevice = null;
        const OnDeviceRequest = struct {
            fn callback(status: wgpu.WGPURequestDeviceStatus, res: wgpu.WGPUDevice, msg: [*c]const u8, userdata: ?*anyopaque) callconv(.C) void {
                _ = msg;
                if (status == wgpu.WGPURequestDeviceStatus_Success) {
                    const ptr = @as(*?wgpu.WGPUDevice, @ptrCast(@alignCast(userdata.?)));
                    ptr.* = res;
                }
            }
        };
        wgpu.wgpuAdapterRequestDevice(self.adapter, &device_desc, OnDeviceRequest.callback, &device);
        self.device = device orelse return error.WGPUDeviceFailed;

        self.queue = wgpu.wgpuDeviceGetQueue(self.device);

        // 4. Create VRAM Buffer
        const buffer_desc = wgpu.WGPUBufferDescriptor{
            .nextInChain = null,
            .label = "Reservoir VRAM Wire",
            .usage = wgpu.WGPUBufferUsage_CopyDst | wgpu.WGPUBufferUsage_Storage,
            .size = BUFFER_SIZE,
            .mappedAtCreation = 0,
        };
        self.vram_buffer = wgpu.wgpuDeviceCreateBuffer(self.device, &buffer_desc);

        std.debug.print("[WebGPU Ext] VRAM Wire Initialized ({} MB on GPU).\n", .{BUFFER_SIZE / 1024 / 1024});
        return self;
    }

    pub fn deinit(self: *WebGPUNode) void {
        if (self.vram_buffer != null) wgpu.wgpuBufferRelease(self.vram_buffer);
        wgpu.wgpuQueueRelease(self.queue);
        wgpu.wgpuDeviceRelease(self.device);
        wgpu.wgpuAdapterRelease(self.adapter);
        wgpu.wgpuInstanceRelease(self.instance);
        self.allocator.destroy(self);
    }

    pub fn bind_wire(self: *WebGPUNode, name: [*c]const u8, ptr: ?*anyopaque) void {
        const wire_name = std.mem.span(name);
        if (std.mem.eql(u8, wire_name, "reservoir")) {
            self.reservoir_ptr = @ptrCast(@alignCast(ptr.?));
        }
    }

    pub fn tick(self: *WebGPUNode) void {
        if (self.reservoir_ptr) |ptr| {
            // Upload 1M floats to GPU VRAM every pulse
            wgpu.wgpuQueueWriteBuffer(self.queue, self.vram_buffer, 0, ptr, BUFFER_SIZE);
        }
    }
};

// --- ABI IMPLEMENTATION ---

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.moontide_node_h {
    _ = name; _ = script_path;
    const node = WebGPUNode.init(std.heap.c_allocator) catch |err| {
        std.debug.print("[WebGPU Ext] Init failed: {any}\n", .{err});
        return null;
    };
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.moontide_node_h) void {
    const node: *WebGPUNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, schema: [*c]const u8, access: usize) abi.moontide_status_t {
    _ = schema; _ = access;
    if (handle == null) return abi.MOONTIDE_STATUS_ERROR;
    const node: *WebGPUNode = @ptrCast(@alignCast(handle));
    node.bind_wire(name, ptr);
    return abi.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h, pulse_count: u64) abi.moontide_status_t {
    _ = pulse_count;
    if (handle == null) return abi.MOONTIDE_STATUS_ERROR;
    const node: *WebGPUNode = @ptrCast(@alignCast(handle));
    node.tick();
    return abi.MOONTIDE_STATUS_OK;
}

export fn reload_node(handle: abi.moontide_node_h, script_path: [*c]const u8) abi.moontide_status_t {
    _ = handle; _ = script_path;
    return abi.MOONTIDE_STATUS_OK;
}

export fn add_trigger(handle: abi.moontide_node_h, event_name: [*c]const u8) abi.moontide_status_t {
    _ = handle; _ = event_name;
    return abi.MOONTIDE_STATUS_OK;
}

export fn set_log_handler(handler: abi.moontide_log_fn) void { _ = handler; }
export fn set_poke_handler(handler: abi.moontide_poke_fn) void { _ = handler; }
export fn set_orchestrator_handler(orch: ?*anyopaque) void {
    global_orch = @ptrCast(@alignCast(orch));
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
