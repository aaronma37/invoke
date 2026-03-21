const std = @import("std");
const kan = @import("kan");
const KanNetwork = kan.KanNetwork;

const Vec3 = struct {
    x: f32, y: f32, z: f32,

    pub fn add(a: Vec3, b: Vec3) Vec3 { return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z }; }
    pub fn mul(a: Vec3, s: f32) Vec3 { return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s }; }
    pub fn length(a: Vec3) f32 { return @sqrt(a.x * a.x + a.y * a.y + a.z * a.z); }
    pub fn normalize(a: Vec3) Vec3 { return a.mul(1.0 / a.length()); }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 4) {
        std.debug.print("Usage: {s} <base.obj> <model_disp.kan> <output.obj>\n", .{args[0]});
        return;
    }

    const base_path = args[1];
    const model_path = args[2];
    const out_path = args[3];

    // 1. Load KAN
    var net = try KanNetwork.loadModel(allocator, model_path);
    defer net.deinit();

    // 2. Load Base OBJ
    const file = try std.fs.cwd().openFile(base_path, .{});
    defer file.close();
    var reader = std.io.bufferedReader(file.reader());
    var in_stream = reader.reader();

    var vertices = std.ArrayList(Vec3).init(allocator);
    defer vertices.deinit();
    var faces = std.ArrayList([3]usize).init(allocator);
    defer faces.deinit();

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var it = std.mem.tokenizeAny(u8, line, " ");
        const first = it.next() orelse continue;
        if (std.mem.eql(u8, first, "v")) {
            const x = try std.fmt.parseFloat(f32, it.next().?);
            const y = try std.fmt.parseFloat(f32, it.next().?);
            const z = try std.fmt.parseFloat(f32, it.next().?);
            try vertices.append(.{ .x = x, .y = y, .z = z });
        } else if (std.mem.eql(u8, first, "f")) {
            var f: [3]usize = undefined;
            for (0..3) |i| {
                const part = it.next().?;
                var sit = std.mem.tokenizeAny(u8, part, "/");
                f[i] = (try std.fmt.parseInt(usize, sit.next().?, 10)) - 1;
            }
            try faces.append(f);
        }
    }

    // 3. Displace Vertices
    var displaced = try allocator.alloc(Vec3, vertices.items.len);
    defer allocator.free(displaced);

    const batch_size = 1000;
    var activations = try allocator.alloc([]f32, net.layers.len + 1);
    for (0..net.layers.len) |i| activations[i] = try allocator.alloc(f32, batch_size * net.layers[i].in_dim);
    activations[net.layers.len] = try allocator.alloc(f32, batch_size * net.out_dim);
    defer { for (activations) |a| allocator.free(a); allocator.free(activations); }

    var v_idx: usize = 0;
    while (v_idx < vertices.items.len) {
        const current_batch = if (vertices.items.len - v_idx < batch_size) vertices.items.len - v_idx else batch_size;
        
        for (0..current_batch) |i| {
            const v = vertices.items[v_idx + i];
            const normal = v.normalize();
            
            // Spherical Mapping to UV
            const phi = std.math.acos(std.math.clamp(normal.z, -1.0, 1.0));
            const theta = std.math.atan2(normal.y, normal.x);
            
            const u = (theta + std.math.pi) / (2.0 * std.math.pi);
            const vv = phi / std.math.pi;

            activations[0][i * 2 + 0] = u;
            activations[0][i * 2 + 1] = vv;
        }

        net.forward(activations[0], activations, current_batch);

        for (0..current_batch) |i| {
            const v = vertices.items[v_idx + i];
            const normal = v.normalize();
            const d = activations[net.layers.len][i * net.out_dim];
            displaced[v_idx + i] = v.add(normal.mul(d));
        }

        v_idx += current_batch;
    }

    // 4. Save Displaced OBJ
    const out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    var writer = out_file.writer();

    for (displaced) |v| {
        try writer.print("v {d:0.6} {d:0.6} {d:0.6}\n", .{v.x, v.y, v.z});
    }
    for (faces.items) |f| {
        try writer.print("f {d} {d} {d}\n", .{f[0] + 1, f[1] + 1, f[2] + 1});
    }

    std.debug.print("Successfully saved displaced mesh to {s}\n", .{out_path});
}
