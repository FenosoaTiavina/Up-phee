const std = @import("std");
const Build = std.Build;
const ResolvedTarget = std.Build.ResolvedTarget;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build framework
    const framework = buildUphFramework(b, target, optimize);

    // Build testbed executable
    const testbed = buildTestbed(b, target, optimize, framework);

    // Create run step
    setupRunStep(b, testbed);
}

fn buildUphFramework(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) struct {
    module: *std.Build.Module,
    artifact: *std.Build.Step.Compile,
} {
    // Create framework module with target specified
    const framework_module = b.createModule(.{
        .root_source_file = b.path("src/uph/uph.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_uph.root_module.addImport("zmath", zmath.module("root"));

    // Add external dependencies
    const zmath = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
    });
    framework_module.addImport("zmath", zmath.module("root"));

    const zgui = b.dependency("zgui", .{
        .target = target,
        .backend = .sdl3_gpu,
    });
    framework_module.addImport("zgui", zgui.module("root"));

    const entt = b.dependency("entt", .{});
    framework_module.addImport("ecs", entt.module("zig-ecs"));

    // Build shared library
    const lib = b.addSharedLibrary(.{
        .name = "uph",
        .root_source_file = b.path("src/uph/uph.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.root_module = framework_module;
    lib.linkSystemLibrary("sdl3");
    lib.linkSystemLibrary("c");
    lib.addCSourceFiles(.{
        .files = &.{"c/stb_image.c"},
    });

    b.installArtifact(lib);

    return .{
        .module = framework_module,
        .artifact = lib,
    };
}

fn buildTestbed(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    framework: anytype,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "testbed",
        .root_source_file = b.path("src/testbed/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add framework dependency
    exe.root_module.addImport("uph", framework.module);
    exe.linkLibrary(framework.artifact);

    b.installArtifact(exe);
    return exe;
}

fn setupRunStep(
    b: *std.Build,
    testbed: *std.Build.Step.Compile,
) void {
    const run_cmd = b.addRunArtifact(testbed);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
}
