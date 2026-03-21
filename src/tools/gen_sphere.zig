const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const rings = 128;
    const sectors = 128;
    const radius = 1.0;

    // 1. Vertices & UVs
    for (0..rings + 1) |r| {
        const phi = std.math.pi * @as(f32, @floatFromInt(r)) / @as(f32, @floatFromInt(rings));
        for (0..sectors + 1) |s| {
            const theta = 2.0 * std.math.pi * @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(sectors));
            
            const x = radius * @sin(phi) * @cos(theta);
            const y = radius * @cos(phi);
            const z = radius * @sin(phi) * @sin(theta);
            
            const u = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(sectors));
            const v = @as(f32, @floatFromInt(r)) / @as(f32, @floatFromInt(rings));

            try stdout.print("v {d:0.6} {d:0.6} {d:0.6}\n", .{ x, y, z });
            try stdout.print("vt {d:0.6} {d:0.6}\n", .{ u, v });
        }
    }

    // 2. Faces
    for (0..rings) |r| {
        for (0..sectors) |s| {
            const first = r * (sectors + 1) + s + 1;
            const second = first + sectors + 1;

            // Two triangles per sector
            try stdout.print("f {d}/{d} {d}/{d} {d}/{d}\n", .{ first, first, second, second, first + 1, first + 1 });
            try stdout.print("f {d}/{d} {d}/{d} {d}/{d}\n", .{ second, second, second + 1, second + 1, first + 1, first + 1 });
        }
    }
}
