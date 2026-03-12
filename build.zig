const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // MODULES
    const core_mod = b.createModule(.{
        .root_source_file = b.path("src/core/orchestrator.zig"),
    });
    core_mod.addIncludePath(b.path("sdk"));
    core_mod.addIncludePath(b.path("src/core"));

    // 1. THE KERNEL (Pure Silicon)
    const exe = b.addExecutable(.{
        .name = "moontide",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.linkSystemLibrary("luajit-5.1");
    exe.addIncludePath(b.path("src/core"));
    exe.addIncludePath(b.path("sdk"));
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/luajit-2.1" });
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
    luajit_ext.root_module.addImport("core", core_mod);
    
    const luajit_install = b.addInstallArtifact(luajit_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&luajit_install.step);

    // 2.5 LIBMOONTIDE (Host Shared Library)
    const moontide_lib = b.addSharedLibrary(.{
        .name = "moontide",
        .root_source_file = b.path("src/core/orchestrator.zig"),
        .target = target,
        .optimize = optimize,
    });
    moontide_lib.linkLibC();
    moontide_lib.addIncludePath(b.path("sdk"));
    moontide_lib.addIncludePath(b.path("src/core"));
    b.installArtifact(moontide_lib);

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
    wasm_ext.root_module.addImport("core", core_mod);

    const wasm_install = b.addInstallArtifact(wasm_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&wasm_install.step);

    // 4. HUD (RAYLIB) EXTENSION
    const hud_ext = b.addSharedLibrary(.{
        .name = "hud_ext",
        .root_source_file = b.path("extensions/hud/hud_ext.zig"),
        .target = target,
        .optimize = optimize,
    });
    hud_ext.linkLibC();
    hud_ext.addIncludePath(b.path("sdk"));
    hud_ext.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    hud_ext.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    hud_ext.linkSystemLibrary("raylib");
    hud_ext.linkSystemLibrary("GL");
    hud_ext.linkSystemLibrary("m");
    hud_ext.linkSystemLibrary("pthread");
    hud_ext.linkSystemLibrary("dl");
    hud_ext.linkSystemLibrary("rt");
    hud_ext.linkSystemLibrary("X11");
    hud_ext.root_module.addImport("core", core_mod);

    const hud_install = b.addInstallArtifact(hud_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&hud_install.step);

    // 5. RUN COMMAND
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // 6. TESTS
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/core/orchestrator.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.linkLibC();
    unit_tests.addIncludePath(b.path("sdk"));
    unit_tests.addIncludePath(b.path("src/core"));

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // 7. INTEGRATION TESTS (Bash)
    const integration_test = b.addSystemCommand(&.{ "bash", "tests/run_integration.sh" });
    integration_test.step.dependOn(b.getInstallStep()); // Need the binary built
    const integration_step = b.step("test-integration", "Run integration tests");
    integration_step.dependOn(&integration_test.step);

    const test_all_step = b.step("test-all", "Run ALL tests (Unit + Integration)");
    test_all_step.dependOn(test_step);
    test_all_step.dependOn(integration_step);
}
