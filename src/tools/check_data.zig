const std = @import("std");
const kan = @import("kan");
const PointSample = kan.kan_dataloader.PointSample;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <dataset.pcb>\n", .{args[0]});
        return;
    }

    const file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();
    const stat = try file.stat();
    const count = stat.size / @sizeOf(PointSample);
    const ptr = try std.posix.mmap(null, stat.size, std.posix.PROT.READ, .{ .TYPE = .SHARED }, file.handle, 0);
    const samples = std.mem.bytesAsSlice(PointSample, ptr);

    var min_x: f32 = 1e10; var max_x: f32 = -1e10;
    var min_y: f32 = 1e10; var max_y: f32 = -1e10;
    var min_z: f32 = 1e10; var max_z: f32 = -1e10;

    for (samples) |s| {
        if (s.x < min_x) min_x = s.x; if (s.x > max_x) max_x = s.x;
        if (s.y < min_y) min_y = s.y; if (s.y > max_y) max_y = s.y;
        if (s.z < min_z) min_z = s.z; if (s.z > max_z) max_z = s.z;
    }

    std.debug.print("Points: {d}\n", .{count});
    std.debug.print("Bounds X: [{d:0.3}, {d:0.3}]\n", .{min_x, max_x});
    std.debug.print("Bounds Y: [{d:0.3}, {d:0.3}]\n", .{min_y, max_y});
    std.debug.print("Bounds Z: [{d:0.3}, {d:0.3}]\n", .{min_z, max_z});
}
