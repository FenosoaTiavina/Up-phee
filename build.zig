const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const uph = getModule(b, target, optimize);

    const exe = b.addExecutable(.{
        .name = "testbed",
        .root_source_file = b.path("testbed/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("uph", uph);
    b.installArtifact(exe);

    setupRunStep(b, exe);
}

pub fn getModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/uph.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zmath = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("zmath", zmath.module("root"));

    const zgui = b.dependency("zgui", .{
        .target = target,
        .backend = .sdl3_gpu,
    });
    mod.addImport("zgui", zgui.module("root"));
    mod.linkLibrary(zgui.artifact("imgui"));

    const entt = b.dependency("entt", .{});
    mod.addImport("ecs", entt.module("zig-ecs"));

    mod.linkSystemLibrary("sdl3", .{});

    return mod;
}

pub fn setupRunStep(
    b: *std.Build,
    testbed: *std.Build.Step.Compile,
) void {
    const run_cmd = b.addRunArtifact(testbed);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
}
