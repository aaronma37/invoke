const std = @import("std");

pub const TypeTag = enum {
    f32,
    f64,
    i32,
    u32,
    bool,
};

pub fn TypeFromTag(comptime tag: TypeTag) type {
    return switch (tag) {
        .f32 => f32,
        .f64 => f64,
        .i32 => i32,
        .u32 => u32,
        .bool => bool,
    };
}

/// A Field definition for a Wire
pub const Field = struct {
    name: []const u8,
    type_tag: TypeTag,
};

/// This function takes an array of Fields and uses Zig's @Type (reify)
/// to dynamically construct an 'extern struct' at comptime.
pub fn CreateWireType(comptime fields: []const Field) type {
    var struct_fields: [fields.len]std.builtin.Type.StructField = undefined;

    for (fields, 0..) |field, i| {
        const T = TypeFromTag(field.type_tag);
        // Ensure name is null-terminated for @Type (reify)
        const field_name: [:0]const u8 = std.fmt.comptimePrint("{s}", .{field.name});
        struct_fields[i] = .{
            .name = field_name,
            .type = T,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(T),
        };
    }

    const type_info = std.builtin.Type{
        .@"struct" = .{
            .layout = .@"extern",
            .fields = &struct_fields,
            .decls = &.{},
            .is_tuple = false,
        },
    };

    return @Type(type_info);
}

/// A simple 'comptime' parser that converts a basic DSL string into Fields.
/// Format: "name:type;name:type"
pub fn ParseSchema(comptime input: []const u8) []const Field {
    @setEvalBranchQuota(2000);
    var field_count = 0;
    for (input) |c| {
        if (c == ';') field_count += 1;
    }
    if (input.len > 0 and input[input.len - 1] != ';') field_count += 1;

    var fields: [field_count]Field = undefined;
    var current_field = 0;

    var it = std.mem.tokenizeAny(u8, input, ";");
    while (it.next()) |entry| {
        var parts = std.mem.tokenizeAny(u8, entry, ":");
        const name = parts.next() orelse @compileError("Missing field name");
        const type_str = parts.next() orelse @compileError("Missing field type");

        const tag = if (std.mem.eql(u8, type_str, "f32"))
            TypeTag.f32
        else if (std.mem.eql(u8, type_str, "i32"))
            TypeTag.i32
        else if (std.mem.eql(u8, type_str, "u32"))
            TypeTag.u32
        else if (std.mem.eql(u8, type_str, "bool"))
            TypeTag.bool
        else
            @compileError("Unknown type: " ++ type_str);

        fields[current_field] = .{ .name = name, .type_tag = tag };
        current_field += 1;
    }

    const final_fields = fields;
    return &final_fields;
}

pub fn GetTypeSize(type_str: []const u8) usize {
    var base_type = type_str;
    var count: usize = 1;

    if (std.mem.indexOf(u8, type_str, "[")) |idx| {
        base_type = type_str[0..idx];
        const end = std.mem.indexOf(u8, type_str, "]") orelse type_str.len;
        count = std.fmt.parseInt(usize, type_str[idx+1..end], 10) catch 1;
    }

    const base_size: usize = if (std.mem.eql(u8, base_type, "f32")) @sizeOf(f32)
                  else if (std.mem.eql(u8, base_type, "f64")) @sizeOf(f64)
                  else if (std.mem.eql(u8, base_type, "i32")) @sizeOf(i32)
                  else if (std.mem.eql(u8, base_type, "u32")) @sizeOf(u32)
                  else if (std.mem.eql(u8, base_type, "u8")) @sizeOf(u8)
                  else if (std.mem.eql(u8, base_type, "i8")) @sizeOf(i8)
                  else if (std.mem.eql(u8, base_type, "bool")) @sizeOf(bool)
                  else if (std.mem.eql(u8, base_type, "char")) 1
                  else 0;
    
    return base_size * count;
}

pub fn CalculateSchemaSize(input: []const u8) usize {
    var total_size: usize = 0;
    var it = std.mem.tokenizeAny(u8, input, ";");
    while (it.next()) |entry| {
        var parts = std.mem.tokenizeAny(u8, entry, ":");
        _ = parts.next(); // name
        const type_str = parts.next() orelse continue;
        total_size += GetTypeSize(type_str);
    }
    return total_size;
}

pub const RuntimeField = struct {
    name: []const u8,
    type_tag: TypeTag,
    offset: usize,
    size: usize,
    array_count: usize,
};

pub const SchemaIterator = struct {
    input: []const u8,
    tokenizer: std.mem.TokenIterator(u8, .any),
    current_offset: usize = 0,

    pub fn init(input: []const u8) SchemaIterator {
        return .{
            .input = input,
            .tokenizer = std.mem.tokenizeAny(u8, input, ";"),
        };
    }

    pub fn next(self: *SchemaIterator) ?RuntimeField {
        const entry = self.tokenizer.next() orelse return null;
        var parts = std.mem.tokenizeAny(u8, entry, ":");
        const name = parts.next() orelse return null;
        const type_raw = parts.next() orelse return null;

        var base_type = type_raw;
        var count: usize = 1;
        if (std.mem.indexOf(u8, type_raw, "[")) |idx| {
            base_type = type_raw[0..idx];
            const end = std.mem.indexOf(u8, type_raw, "]") orelse type_raw.len;
            count = std.fmt.parseInt(usize, type_raw[idx + 1 .. end], 10) catch 1;
        }

        const tag: TypeTag = if (std.mem.eql(u8, base_type, "f32")) .f32
        else if (std.mem.eql(u8, base_type, "f64")) .f64
        else if (std.mem.eql(u8, base_type, "i32")) .i32
        else if (std.mem.eql(u8, base_type, "u32")) .u32
        else if (std.mem.eql(u8, base_type, "bool")) .bool
        else .u32; // Default

        const size = GetTypeSize(type_raw);
        const field = RuntimeField{
            .name = name,
            .type_tag = tag,
            .offset = self.current_offset,
            .size = size,
            .array_count = count,
        };

        self.current_offset += size;
        return field;
    }
};

pub fn generateCStruct(allocator: std.mem.Allocator, name: []const u8, schema_str: []const u8) ![]const u8 {
    var list = std.ArrayList(u8).init(allocator);
    
    // Replace dots with underscores for valid C identifier
    const safe_name = try allocator.dupe(u8, name);
    defer allocator.free(safe_name);
    for (safe_name) |*c| if (c.* == '.') { c.* = '_'; };

    // --- ENFORCED SOA VIEW ---
    // Instead of mapping the wire memory 1:1, we generate a 'View' struct.
    // Every field is a pointer. This forces the logic to be layout-agnostic
    // and encourages SOA access patterns.
    try list.writer().print("typedef struct {{\n", .{});
    
    var it = std.mem.tokenizeAny(u8, schema_str, ";");
    while (it.next()) |entry| {
        var parts = std.mem.tokenizeAny(u8, entry, ":");
        const f_name = parts.next() orelse continue;
        const f_type_raw = parts.next() orelse continue;
        
        var f_type = f_type_raw;
        if (std.mem.indexOf(u8, f_type_raw, "[")) |idx| {
            f_type = f_type_raw[0..idx];
        }

        const c_type = if (std.mem.eql(u8, f_type, "f32")) "float"
                  else if (std.mem.eql(u8, f_type, "f64")) "double"
                  else if (std.mem.eql(u8, f_type, "i32")) "int32_t"
                  else if (std.mem.eql(u8, f_type, "u32")) "uint32_t"
                  else if (std.mem.eql(u8, f_type, "bool")) "bool"
                  else if (std.mem.eql(u8, f_type, "char")) "char"
                  else "uint8_t";
                  
        // Every field is now a pointer to the start of its column in the wire.
        try list.writer().print("    {s}* {s};\n", .{ c_type, f_name });
    }
    try list.writer().print("}} {s}_t;\n\n", .{safe_name});

    return list.toOwnedSlice();
}

test "CalculateSchemaSize" {
    try std.testing.expectEqual(@as(usize, 8), CalculateSchemaSize("x:f32;y:f32"));
    try std.testing.expectEqual(@as(usize, 4004), CalculateSchemaSize("count:i32;px:f32[1000]"));
}

test "generateCStruct" {
    const allocator = std.testing.allocator;
    const c_struct = try generateCStruct(allocator, "swarm.boids", "count:i32;px:f32[1000]");
    defer allocator.free(c_struct);

    try std.testing.expect(std.mem.indexOf(u8, c_struct, "typedef struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, c_struct, "int32_t* count;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c_struct, "float* px;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c_struct, "} swarm_boids_t;") != null);
}

test "SchemaIterator: Precise Offset and Array Mapping" {
    const input = "count:i32;pos:f32[3];active:bool";
    var it = SchemaIterator.init(input);

    // Field 1: count (i32, 4 bytes)
    const f1 = it.next().?;
    try std.testing.expectEqualStrings("count", f1.name);
    try std.testing.expectEqual(@as(usize, 0), f1.offset);
    try std.testing.expectEqual(TypeTag.i32, f1.type_tag);

    // Field 2: pos (f32[3], 12 bytes)
    const f2 = it.next().?;
    try std.testing.expectEqualStrings("pos", f2.name);
    try std.testing.expectEqual(@as(usize, 4), f2.offset); // Starts after i32
    try std.testing.expectEqual(@as(usize, 12), f2.size);
    try std.testing.expectEqual(@as(usize, 3), f2.array_count);

    // Field 3: active (bool, 1 byte)
    const f3 = it.next().?;
    try std.testing.expectEqual(@as(usize, 16), f3.offset); // Starts after 4 + 12
    try std.testing.expectEqual(TypeTag.bool, f3.type_tag);
}

