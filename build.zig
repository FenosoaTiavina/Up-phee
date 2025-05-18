const std = @import("std");
const builtin = @import("builtin");

pub const Dependency = struct {
    name: []const u8,
    mod: *std.Build.Module,
};

pub const UphOptions = struct {
    additional_deps: []const Dependency = &.{},
    dep_name: ?[]const u8 = "uph",
    link_dynamic: bool = false,
};

pub const Plugin = []const u8;

const AppOptions = struct {
    additional_deps: []const Dependency = &.{},
    plugins: []const []const u8,
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const uph_opt = UphOptions{ .link_dynamic = true };
    const uph = getUphLibrary(b, target, optimize, uph_opt);

    const testbed = createApp(
        b,
        "testbed",
        target,
        optimize,
        "./testbed/app.zig",
        uph.module,
        uph.artifact,
        .{ .plugins = &.{} },
    );

    const install_test_cmd = b.addInstallArtifact(
        testbed,
        .{ .dest_dir = .{
            .override = .{ .custom = "./bin" },
        } },
    );

    if (uph_opt.link_dynamic) {
        const install_uph = b.addInstallArtifact(uph.artifact, .{
            .dest_dir = .{
                .override = .{ .custom = "./bin" },
            },
        });
        install_test_cmd.step.dependOn(&install_uph.step);
    }

    setupRunStep(b, testbed);
}

fn getUphLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opt: UphOptions,
) struct {
    module: *std.Build.Module,
    artifact: *std.Build.Step.Compile,
} {
    const bos = b.addOptions();
    bos.addOption(bool, "link_dynamic", opt.link_dynamic);

    const uph_mod = b.createModule(.{
        .root_source_file = b.path("src/uph.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = bos.createModule() },
        },
    });

    const library_mod =
        b.createModule(.{
            .target = target,
            .optimize = optimize,
        });

    {
        const zmath = b.dependency("zmath", .{
            .target = target,
            .optimize = optimize,
        });
        library_mod.addImport("zmath", zmath.module("root"));
    }

    {
        const zgui = b.dependency("zgui", .{
            .target = target,
            .backend = .sdl3_gpu,
        });

        library_mod.addImport("zgui", zgui.module("root"));
        library_mod.linkLibrary(zgui.artifact("imgui"));
    }

    {
        const entt = b.dependency("entt", .{});
        library_mod.addImport("ecs", entt.module("zig-ecs"));
    }

    {
        library_mod.addCSourceFiles(
            .{
                .files = &.{"./c/stb_image.c"},
            },
        );
    }

    var library: *std.Build.Step.Compile = undefined;

    library = b.addLibrary(
        .{
            .name = "uph",
            .root_module = library_mod,
            .linkage = if (opt.link_dynamic) .dynamic else .static,
        },
    );

    library.linkSystemLibrary("sdl3");

    return .{ .module = uph_mod, .artifact = library };
}

fn createApp(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    root_file: []const u8,
    uph_module: *std.Build.Module,
    uph_lib: *std.Build.Step.Compile,
    opt: AppOptions,
) *std.Build.Step.Compile {
    const game = b.createModule(.{
        .root_source_file = b.path(root_file),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "uph", .module = uph_module },
        },
    });

    for (opt.additional_deps) |d| {
        game.addImport(d.name, d.mod);
    }

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/entrypoin.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "jok", .module = uph_module },
            .{ .name = "game", .module = game },
        },
    });

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = root_module,
    });

    exe.linkLibrary(uph_lib);

    return exe;
}

fn getUphBuilder(b: *std.Build, dep_name: ?[]const u8) *std.Build {
    return if (dep_name) |dep| b.dependency(dep, .{ .skipbuild = true }).builder else b;
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
