const std = @import("std");
const kan = @import("kan");
const PointSample = kan.kan_dataloader.PointSample;

const Vec3 = struct {
    x: f32, y: f32, z: f32,

    pub fn sub(a: Vec3, b: Vec3) Vec3 { return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z }; }
    pub fn add(a: Vec3, b: Vec3) Vec3 { return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z }; }
    pub fn mul(a: Vec3, s: f32) Vec3 { return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s }; }
    pub fn dot(a: Vec3, b: Vec3) f32 { return a.x * b.x + a.y * b.y + a.z * b.z; }
    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }
    pub fn length(a: Vec3) f32 { return @sqrt(a.dot(a)); }
    pub fn normalize(a: Vec3) Vec3 { return a.mul(1.0 / a.length()); }
};

fn rayTriangleIntersect(orig: Vec3, dir: Vec3, v0: Vec3, v1: Vec3, v2: Vec3) ?f32 {
    const edge1 = v1.sub(v0);
    const edge2 = v2.sub(v0);
    const pvec = dir.cross(edge2);
    const det = edge1.dot(pvec);

    if (det > -1e-6 and det < 1e-6) return null;
    const inv_det = 1.0 / det;

    const tvec = orig.sub(v0);
    const u = tvec.dot(pvec) * inv_det;
    if (u < 0.0 or u > 1.0) return null;

    const qvec = tvec.cross(edge1);
    const v = dir.dot(qvec) * inv_det;
    if (v < 0.0 or u + v > 1.0) return null;

    const t = edge2.dot(qvec) * inv_det;
    if (t < 0.0) return null;
    return t;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <target.obj> <output.pcb> [resolution]\n", .{args[0]});
        return;
    }

    const target_path = args[1];
    const out_path = args[2];
    const res = if (args.len > 3) try std.fmt.parseInt(usize, args[3], 10) else 512;

    // 1. Load Target OBJ (Minimal loader)
    const file = try std.fs.cwd().openFile(target_path, .{});
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

    std.debug.print("Loaded target: {d} vertices, {d} faces\n", .{vertices.items.len, faces.items.len});

    // 2. Sample UV Grid on Sphere
    var samples = try allocator.alloc(PointSample, res * res);
    defer allocator.free(samples);

    for (0..res) |v_idx| {
        for (0..res) |u_idx| {
            const u = @as(f32, @floatFromInt(u_idx)) / @as(f32, @floatFromInt(res - 1));
            const v = @as(f32, @floatFromInt(v_idx)) / @as(f32, @floatFromInt(res - 1));

            // Map UV to Sphere
            const theta = 2.0 * std.math.pi * u;
            const phi = std.math.pi * v;
            const dir = Vec3{
                .x = @sin(phi) * @cos(theta),
                .y = @sin(phi) * @sin(theta),
                .z = @cos(phi),
            };

            // Raycast along normal (dir is normal for unit sphere)
            var min_t: f32 = 10.0; // Max displacement
            var hit = false;
            
            // Note: This is O(N_faces * N_samples), slow but correct for small-ish meshes.
            // For production, use a BVH.
            for (faces.items) |f| {
                if (rayTriangleIntersect(.{ .x = 0, .y = 0, .z = 0 }, dir, vertices.items[f[0]], vertices.items[f[1]], vertices.items[f[2]])) |t| {
                    if (t < min_t) {
                        min_t = t;
                        hit = true;
                    }
                }
            }

            samples[v_idx * res + u_idx] = .{
                .x = u, .y = v, .z = 0.0,
                .sdf = if (hit) min_t else 0.0,
                .r = 0.5, .g = 0.5, .b = 0.5,
                .roughness = 0.5, .metallic = 0.0,
            };
        }
        if (v_idx % 10 == 0) std.debug.print("Sampling: {d}%\r", .{(v_idx * 100) / res});
    }

    // 3. Save to PCB
    const out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    try out_file.writeAll(std.mem.sliceAsBytes(samples));
    std.debug.print("\nSaved {d} UV samples to {s}\n", .{samples.len, out_path});
}
