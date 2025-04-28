const std = @import("std");
const Build = std.Build;
const ResolvedTarget = std.Build.ResolvedTarget;

pub fn build(b: *std.Build) !void {
    const _testbed = b.step("testbed", "compilling testbed app");
    try build_testbed(
        b,
        "test_game",
        std.Build.standardTargetOptions(b, .{}),
        std.Build.standardOptimizeOption(b, .{}),
        .{},
        _testbed,
    );
}

const AppOutOptions = struct {
    plugins: []const []const u8 = &.{},
    preload_path: ?[]const u8 = null,
};

pub fn build_testbed(
    b: *std.Build,
    name: []const u8,
    target: ResolvedTarget,
    optimize: std.builtin.Mode,
    opt: AppOutOptions,
    testbed: *Build.Step,
) !void {
    const assets_install = b.addInstallDirectory(.{
        .source_dir = b.path("examples/assets"),
        .install_dir = .bin,
        .install_subdir = "assets",
    });

    const exe = try create_app(
        b,
        name,
        b.fmt("examples/{s}.zig", .{name}),
        target,
        optimize,
        .{
            .dep_name = null,
            .link_dynamic = opt.plugins.len != 0,
        },
    );

    const install_cmd = b.addInstallArtifact(exe, .{});
    b.step(name, b.fmt("compile {s}", .{name})).dependOn(&install_cmd.step);

    // Create plugins
    for (opt.plugins) |pname| {
        const plugin = createPlugin(
            b,
            pname,
            b.fmt("testbed/plugins/{s}.zig", .{pname}),
            target,
            optimize,
            .{ .dep_name = null, .link_dynamic = true },
        );
        const install_plugin = b.addInstallArtifact(
            plugin,
            .{ .dest_dir = .{ .override = .{ .bin = {} } } },
        );
        b.step(pname, b.fmt("compile plugin {s}", .{pname})).dependOn(&install_plugin.step);
        install_cmd.step.dependOn(&install_plugin.step);
    }

    // Capable of running
    if (target.query.isNative()) {
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(&install_cmd.step);
        run_cmd.step.dependOn(&assets_install.step);
        run_cmd.cwd = b.path("zig-out/bin");
        b.step(b.fmt("run-{s}", .{name}), b.fmt("run {s}", .{name})).dependOn(&run_cmd.step);
    }
    testbed.dependOn(&install_cmd.step);
}

pub fn get_uph_builder(b: *Build, dep_name: ?[]const u8) *Build {
    return if (dep_name) |dep| b.dependency(dep, .{ .skipbuild = true }).builder else b;
}

pub const UphOptions = struct {
    dep_name: ?[]const u8 = "uph",
};

pub fn get_uph_lib(
    b: *Build,
    target: ResolvedTarget,
    optimize: std.builtin.Mode,
    opt: UphOptions,
    linkage: std.builtin.LinkMode,
) struct {
    module: *Build.Module,
    artifact: *Build.Step.Compile,
} {
    const uph_b = get_uph_builder(b, opt.dep_name);

    const uph_lib_mod = uph_b.createModule(.{
        .root_source_file = uph_b.path("./uph/uph.lib"),
        .optimize = optimize,
        .target = target,
        .imports = &.{},
    });

    const lib_uph = b.addLibrary(.{
        .linkage = linkage,
        .name = "uph",
        .root_module = uph_lib_mod,
    });

    const zmath = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
    });
    lib_uph.root_module.addImport("zmath", zmath.module("root"));

    const zgui = b.dependency("zgui", .{
        .target = target,
        .backend = .sdl3_gpu,
    });
    lib_uph.root_module.addImport("zgui", zgui.module("root"));
    lib_uph.linkLibrary(zgui.artifact("imgui"));

    const entt = b.dependency("entt", .{});
    lib_uph.root_module.addImport("ecs", entt.module("zig-ecs"));
    lib_uph.linkSystemLibrary("sdl3");

    lib_uph.addCSourceFiles(.{
        .files = &[_][]const u8{"c/stb_image.c"},
    });

    return .{ .module = uph_lib_mod, .artifact = lib_uph };
}

pub const Dependency = struct {
    name: []const u8,
    mod: *Build.Module,
};

pub const AppOptions = struct {
    dep_name: ?[]const u8 = "uph",
    additional_deps: []const Dependency = &.{},
    link_dynamic: bool = false,
};

pub fn create_app(
    b: *Build,
    name: []const u8,
    game_root: []const u8,
    target: ResolvedTarget,
    optimize: std.builtin.Mode,
    opt: AppOptions,
) !*Build.Step.Compile {
    std.debug.assert(target.result.os.tag == .windows or target.result.os.tag == .linux or target.result.os.tag == .macos);

    const uph = get_uph_lib(b, target, optimize, UphOptions{ .dep_name = opt.dep_name }, if (opt.link_dynamic == true) .dynamic else .static);

    const game = b.createModule(.{
        .root_source_file = b.path(game_root),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "uph", .module = uph.module },
        },
    });

    const builder = get_uph_builder(b, opt.dep_name);
    const root = b.createModule(.{
        .root_source_file = builder.path("uph/entrypoints/app.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "uph", .module = uph.module },
            .{ .name = "game", .module = game },
        },
    });

    // Create executable
    const exe = builder.addExecutable(.{
        .name = name,
        .root_module = root,
    });
    exe.linkLibrary(uph.artifact);

    // Install uph library
    if (opt.link_dynamic) {
        const install_uph = b.addInstallArtifact(uph.artifact, .{ .dest_dir = .{ .override = .{ .bin = {} } } });
        exe.step.dependOn(&install_uph.step);
    }

    return exe;
}

pub fn createPlugin(
    b: *Build,
    name: []const u8,
    plugin_root: []const u8,
    target: ResolvedTarget,
    optimize: std.builtin.Mode,
    opt: AppOptions,
) *Build.Step.Compile {
    std.debug.assert(target.result.os.tag == .windows or target.result.os.tag == .linux or target.result.os.tag == .macos);
    std.debug.assert(opt.link_dynamic);
    const uph = get_uph_lib(b, target, optimize, UphOptions{ .dep_name = opt.dep_name }, if (opt.link_dynamic == true) .dynamic else .static);

    const plugin = b.createModule(.{
        .root_source_file = b.path(plugin_root),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "uph", .module = uph.module },
        },
    });
    for (opt.additional_deps) |d| {
        plugin.addImport(d.name, d.mod);
    }

    // Create root module
    const builder = get_uph_builder(b, opt.dep_name);
    const root = b.createModule(.{
        .root_source_file = builder.path("uph/entrypoints/plugin.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "uph", .module = uph.module },
            .{ .name = "plugin", .module = plugin },
        },
    });

    // Create shared library
    const lib = b.addSharedLibrary(.{
        .name = name,
        .root_module = root,
    });
    lib.linkLibrary(uph.artifact);

    // Install uph library
    const install_uph = b.addInstallArtifact(uph.artifact, .{ .dest_dir = .{ .override = .{ .bin = {} } } });
    lib.step.dependOn(&install_uph.step);

    return lib;
}

fn run(exe: *std.Build.Step.Compile, b: *std.Build) !void {
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
