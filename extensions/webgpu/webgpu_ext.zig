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

    pub fn init(allocator: std.mem.Allocator) !*WebGPUNode {
        const self = try allocator.create(WebGPUNode);
        self.allocator = allocator;

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

        std.debug.print("[WebGPU Ext] SOTA Massive Swarm Renderer ACTIVE.\n", .{});
        return self;
    }

    pub fn deinit(self: *WebGPUNode) void {
        wgpu.wgpuQueueRelease(self.queue);
        wgpu.wgpuDeviceRelease(self.device);
        wgpu.wgpuAdapterRelease(self.adapter);
        wgpu.wgpuInstanceRelease(self.instance);
        self.allocator.destroy(self);
    }

    pub fn tick(self: *WebGPUNode) void {
        _ = self;
        // In a real SOTA implementation, we would process GPU command wires here.
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

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, access: usize) abi.moontide_status_t {
    _ = handle; _ = name; _ = ptr; _ = access;
    return abi.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h) abi.moontide_status_t {
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
