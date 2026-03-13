const std = @import("std");
const core = @import("core");
const sandbox = core.sandbox;
const Orchestrator = core.Orchestrator;
const posix = std.posix;

const abi = @cImport({
    @cInclude("moontide.h");
});

var global_orch: ?*Orchestrator = null;

const INCOMING_SIZE = 16384; // 16KB Ring Buffer
const MAX_OUTGOING = 16;
const MAX_PACKET = 1024;

const OutgoingPacket = extern struct {
    addr: u32,
    port: u16,
    _pad: u16 = 0,
    len: u32,
    data: [MAX_PACKET]u8,
};

const IncomingHeader = extern struct {
    head: u32,
    tail: u32,
};

const NetworkNode = struct {
    allocator: std.mem.Allocator,
    sockfd: posix.socket_t,
    
    // Wire pointers
    in_header: ?*IncomingHeader = null,
    in_data: ?[*]u8 = null,
    out_wire: ?[*]OutgoingPacket = null,

    pub fn init(allocator: std.mem.Allocator) !*NetworkNode {
        const self = try allocator.create(NetworkNode);
        self.allocator = allocator;
        
        // 1. Create a non-blocking UDP socket
        self.sockfd = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
        
        // Set non-blocking
        const flags = try posix.fcntl(self.sockfd, posix.F.GETFL, 0);
        _ = try posix.fcntl(self.sockfd, posix.F.SETFL, flags | posix.SOCK.NONBLOCK);

        // Bind to a random port or 8080 by default
        const address = posix.sockaddr.in{
            .family = posix.AF.INET,
            .port = std.mem.nativeToBig(u16, 8080),
            .addr = 0, // INADDR_ANY
        };
        
        posix.bind(self.sockfd, @ptrCast(&address), @sizeOf(posix.sockaddr.in)) catch |err| {
            std.debug.print("[TidePool] Bind failed (port 8080): {any}\n", .{err});
        };

        std.debug.print("[TidePool] Socket ACTIVE (UDP Port 8080).\n", .{});
        return self;
    }

    pub fn deinit(self: *NetworkNode) void {
        posix.close(self.sockfd);
        self.allocator.destroy(self);
    }

    pub fn receivePackets(self: *NetworkNode) void {
        const header = self.in_header orelse return;
        const buffer = self.in_data orelse return;

        var src_addr: posix.sockaddr.in = undefined;
        var src_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.in);
        
        var packet_buf: [MAX_PACKET]u8 = undefined;

        while (true) {
            const bytes_read = posix.recvfrom(self.sockfd, &packet_buf, 0, @ptrCast(&src_addr), &src_addr_len) catch |err| {
                if (err == error.WouldBlock) break;
                std.debug.print("[TidePool] recvfrom error: {any}\n", .{err});
                break;
            };

            if (bytes_read > 0) {
                // Pour into Ring Buffer
                // Format: [Len:u16][Addr:u32][Port:u16][Data:...]
                const total_size = 2 + 4 + 2 + bytes_read;
                
                // Check if we have space (simple tail/head check)
                const next_head = (header.head + @as(u32, @intCast(total_size))) % INCOMING_SIZE;
                if (next_head == header.tail) {
                    std.debug.print("[TidePool] Ring Buffer FULL. Dropping packet.\n", .{});
                    continue;
                }

                // Copy Len
                const len_u16 = @as(u16, @intCast(bytes_read));
                self.writeToRing(buffer, &header.head, std.mem.asBytes(&len_u16));
                
                // Copy Addr/Port
                self.writeToRing(buffer, &header.head, std.mem.asBytes(&src_addr.addr));
                self.writeToRing(buffer, &header.head, std.mem.asBytes(&src_addr.port));

                // Copy Data
                self.writeToRing(buffer, &header.head, packet_buf[0..bytes_read]);
            }
        }
    }

    fn writeToRing(self: *NetworkNode, buffer: [*]u8, head: *u32, data: []const u8) void {
        _ = self;
        for (data) |byte| {
            buffer[head.*] = byte;
            head.* = (head.* + 1) % INCOMING_SIZE;
        }
    }

    pub fn sendPackets(self: *NetworkNode) void {
        const out_ptr = self.out_wire orelse return;
        
        for (0..MAX_OUTGOING) |i| {
            const pkt = &out_ptr[i];
            if (pkt.len > 0) {
                const dest_addr = posix.sockaddr.in{
                    .family = posix.AF.INET,
                    .port = pkt.port,
                    .addr = pkt.addr,
                };

                _ = posix.sendto(self.sockfd, pkt.data[0..pkt.len], 0, @ptrCast(&dest_addr), @sizeOf(posix.sockaddr.in)) catch |err| {
                    std.debug.print("[TidePool] sendto error: {any}\n", .{err});
                };

                // Clear command
                pkt.len = 0;
            }
        }
    }
};

// --- ABI IMPLEMENTATION ---

export fn create_node(name: [*c]const u8, script_path: [*c]const u8) abi.moontide_node_h {
    _ = name; _ = script_path;
    const node = NetworkNode.init(std.heap.c_allocator) catch return null;
    return @ptrCast(node);
}

export fn destroy_node(handle: abi.moontide_node_h) void {
    const node: *NetworkNode = @ptrCast(@alignCast(handle));
    node.deinit();
}

export fn bind_wire(handle: abi.moontide_node_h, name: [*c]const u8, ptr: ?*anyopaque, access: usize) abi.moontide_status_t {
    const node: *NetworkNode = @ptrCast(@alignCast(handle));
    const wire_name = std.mem.span(name);
    _ = access;

    if (std.mem.eql(u8, wire_name, "network.incoming")) {
        node.in_header = @ptrCast(@alignCast(ptr));
        // Data follows head/tail (8 bytes)
        const base: [*]u8 = @ptrCast(ptr.?);
        node.in_data = base + 8;
    } else if (std.mem.eql(u8, wire_name, "network.outgoing")) {
        node.out_wire = @ptrCast(@alignCast(ptr));
    }

    return abi.MOONTIDE_STATUS_OK;
}

export fn tick(handle: abi.moontide_node_h) abi.moontide_status_t {
    const node: *NetworkNode = @ptrCast(@alignCast(handle));
    node.receivePackets();
    node.sendPackets();
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
