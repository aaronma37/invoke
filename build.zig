const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. THE KERNEL (Pure Silicon)
    const exe = b.addExecutable(.{
        .name = "invoke",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.addIncludePath(b.path("src/core"));
    exe.addIncludePath(b.path("sdk"));
    b.installArtifact(exe);

    // 2. LUAJIT EXTENSION
    const luajit_ext = b.addSharedLibrary(.{
        .name = "luajit_ext",
        .root_source_file = b.path("extensions/luajit/luajit_ext.zig"),
        .target = target,
        .optimize = optimize,
    });
    luajit_ext.linkLibC();
    luajit_ext.linkSystemLibrary("luajit-5.1");
    luajit_ext.addIncludePath(b.path("sdk"));
    luajit_ext.addIncludePath(.{ .cwd_relative = "/usr/include/luajit-2.1" });
    
    const luajit_install = b.addInstallArtifact(luajit_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&luajit_install.step);

    // 3. WASM EXTENSION
    const wasm_ext = b.addSharedLibrary(.{
        .name = "wasm_ext",
        .root_source_file = b.path("extensions/wasm/wasm_ext.zig"),
        .target = target,
        .optimize = optimize,
    });
    wasm_ext.linkLibC();
    wasm_ext.addIncludePath(b.path("sdk"));
    wasm_ext.addIncludePath(.{ .cwd_relative = "/home/aaron-ma/.local/wasmtime-c-api/include" });
    wasm_ext.addLibraryPath(.{ .cwd_relative = "/home/aaron-ma/.local/wasmtime-c-api/lib" });
    wasm_ext.linkSystemLibrary("wasmtime");

    const wasm_install = b.addInstallArtifact(wasm_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&wasm_install.step);

    // 4. RUN COMMAND
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
