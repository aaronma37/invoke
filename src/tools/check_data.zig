const std = @import("std");
const kan = @import("kan");
const PointSample = kan.kan_dataloader.PointSample;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const path = if (args.len > 1) args[1] else "current_dataset.pcb";

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    
    const samples = try allocator.alloc(PointSample, stat.size / 36);
    defer allocator.free(samples);
    _ = try file.readAll(std.mem.sliceAsBytes(samples));

    std.debug.print("Dataset Check: {d} points\n", .{samples.len});
    var min_sdf: f32 = 1e10;
    var max_sdf: f32 = -1e10;
    var avg_sdf: f32 = 0;

    for (samples[0..@min(samples.len, 1000)]) |s| {
        if (s.sdf < min_sdf) min_sdf = s.sdf;
        if (s.sdf > max_sdf) max_sdf = s.sdf;
        avg_sdf += s.sdf;
    }

    std.debug.print("First 1000 Stats: Min {d:0.4}, Max {d:0.4}, Avg {d:0.4}\n", .{min_sdf, max_sdf, avg_sdf / 1000.0});
    
    std.debug.print("First 5 points:\n", .{});
    for (samples[0..5]) |s| {
        std.debug.print("  POS: ({d:0.3}, {d:0.3}, {d:0.3}) SDF: {d:0.4}\n", .{s.x, s.y, s.z, s.sdf});
    }
}
