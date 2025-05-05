const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const testbed = createUphApp(b, target, optimize, "testbed", "testbed/app.zig");
    setupRunStep(b, testbed);
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

pub fn createUphApp(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    app_name: []const u8,
    app_root: []const u8,
) *std.Build.Step.Compile {
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

    const game = b.createModule(.{
        .root_source_file = b.path(app_root),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "uph", .module = uph },
        },
    });

    const root = b.createModule(.{
        .root_source_file = b.path("src/entrypoint.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "uph", .module = uph },
            .{ .name = "game", .module = game },
        },
    });

    const exe = b.addExecutable(.{
        .name = app_name,
        .root_module = root,
    });
    b.installArtifact(exe);
    exe.step.dependOn(&install_uph.step);
    return exe;
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
