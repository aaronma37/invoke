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

const Vec2 = struct { u: f32, v: f32 };

const Face = struct {
    v_idx: [3]usize,
    vt_idx: [3]usize,
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

const Mesh = struct {
    vertices: std.ArrayList(Vec3),
    uvs: std.ArrayList(Vec2),
    faces: std.ArrayList(Face),

    pub fn deinit(self: *Mesh) void {
        self.vertices.deinit();
        self.uvs.deinit();
        self.faces.deinit();
    }
};

fn loadObj(allocator: mem.Allocator, path: []const u8) !Mesh {
    var mesh = Mesh{
        .vertices = std.ArrayList(Vec3).init(allocator),
        .uvs = std.ArrayList(Vec2).init(allocator),
        .faces = std.ArrayList(Face).init(allocator),
    };

    const file_content = try std.fs.cwd().readFileAlloc(allocator, path, 100 * 1024 * 1024);
    defer allocator.free(file_content);

    var it = std.mem.tokenizeAny(u8, file_content, " \r\n\\n");
    while (it.next()) |token| {
        if (std.mem.eql(u8, token, "v")) {
            const x_str = it.next() orelse break;
            const y_str = it.next() orelse break;
            const z_str = it.next() orelse break;
            const x = std.fmt.parseFloat(f32, x_str) catch |err| { std.debug.print("Error parsing v x: {s}\n", .{x_str}); return err; };
            const y = std.fmt.parseFloat(f32, y_str) catch |err| { std.debug.print("Error parsing v y: {s}\n", .{y_str}); return err; };
            const z = std.fmt.parseFloat(f32, z_str) catch |err| { std.debug.print("Error parsing v z: {s}\n", .{z_str}); return err; };
            try mesh.vertices.append(.{ .x = x, .y = y, .z = z });
        } else if (std.mem.eql(u8, token, "vt")) {
            const u_str = it.next() orelse break;
            const v_str = it.next() orelse break;
            const u = std.fmt.parseFloat(f32, u_str) catch |err| { std.debug.print("Error parsing vt u: {s}\n", .{u_str}); return err; };
            const v = std.fmt.parseFloat(f32, v_str) catch |err| { std.debug.print("Error parsing vt v: {s}\n", .{v_str}); return err; };
            try mesh.uvs.append(.{ .u = u, .v = v });
        } else if (std.mem.eql(u8, token, "f")) {
            var f: Face = undefined;
            for (0..3) |i| {
                const part = it.next() orelse break;
                var sit = std.mem.tokenizeAny(u8, part, "/");
                const v_idx_str = sit.next() orelse break;
                f.v_idx[i] = (std.fmt.parseInt(usize, v_idx_str, 10) catch |err| { std.debug.print("Error parsing f v: {s}\n", .{v_idx_str}); return err; }) - 1;
                if (sit.next()) |uv_str| {
                    if (uv_str.len > 0) {
                        f.vt_idx[i] = (std.fmt.parseInt(usize, uv_str, 10) catch 1) - 1;
                    } else { f.vt_idx[i] = 0; }
                } else {
                    f.vt_idx[i] = 0;
                }
            }
            try mesh.faces.append(f);
        } else {
            // Skip unknown tokens (g, s, mtllib, usemtl, etc)
            continue;
        }
    }
    return mesh;
}

const mem = std.mem;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <target.obj> <output.pcb> [base.obj | resolution]\n", .{args[0]});
        return;
    }

    const target_path = args[1];
    const out_path = args[2];
    
    var base_path: ?[]const u8 = null;
    var res: usize = 512;
    
    if (args.len > 3) {
        if (std.mem.endsWith(u8, args[3], ".obj")) {
            base_path = args[3];
            // When using a base mesh, we derive resolution from the base mesh vertex count 
            // or sample uniformly. For now, we will just sample every vertex explicitly.
        } else {
            res = try std.fmt.parseInt(usize, args[3], 10);
        }
    }

    var target_mesh = try loadObj(allocator, target_path);
    defer target_mesh.deinit();
    std.debug.print("Loaded target: {d} vertices, {d} faces\n", .{target_mesh.vertices.items.len, target_mesh.faces.items.len});

    var samples_list = std.ArrayList(PointSample).init(allocator);
    defer samples_list.deinit();

    if (base_path) |bp| {
        std.debug.print("Using explicit base mesh: {s}\n", .{bp});
        var base_mesh = try loadObj(allocator, bp);
        defer base_mesh.deinit();
        
        // Sample explicitly at every face vertex of the base mesh
        for (base_mesh.faces.items) |f| {
            for (0..3) |i| {
                const v_id = f.v_idx[i];
                const vt_id = f.vt_idx[i];
                const orig = base_mesh.vertices.items[v_id];
                const dir = orig.normalize(); 
                const uv = if (base_mesh.uvs.items.len > vt_id) base_mesh.uvs.items[vt_id] else Vec2{ .u = 0, .v = 0 };
                
                var min_t: f32 = 10.0;
                var hit = false;

                if (target_mesh.faces.items.len > 0) {
                    for (target_mesh.faces.items) |tf| {
                        if (rayTriangleIntersect(orig, dir, target_mesh.vertices.items[tf.v_idx[0]], target_mesh.vertices.items[tf.v_idx[1]], target_mesh.vertices.items[tf.v_idx[2]])) |t| {
                            if (t < min_t) {
                                min_t = t;
                                hit = true;
                            }
                        }
                    }
                } else {
                    // FALLBACK: Nearest Vertex Distance (Point Cloud)
                    // We look for the vertex closest to the ray path
                    var min_dist_sq: f32 = 1e10;
                    for (target_mesh.vertices.items) |tv| {
                        const to_v = tv.sub(orig);
                        const proj = to_v.dot(dir);
                        if (proj < 0) continue; // Behind ray
                        
                        const perp = to_v.sub(dir.mul(proj));
                        const d2 = perp.dot(perp);
                        if (d2 < 0.001) { // Very close to ray
                            if (proj < min_t) {
                                min_t = proj;
                                hit = true;
                            }
                        }
                        
                        // Also track raw distance for debugging
                        const d_raw_sq = to_v.dot(to_v);
                        if (d_raw_sq < min_dist_sq) min_dist_sq = d_raw_sq;
                    }
                    // If no ray hit, use nearest vertex as approximation
                    if (!hit) {
                        min_t = @sqrt(min_dist_sq);
                        hit = true;
                    }
                }
                
                try samples_list.append(.{
                    .x = uv.u, .y = uv.v, .z = 0.0,
                    .sdf = if (hit) min_t else 0.0,
                    .r = 0.5, .g = 0.5, .b = 0.5,
                    .roughness = 0.5, .metallic = 0.0,
                });
            }
        }
        std.debug.print("Sampled {d} explicit UV points from base mesh.\n", .{samples_list.items.len});
    } else {
        std.debug.print("Using spherical mapping at resolution {d}x{d}\n", .{res, res});
        for (0..res) |v_idx| {
            for (0..res) |u_idx| {
                const u = @as(f32, @floatFromInt(u_idx)) / @as(f32, @floatFromInt(res - 1));
                const v = @as(f32, @floatFromInt(v_idx)) / @as(f32, @floatFromInt(res - 1));

                const theta = 2.0 * std.math.pi * u;
                const phi = std.math.pi * v;
                const dir = Vec3{
                    .x = @sin(phi) * @cos(theta),
                    .y = @sin(phi) * @sin(theta),
                    .z = @cos(phi),
                };

                var min_t: f32 = 10.0; 
                var hit = false;
                
                for (target_mesh.faces.items) |f| {
                    if (rayTriangleIntersect(.{ .x = 0, .y = 0, .z = 0 }, dir, target_mesh.vertices.items[f.v_idx[0]], target_mesh.vertices.items[f.v_idx[1]], target_mesh.vertices.items[f.v_idx[2]])) |t| {
                        if (t < min_t) {
                            min_t = t;
                            hit = true;
                        }
                    }
                }

                try samples_list.append(.{
                    .x = u, .y = v, .z = 0.0,
                    .sdf = if (hit) min_t else 0.0,
                    .r = 0.5, .g = 0.5, .b = 0.5,
                    .roughness = 0.5, .metallic = 0.0,
                });
            }
            if (v_idx % 10 == 0) std.debug.print("Sampling: {d}%\r", .{(v_idx * 100) / res});
        }
    }

    // 3. Save to PCB
    const out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    try out_file.writeAll(std.mem.sliceAsBytes(samples_list.items));
    std.debug.print("\nSaved {d} samples to {s}\n", .{samples_list.items.len, out_path});
}
