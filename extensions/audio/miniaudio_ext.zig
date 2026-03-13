const std = @import("std");
const core = @import("core");
const sandbox = core.sandbox;
const Orchestrator = core.Orchestrator;

const abi = @cImport({
    @cInclude("moontide.h");
});

const ma = @cImport({
    @cInclude("miniaudio.h");
});

var global_orch: ?*Orchestrator = null;

const MAX_SOUNDS = 32;
const MAX_COMMANDS = 16;

const AudioCommand = extern struct {
    id: u32,
    volume: f32,
    pitch: f32,
};

const AudioNode = struct {
    allocator: std.mem.Allocator,
    engine: ma.ma_engine,
    sounds: [MAX_SOUNDS]?ma.ma_sound,
    
    // Wire pointers
    play_wire: ?[*]AudioCommand = null,
    load_wire: ?[*]u8 = null, // Path wire (256 bytes per path)

    pub fn init(allocator: std.mem.Allocator) !*AudioNode {
        const self = try allocator.create(AudioNode);
        self.allocator = allocator;
        
        var config = ma.ma_engine_config_init();
        if (ma.ma_engine_init(&config, &self.engine) != ma.MA_SUCCESS) {
            std.debug.print("[Audio Ext] Failed to initialize miniaudio engine.\n", .{});
            return error.AudioInitFailed;
        }

        for (0..MAX_SOUNDS) |i| self.sounds[i] = null;
        
        std.debug.print("[Audio Ext] Miniaudio Engine Initialized (Moontide Vocal Cords ACTIVE).\n", .{});
        return self;
    }

    pub fn deinit(self: *AudioNode) void {
        for (0..MAX_SOUNDS) |i| {
            if (self.sounds[i]) |*s| ma.ma_sound_uninit(s);
        }
        ma.ma_engine_uninit(&self.engine);
        self.allocator.destroy(self);
    }

    pub fn processCommands(self: *AudioNode) void {
        const cmd_ptr = self.play_wire orelse return;
        
        for (0..MAX_COMMANDS) |i| {
            const cmd = &cmd_ptr[i];
            if (cmd.id != 0) {
                const sound_idx = cmd.id - 1;
                if (sound_idx < MAX_SOUNDS) {
                    if (self.sounds[sound_idx]) |*s| {
                        ma.ma_sound_set_volume(s, cmd.volume);
                        ma.ma_sound_set_pitch(s, cmd.pitch);
                        _ = ma.ma_sound_start(s);
                    }
                }
                // CLEAR the command after processing
                cmd.id = 0;
            }
        }
    }

    pub fn checkLoadRequests(self: *AudioNode) void {
        const path_ptr = self.load_wire orelse return;
        
        for (0..MAX_SOUNDS) |i| {
            const path_base = path_ptr + (i * 256);
            if (path_base[0] != 0 and self.sounds[i] == null) {
                // New path detected! Load it.
                var sound: ma.ma_sound = undefined;
                const path_c = @as([*c]const u8, @ptrCast(path_base));
                
                if (ma.ma_sound_init_from_file(&self.engine, path_c, 0, null, null, &sound) == ma.MA_SUCCESS) {
                    self.sounds[i] = sound;
                    std.debug.print("[Audio Ext] Loaded Sound [{d}]: {s}\n", .{ i + 1, std.mem.span(path_c) });
                } else {
                    std.debug.print("[Audio Ext] Failed to load sound: {s}\n", .{ std.mem.span(path_c) });
                    // Zero out path to prevent infinite retries
                    path_base[0] = 0;
                }
            }
        }
    }
};

// --- ABI IMPLEMENTATION ---

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.moontide_node_h {
    _ = name; _ = script_path;
    const node = AudioNode.init(std.heap.c_allocator) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.moontide_node_h) void {
    const node: *AudioNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, access: usize) abi.moontide_status_t {
    const node: *AudioNode = @ptrCast(@alignCast(handle));
    const wire_name = std.mem.span(name);
    _ = access;

    if (std.mem.eql(u8, wire_name, "audio.play")) {
        node.play_wire = @ptrCast(@alignCast(ptr));
    } else if (std.mem.eql(u8, wire_name, "audio.load")) {
        node.load_wire = @ptrCast(@alignCast(ptr));
    }

    return abi.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h) abi.moontide_status_t {
    const node: *AudioNode = @ptrCast(@alignCast(handle));
    node.checkLoadRequests();
    node.processCommands();
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
