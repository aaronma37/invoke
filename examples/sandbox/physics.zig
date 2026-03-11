const moontide = @import("moontide.zig");

// Hardcoded for the sandbox topology
const OFFSET_stats = 0x0;
const OFFSET_environment_wind = 0x10;

pub const player_stats_t = extern struct {
    x: f32,
    y: f32,
    health: i32,
};

pub const environment_wind_t = extern struct {
    force: f32,
    direction: f32,
};

export fn tick() void {
    const stats = moontide.getWire(player_stats_t, OFFSET_stats);
    const wind = moontide.getWire(environment_wind_t, OFFSET_environment_wind);

    stats.x += wind.force;
    stats.health -= 2;

    if (stats.health < 50) {
        moontide.info("Player health is low! Poking damage system.");
        moontide.poke("on_collision");
    }
}
