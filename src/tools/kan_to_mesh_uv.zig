const std = @import("std");
const kan = @import("kan");
const KanNetwork = kan.KanNetwork;

const Vec3 = struct {
    x: f32, y: f32, z: f32,
    pub fn add(a: Vec3, b: Vec3) Vec3 { return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z }; }
    pub fn sub(a: Vec3, b: Vec3) Vec3 { return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z }; }
    pub fn mul(a: Vec3, s: f32) Vec3 { return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s }; }
    pub fn length(a: Vec3) f32 { return @sqrt(a.x * a.x + a.y * a.y + a.z * a.z); }
    pub fn normalize(a: Vec3) Vec3 { 
        const len = a.length();
        if (len < 1e-8) return .{ .x = 0, .y = 1, .z = 0 };
        return a.mul(1.0 / len); 
    }
    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }
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

    var base_positions = std.ArrayList(Vec3).init(allocator);
    defer base_positions.deinit();
    var base_uvs = std.ArrayList(Vec2).init(allocator);
    defer base_uvs.deinit();
    var base_faces = std.ArrayList(Face).init(allocator);
    defer base_faces.deinit();

    var line_it = std.mem.splitScalar(u8, file_content, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \r\t");
        if (line.len == 0 or line[0] == '#') continue;
        var it = std.mem.tokenizeAny(u8, line, " ");
        const prefix = it.next() orelse continue;

        if (std.mem.eql(u8, prefix, "v")) {
            const x = try std.fmt.parseFloat(f32, it.next().?);
            const y = try std.fmt.parseFloat(f32, it.next().?);
            const z = try std.fmt.parseFloat(f32, it.next().?);
            try base_positions.append(.{ .x = x, .y = y, .z = z });
        } else if (std.mem.eql(u8, prefix, "vt")) {
            const u = try std.fmt.parseFloat(f32, it.next().?);
            const v = try std.fmt.parseFloat(f32, it.next().?);
            try base_uvs.append(.{ .u = u, .v = v });
        } else if (std.mem.eql(u8, prefix, "f")) {
            var f: Face = undefined;
            for (0..3) |i| {
                const part = it.next().?;
                var sit = std.mem.splitScalar(u8, part, '/');
                f.v_idx[i] = (try std.fmt.parseInt(usize, sit.next().?, 10)) - 1;
                if (sit.next()) |vt_str| {
                    if (vt_str.len > 0) f.vt_idx[i] = (try std.fmt.parseInt(usize, vt_str, 10)) - 1
                    else f.vt_idx[i] = 0;
                } else f.vt_idx[i] = 0;
            }
            try base_faces.append(f);
        }
    }
    
    // 3. Reconstruct using Triangle Corners (to handle UV seams correctly)
    const out_verts = try allocator.alloc(Vec3, base_faces.items.len * 3);
    defer allocator.free(out_verts);
    const out_uvs = try allocator.alloc(Vec2, base_faces.items.len * 3);
    defer allocator.free(out_uvs);
    const out_norms = try allocator.alloc(Vec3, base_faces.items.len * 3);
    defer allocator.free(out_norms);

    const batch_size = 1024;
    var activations = try allocator.alloc([]f32, net.layers.len + 1);
    for (0..net.layers.len) |i| activations[i] = try allocator.alloc(f32, batch_size * net.layers[i].in_dim);
    activations[net.layers.len] = try allocator.alloc(f32, batch_size * net.out_dim);
    defer { for (activations) |a| allocator.free(a); allocator.free(activations); }

    var f_idx: usize = 0;
    while (f_idx < base_faces.items.len) {
        const remaining = base_faces.items.len - f_idx;
        const limit = batch_size / 3;
        const chunk_faces = @min(remaining, limit);
        if (chunk_faces == 0) break;
        const cp: usize = chunk_faces;
        const chunk_points = cp + cp + cp;
        
        for (0..chunk_faces) |i| {
            const face = base_faces.items[f_idx + i];
            for (0..3) |j| {
                const uv = if (base_uvs.items.len > face.vt_idx[j]) base_uvs.items[face.vt_idx[j]] else Vec2{ .u = 0, .v = 0 };
                const base_idx = (i * 3 + j) * 2;
                activations[0][base_idx + 0] = uv.u;
                activations[0][base_idx + 1] = uv.v;
                out_uvs[(f_idx + i) * 3 + j] = uv;
            }
        }

        net.forward(activations[0], activations, chunk_points);

        for (0..chunk_faces) |i| {
            const face = base_faces.items[f_idx + i];
            for (0..3) |j| {
                const base_pos = base_positions.items[face.v_idx[j]];
                const disp = activations[net.layers.len][(i * 3 + j) * 3 .. (i * 3 + j) * 3 + 3];
                out_verts[(f_idx + i) * 3 + j] = base_pos.add(.{ .x = disp[0], .y = disp[1], .z = disp[2] });
            }
        }
        f_idx += chunk_faces;
    }

    // 4. Compute Face Normals
    for (0..base_faces.items.len) |i| {
        const v0 = out_verts[i * 3 + 0];
        const v1 = out_verts[i * 3 + 1];
        const v2 = out_verts[i * 3 + 2];
        const edge1 = v1.sub(v0);
        const edge2 = v2.sub(v0);
        const face_norm = edge1.cross(edge2).normalize();
        
        out_norms[i * 3 + 0] = face_norm;
        out_norms[i * 3 + 1] = face_norm;
        out_norms[i * 3 + 2] = face_norm;
    }

    // 5. Save OBJ
    const out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    var writer = out_file.writer();

    try writer.print("# Moontide KAN Reconstructed Mesh (Triangle Corner Split)\n", .{});
    for (out_verts) |v| try writer.print("v {d:0.6} {d:0.6} {d:0.6}\n", .{v.x, v.y, v.z});
    for (out_uvs) |uv| try writer.print("vt {d:0.6} {d:0.6}\n", .{uv.u, uv.v});
    for (out_norms) |n| try writer.print("vn {d:0.6} {d:0.6} {d:0.6}\n", .{n.x, n.y, n.z});

    for (0..base_faces.items.len) |i| {
        const v1 = i * 3 + 1;
        const v2 = i * 3 + 2;
        const v3 = i * 3 + 3;
        try writer.print("f {d}/{d}/{d} {d}/{d}/{d} {d}/{d}/{d}\n", .{ v1, v1, v1, v2, v2, v2, v3, v3, v3 });
    }

    std.debug.print("Saved Reconstruction to {s}\n", .{out_path});
}
