const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const uph = getModule(b, target, optimize, UphOptions{ .link_dynamic = true });
    const lib_uph = b.addLibrary(.{ .linkage = .dynamic, .name = "uph", .root_module = uph, .version = .{
        .major = 0,
        .minor = 0,
        .patch = 1,
    } });

    const install_uph = b.addInstallArtifact(
        lib_uph,
        .{
            .dest_dir = .{
                .override = .{ .bin = {} },
            },
        },
    );

    const exe = b.addExecutable(.{
        .name = "testbed",
        .root_source_file = b.path("testbed/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("uph", uph);
    b.installArtifact(exe);
    exe.step.dependOn(&install_uph.step);

    setupRunStep(b, exe);
}

pub const UphOptions = struct {
    link_dynamic: bool = false,
};

pub fn getModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, opt: UphOptions) *std.Build.Module {
    const bos = b.addOptions();
    bos.addOption(bool, "link_dynamic", opt.link_dynamic);

    const mod = b.createModule(.{
        .root_source_file = b.path("src/uph.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = bos.createModule() },
        },
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

    mod.addCSourceFiles(
        .{
            .files = &.{"./c/stb_image.c"},
        },
    );

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
