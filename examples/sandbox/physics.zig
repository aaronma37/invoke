const invoke = @import("invoke.zig");

export fn tick() void {
    const stats = invoke.getWire(invoke.wires.player_stats_t, "stats");
    const wind = invoke.getWire(invoke.wires.environment_wind_t, "environment_wind");

    // Logic is now clean and type-safe!
    stats.x += wind.force;
    stats.health -= 2;
}
