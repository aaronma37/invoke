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

    const simd_mod = b.createModule(.{
        .root_source_file = b.path("sdk/moontide_simd.zig"),
    });

    const moontide_mod = b.createModule(.{
        .root_source_file = b.path("sdk/moontide.zig"),
    });
    moontide_mod.addImport("core", core_mod);

    const kan_mod = b.createModule(.{
        .root_source_file = b.path("src/core/kan_network.zig"),
    });
    kan_mod.addIncludePath(b.path("src/core"));
    kan_mod.addIncludePath(b.path("sdk"));

    // 1. THE KERNEL (Pure Silicon Pulse Oscillator)
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

    // 3. SPIKING SIMD (AVX-512) EXTENSION
    const spiking_ext = b.addSharedLibrary(.{
        .name = "spiking_simd_ext",
        .root_source_file = b.path("extensions/spiking_simd/spiking_ext.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_model = .native }),
        .optimize = optimize,
    });
    spiking_ext.linkLibC();
    spiking_ext.addIncludePath(b.path("sdk"));
    spiking_ext.root_module.addImport("moontide", moontide_mod);
    spiking_ext.root_module.addImport("moontide_simd", simd_mod);

    const spiking_install = b.addInstallArtifact(spiking_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&spiking_install.step);

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

    // 5. INSPECTOR (MOTHERBOARD UI) EXTENSION
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

    // 5. WEBGPU EXTENSION (VRAM Wires)
    const webgpu_ext = b.addSharedLibrary(.{
        .name = "webgpu_ext",
        .root_source_file = b.path("extensions/webgpu/webgpu_ext.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_model = .native }),
        .optimize = optimize,
    });
    webgpu_ext.linkLibC();
    webgpu_ext.addIncludePath(b.path("sdk"));
    webgpu_ext.addIncludePath(b.path("ext/wgpu"));
    webgpu_ext.addLibraryPath(b.path("ext/wgpu"));
    webgpu_ext.linkSystemLibrary("wgpu_native");
    webgpu_ext.linkSystemLibrary("m");
    webgpu_ext.linkSystemLibrary("pthread");
    webgpu_ext.linkSystemLibrary("dl");
    webgpu_ext.root_module.addImport("core", core_mod);

    const webgpu_install = b.addInstallArtifact(webgpu_ext, .{
        .dest_dir = .{ .override = .{ .custom = "../ext" } },
    });
    b.getInstallStep().dependOn(&webgpu_install.step);

    // 6. KAN TRAINER TOOL
    const train_exe = b.addExecutable(.{
        .name = "kan-train",
        .root_source_file = b.path("src/tools/train.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_model = .native }),
        .optimize = optimize,
    });
    train_exe.linkLibC();
    train_exe.addIncludePath(b.path("src/core"));
    train_exe.addIncludePath(b.path("sdk"));
    train_exe.root_module.addImport("kan", kan_mod);
    b.installArtifact(train_exe);

    const train_run = b.addRunArtifact(train_exe);
    train_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| train_run.addArgs(args);
    const train_step = b.step("train", "Run the KAN trainer");
    train_step.dependOn(&train_run.step);

    // KAN BENCHMARK TOOL
    const bench_exe = b.addExecutable(.{
        .name = "benchmark-kan",
        .root_source_file = b.path("src/tools/benchmark_kan.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_model = .native }),
        .optimize = optimize,
    });
    bench_exe.linkLibC();
    bench_exe.addIncludePath(b.path("src/core"));
    bench_exe.addIncludePath(b.path("sdk"));
    bench_exe.root_module.addImport("kan", kan_mod);
    b.installArtifact(bench_exe);

    const bench_run = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run the KAN benchmark");
    bench_step.dependOn(&bench_run.step);

    // KAN TO PCB TOOL (Validation)
    const pcb_exe = b.addExecutable(.{
        .name = "kan-to-pcb",
        .root_source_file = b.path("src/tools/kan_to_pcb.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_model = .native }),
        .optimize = optimize,
    });
    pcb_exe.linkLibC();
    pcb_exe.root_module.addImport("kan", kan_mod);
    b.installArtifact(pcb_exe);

    const pcb_run = b.addRunArtifact(pcb_exe);
    const pcb_step = b.step("debug-kan", "Sample model.kan to kan_debug.pcb");
    pcb_step.dependOn(&pcb_run.step);

    // KAN TO OBJ TOOL (Reconstruction)
    const obj_exe = b.addExecutable(.{
        .name = "kan-to-obj",
        .root_source_file = b.path("src/tools/reconstruct.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_model = .native }),
        .optimize = optimize,
    });
    obj_exe.linkLibC();
    obj_exe.root_module.addImport("kan", kan_mod);
    b.installArtifact(obj_exe);

    const obj_run = b.addRunArtifact(obj_exe);
    const obj_step = b.step("reconstruct-kan", "Extract model.kan to bunny_reconstructed.obj");
    obj_step.dependOn(&obj_run.step);

    // KAN UV SAMPLER TOOL
    const uv_exe = b.addExecutable(.{
        .name = "uv-sampler",
        .root_source_file = b.path("src/tools/uv_sampler.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_model = .native }),
        .optimize = optimize,
    });
    uv_exe.linkLibC();
    uv_exe.root_module.addImport("kan", kan_mod);
    b.installArtifact(uv_exe);

    // KAN DISPLACED RECONSTRUCTION TOOL
    const dis_exe = b.addExecutable(.{
        .name = "reconstruct-displaced",
        .root_source_file = b.path("src/tools/reconstruct_displaced.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_model = .native }),
        .optimize = optimize,
    });
    dis_exe.linkLibC();
    dis_exe.root_module.addImport("kan", kan_mod);
    b.installArtifact(dis_exe);

    // 7. RUN COMMAND
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the Moontide Neural Oscillator");
    run_step.dependOn(&run_cmd.step);

    // 7. TESTS
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("tests/neuromorphic_core_test.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_model = .native }),
        .optimize = optimize,
    });
    unit_tests.linkLibC();
    unit_tests.addIncludePath(b.path("sdk"));
    unit_tests.addIncludePath(b.path("src/core"));
    unit_tests.root_module.addImport("core", core_mod);
    unit_tests.root_module.addImport("moontide_simd", simd_mod);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run silicon unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
