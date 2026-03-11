const moontide = @import("moontide.zig");

// We'll use a fixed size for the example
const MAX_BOIDS = 1000;

pub const SwarmWire = extern struct {
    count: i32,
    px: [MAX_BOIDS]f32,
    py: [MAX_BOIDS]f32,
    vx: [MAX_BOIDS]f32,
    vy: [MAX_BOIDS]f32,
};

// Offsets are calculated by the kernel
const OFFSET_SWARM = 0x0;

export fn tick() void {
    const swarm = moontide.getWire(SwarmWire, OFFSET_SWARM);
    
    const visual_range: f32 = 40.0;
    const min_distance: f32 = 10.0;
    const cohesion_factor: f32 = 0.005;
    const separation_factor: f32 = 0.05;
    const alignment_factor: f32 = 0.05;

    var i: usize = 0;
    while (i < @as(usize, @intCast(swarm.count))) : (i += 1) {
        var centerX: f32 = 0;
        var centerY: f32 = 0;
        var moveX: f32 = 0;
        var moveY: f32 = 0;
        var avgVX: f32 = 0;
        var avgVY: f32 = 0;
        var neighbors: i32 = 0;

        var j: usize = 0;
        while (j < @as(usize, @intCast(swarm.count))) : (j += 1) {
            if (i == j) continue;

            const dx = swarm.px[i] - swarm.px[j];
            const dy = swarm.py[i] - swarm.py[j];
            const dist = @sqrt(dx*dx + dy*dy);

            if (dist < visual_range) {
                centerX += swarm.px[j];
                centerY += swarm.py[j];
                avgVX += swarm.vx[j];
                avgVY += swarm.vy[j];
                neighbors += 1;

                if (dist < min_distance) {
                    moveX += dx;
                    moveY += dy;
                }
            }
        }

        if (neighbors > 0) {
            centerX /= @as(f32, @floatFromInt(neighbors));
            centerY /= @as(f32, @floatFromInt(neighbors));
            avgVX /= @as(f32, @floatFromInt(neighbors));
            avgVY /= @as(f32, @floatFromInt(neighbors));

            swarm.vx[i] += (centerX - swarm.px[i]) * cohesion_factor + 
                           (avgVX - swarm.vx[i]) * alignment_factor;
            swarm.vy[i] += (centerY - swarm.py[i]) * cohesion_factor + 
                           (avgVY - swarm.vy[i]) * alignment_factor;
        }

        swarm.vx[i] += moveX * separation_factor;
        swarm.vy[i] += moveY * separation_factor;

        // Apply velocities
        swarm.px[i] += swarm.vx[i];
        swarm.py[i] += swarm.vy[i];

        // Screen wrap (Pseudo-boundaries)
        if (swarm.px[i] < -400) swarm.px[i] = 400;
        if (swarm.px[i] > 400) swarm.px[i] = -400;
        if (swarm.py[i] < -300) swarm.py[i] = 300;
        if (swarm.py[i] > 300) swarm.py[i] = -300;
    }
}
