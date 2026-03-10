const wires = @cImport({
    @cInclude("wires.h");
    @cInclude("physics_offsets.h");
});

// Export a function to return the buffer offset for the host to use.
var wire_buffer: [2048]u8 align(16) = undefined;

export fn get_wire_buffer() [*]u8 {
    return &wire_buffer;
}

export fn tick() void {
    // USE DYNAMIC OFFSETS: No more magic numbers!
    const stats_ptr: *wires.player_stats_t = @ptrCast(@alignCast(&wire_buffer[wires.OFFSET_stats]));
    const wind_ptr: *wires.environment_wind_t = @ptrCast(@alignCast(&wire_buffer[wires.OFFSET_environment_wind]));

    // Apply wind to X
    stats_ptr.x += wind_ptr.force;
    stats_ptr.health -= 2;
}
