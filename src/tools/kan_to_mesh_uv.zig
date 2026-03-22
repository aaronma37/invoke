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
    vn_idx: [3]usize,
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

    var positions = std.ArrayList(Vec3).init(allocator);
    defer positions.deinit();
    var uvs = std.ArrayList(Vec2).init(allocator);
    defer uvs.deinit();
    var normals = std.ArrayList(Vec3).init(allocator);
    defer normals.deinit();
    var faces = std.ArrayList(Face).init(allocator);
    defer faces.deinit();

    var it = std.mem.tokenizeAny(u8, file_content, " \r\n");
    while (it.next()) |token| {
        if (std.mem.eql(u8, token, "v")) {
            const x = try std.fmt.parseFloat(f32, it.next().?);
            const y = try std.fmt.parseFloat(f32, it.next().?);
            const z = try std.fmt.parseFloat(f32, it.next().?);
            try positions.append(.{ .x = x, .y = y, .z = z });
        } else if (std.mem.eql(u8, token, "vt")) {
            const u = try std.fmt.parseFloat(f32, it.next().?);
            const v = try std.fmt.parseFloat(f32, it.next().?);
            try uvs.append(.{ .u = u, .v = v });
        } else if (std.mem.eql(u8, token, "vn")) {
            const x = try std.fmt.parseFloat(f32, it.next().?);
            const y = try std.fmt.parseFloat(f32, it.next().?);
            const z = try std.fmt.parseFloat(f32, it.next().?);
            try normals.append(.{ .x = x, .y = y, .z = z });
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
                    if (sit.next()) |n_str| {
                        f.vn_idx[i] = (try std.fmt.parseInt(usize, n_str, 10)) - 1;
                    } else { f.vn_idx[i] = 0; }
                } else {
                    f.vt_idx[i] = 0;
                    f.vn_idx[i] = 0;
                }
            }
            try faces.append(f);
        }
    }
    
    std.debug.print("Loaded base mesh: {d} verts, {d} uvs, {d} faces.\n", .{positions.items.len, uvs.items.len, faces.items.len});

    // 3. Displace Vertices based on UVs (one vertex per face corner to handle shared UVs correctly)
    const out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    var writer = out_file.writer();

    const batch_size = 1024;
    var activations = try allocator.alloc([]f32, net.layers.len + 1);
    for (0..net.layers.len) |i| activations[i] = try allocator.alloc(f32, batch_size * net.layers[i].in_dim);
    activations[net.layers.len] = try allocator.alloc(f32, batch_size * net.out_dim);
    defer { for (activations) |a| allocator.free(a); allocator.free(activations); }

    var f_idx: usize = 0;
    var vert_out_count: usize = 0;
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
                const pos = positions.items[face.v_idx[j]];
                
                // Determine Normal: 
                // 1. If explicit normals exist, use them.
                // 2. Otherwise, use normalized position (assumes centered on origin)
                var normal = if (normals.items.len > face.vn_idx[j]) normals.items[face.vn_idx[j]] else pos.normalize();
                
                const d = activations[net.layers.len][(i * 3 + j) * net.out_dim];
                const displaced_pos = pos.add(normal.mul(d));
                
                try writer.print("v {d:0.6} {d:0.6} {d:0.6}\n", .{displaced_pos.x, displaced_pos.y, displaced_pos.z});
                const uv = if (uvs.items.len > face.vt_idx[j]) uvs.items[face.vt_idx[j]] else Vec2{ .u = 0, .v = 0 };
                try writer.print("vt {d:0.6} {d:0.6}\n", .{uv.u, uv.v});
            }
            
            const v1 = vert_out_count + 1;
            const v2 = vert_out_count + 2;
            const v3 = vert_out_count + 3;
            try writer.print("f {d}/{d} {d}/{d} {d}/{d}\n", .{ v1, v1, v2, v2, v3, v3 });
            vert_out_count += 3;
        }

        f_idx += current_batch_faces;
    }

    std.debug.print("Successfully saved displaced mesh to {s}\n", .{out_path});
}
