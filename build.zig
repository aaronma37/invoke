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

    // 4.5 JOURNAL (PERSISTENCE) EXTENSION
    const journal_ext = b.addSharedLibrary(.{
        .name = "journal_ext",
        .root_source_file = b.path("extensions/journal/journal_ext.zig"),
        .target = target,
        .optimize = optimize,
    });
    journal_ext.linkLibC();
    journal_ext.addIncludePath(b.path("sdk"));
    journal_ext.root_module.addImport("core", core_mod);

    const journal_install = b.addInstallArtifact(journal_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&journal_install.step);

    // 4.6 AUDIO (MINIAUDIO) EXTENSION
    const audio_ext = b.addSharedLibrary(.{
        .name = "audio_ext",
        .root_source_file = b.path("extensions/audio/miniaudio_ext.zig"),
        .target = target,
        .optimize = optimize,
    });
    audio_ext.linkLibC();
    audio_ext.addIncludePath(b.path("sdk"));
    audio_ext.addIncludePath(b.path("ext/miniaudio"));
    audio_ext.addCSourceFile(.{ .file = b.path("extensions/audio/miniaudio_impl.c"), .flags = &.{} });
    audio_ext.linkSystemLibrary("m");
    audio_ext.linkSystemLibrary("dl");
    audio_ext.linkSystemLibrary("pthread");
    audio_ext.root_module.addImport("core", core_mod);

    const audio_install = b.addInstallArtifact(audio_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&audio_install.step);

    // 4.7 NETWORK (TIDEPOOL) EXTENSION
    const network_ext = b.addSharedLibrary(.{
        .name = "network_ext",
        .root_source_file = b.path("extensions/network/tide_pool_ext.zig"),
        .target = target,
        .optimize = optimize,
    });
    network_ext.linkLibC();
    network_ext.addIncludePath(b.path("sdk"));
    network_ext.root_module.addImport("core", core_mod);

    const network_install = b.addInstallArtifact(network_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&network_install.step);

    // 4.8 INSPECTOR (MOTHERBOARD UI) EXTENSION
    const inspector_ext = b.addSharedLibrary(.{
        .name = "inspector_ext",
        .root_source_file = b.path("extensions/inspector/inspector_ext.zig"),
        .target = target,
        .optimize = optimize,
    });
    inspector_ext.linkLibC();
    inspector_ext.addIncludePath(b.path("sdk"));
    inspector_ext.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    inspector_ext.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    inspector_ext.linkSystemLibrary("raylib");
    inspector_ext.linkSystemLibrary("GL");
    inspector_ext.linkSystemLibrary("m");
    inspector_ext.linkSystemLibrary("pthread");
    inspector_ext.linkSystemLibrary("dl");
    inspector_ext.linkSystemLibrary("rt");
    inspector_ext.linkSystemLibrary("X11");
    inspector_ext.root_module.addImport("core", core_mod);

    const inspector_install = b.addInstallArtifact(inspector_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&inspector_install.step);

    // 4.9 TENSOR (SOTA SIMD) EXTENSION
    const tensor_ext = b.addSharedLibrary(.{
        .name = "tensor_ext",
        .root_source_file = b.path("extensions/tensor/tensor_ext.zig"),
        .target = target,
        .optimize = optimize, // Usually you want ReleaseFast for this, but using 'optimize' for consistency
    });
    tensor_ext.linkLibC();
    tensor_ext.addIncludePath(b.path("sdk"));
    tensor_ext.root_module.addImport("core", core_mod);

    const tensor_install = b.addInstallArtifact(tensor_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&tensor_install.step);

    // 4.10 PYTHON (SOTA ECOSYSTEM) EXTENSION
    const python_ext = b.addSharedLibrary(.{
        .name = "python_ext",
        .root_source_file = b.path("extensions/python/python_ext.zig"),
        .target = target,
        .optimize = optimize,
    });
    python_ext.linkLibC();
    python_ext.addIncludePath(b.path("sdk"));
    python_ext.addIncludePath(.{ .cwd_relative = "/usr/include/python3.12" });
    python_ext.addLibraryPath(.{ .cwd_relative = "/usr/lib/python3.12/config-3.12-x86_64-linux-gnu" });
    python_ext.linkSystemLibrary("python3.12");
    python_ext.root_module.addImport("core", core_mod);

    const python_install = b.addInstallArtifact(python_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&python_install.step);

    // 4.11 SQLITE (DATA INTELLIGENCE) EXTENSION
    const sqlite_ext = b.addSharedLibrary(.{
        .name = "sqlite_ext",
        .root_source_file = b.path("extensions/sqlite/sqlite_ext.zig"),
        .target = target,
        .optimize = optimize,
    });
    sqlite_ext.linkLibC();
    sqlite_ext.addIncludePath(b.path("sdk"));
    sqlite_ext.linkSystemLibrary("sqlite3");
    sqlite_ext.root_module.addImport("core", core_mod);

    const sqlite_install = b.addInstallArtifact(sqlite_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&sqlite_install.step);

    // 4.12 WEBGPU (MASSIVE SWARM) EXTENSION
    const webgpu_ext = b.addSharedLibrary(.{
        .name = "webgpu_ext",
        .root_source_file = b.path("extensions/webgpu/webgpu_ext.zig"),
        .target = target,
        .optimize = optimize,
    });
    webgpu_ext.linkLibC();
    webgpu_ext.addIncludePath(b.path("sdk"));
    webgpu_ext.addIncludePath(b.path("ext/wgpu"));
    webgpu_ext.addLibraryPath(b.path("ext/wgpu"));
    webgpu_ext.linkSystemLibrary("wgpu_native");
    webgpu_ext.linkSystemLibrary("m");
    webgpu_ext.linkSystemLibrary("dl");
    webgpu_ext.linkSystemLibrary("pthread");
    webgpu_ext.root_module.addImport("core", core_mod);

    const webgpu_install = b.addInstallArtifact(webgpu_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&webgpu_install.step);

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
