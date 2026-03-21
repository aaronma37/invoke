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

const Vec2 = struct { u: f32, v: f32 };

const Face = struct {
    v_idx: [3]usize,
    vt_idx: [3]usize,
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
    const file_content = try std.fs.cwd().readFileAlloc(allocator, base_path, 100 * 1024 * 1024);
    defer allocator.free(file_content);

    var vertices = std.ArrayList(Vec3).init(allocator);
    defer vertices.deinit();
    var uvs = std.ArrayList(Vec2).init(allocator);
    defer uvs.deinit();
    var faces = std.ArrayList(Face).init(allocator);
    defer faces.deinit();

    var it = std.mem.tokenizeAny(u8, file_content, " \r\n");
    while (it.next()) |token| {
        if (std.mem.eql(u8, token, "v")) {
            const x = try std.fmt.parseFloat(f32, it.next().?);
            const y = try std.fmt.parseFloat(f32, it.next().?);
            const z = try std.fmt.parseFloat(f32, it.next().?);
            try vertices.append(.{ .x = x, .y = y, .z = z });
        } else if (std.mem.eql(u8, token, "vt")) {
            const u = try std.fmt.parseFloat(f32, it.next().?);
            const v = try std.fmt.parseFloat(f32, it.next().?);
            try uvs.append(.{ .u = u, .v = v });
        } else if (std.mem.eql(u8, token, "f")) {
            var f: Face = undefined;
            for (0..3) |i| {
                const part = it.next().?;
                var sit = std.mem.tokenizeAny(u8, part, "/");
                f.v_idx[i] = (try std.fmt.parseInt(usize, sit.next().?, 10)) - 1;
                if (sit.next()) |uv_str| {
                    if (uv_str.len > 0) {
                        f.vt_idx[i] = (try std.fmt.parseInt(usize, uv_str, 10)) - 1;
                    } else { f.vt_idx[i] = 0; }
                } else {
                    f.vt_idx[i] = 0;
                }
            }
            try faces.append(f);
        }
    }
    
    std.debug.print("Loaded base mesh: {d} verts, {d} uvs, {d} faces.\n", .{vertices.items.len, uvs.items.len, faces.items.len});

    // 3. Displace Vertices based on UVs
    // Since vertices might be split by UVs in the OBJ, we'll displace based on the face-vertex combinations.
    // To keep the output mesh unified, we will create a new displaced vertex array matching the size of the original vertices.
    // Note: If a vertex has multiple UVs (seams), this simple approach will use the last UV evaluated.
    var displaced = try allocator.alloc(Vec3, vertices.items.len);
    defer allocator.free(displaced);
    @memcpy(displaced, vertices.items); // Copy base geometry first

    const batch_size = 1000;
    var activations = try allocator.alloc([]f32, net.layers.len + 1);
    for (0..net.layers.len) |i| activations[i] = try allocator.alloc(f32, batch_size * net.layers[i].in_dim);
    activations[net.layers.len] = try allocator.alloc(f32, batch_size * net.out_dim);
    defer { for (activations) |a| allocator.free(a); allocator.free(activations); }

    var f_idx: usize = 0;
    while (f_idx < faces.items.len) {
        const current_batch_faces = if (faces.items.len - f_idx < batch_size / 3) faces.items.len - f_idx else batch_size / 3;
        const current_points = current_batch_faces * 3;
        
        for (0..current_batch_faces) |i| {
            const face = faces.items[f_idx + i];
            for (0..3) |j| {
                const uv = if (uvs.items.len > face.vt_idx[j]) uvs.items[face.vt_idx[j]] else Vec2{ .u = 0, .v = 0 };
                activations[0][(i * 3 + j) * 2 + 0] = uv.u;
                activations[0][(i * 3 + j) * 2 + 1] = uv.v;
            }
        }

        net.forward(activations[0], activations, current_points);

        for (0..current_batch_faces) |i| {
            const face = faces.items[f_idx + i];
            for (0..3) |j| {
                const v_id = face.v_idx[j];
                const base_v = vertices.items[v_id];
                const normal = base_v.normalize(); // Simple spherical normal for now
                const d = activations[net.layers.len][(i * 3 + j) * net.out_dim];
                
                // Note: If a vertex is shared across faces, it will be overwritten. 
                // For a fully unwrapped mesh, vertices are usually unique per UV anyway.
                displaced[v_id] = base_v.add(normal.mul(d));
            }
        }

        f_idx += current_batch_faces;
    }

    // 4. Save Displaced OBJ
    const out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    var writer = out_file.writer();

    for (displaced) |v| {
        try writer.print("v {d:0.6} {d:0.6} {d:0.6}\n", .{v.x, v.y, v.z});
    }
    for (uvs.items) |uv| {
        try writer.print("vt {d:0.6} {d:0.6}\n", .{uv.u, uv.v});
    }
    for (faces.items) |f| {
        try writer.print("f {d}/{d} {d}/{d} {d}/{d}\n", .{
            f.v_idx[0] + 1, f.vt_idx[0] + 1,
            f.v_idx[1] + 1, f.vt_idx[1] + 1,
            f.v_idx[2] + 1, f.vt_idx[2] + 1,
        });
    }

    std.debug.print("Successfully saved displaced mesh to {s}\n", .{out_path});
}
