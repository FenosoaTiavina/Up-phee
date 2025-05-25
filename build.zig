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

const LibMod = struct {
    module: *std.Build.Module,
    artifact: *std.Build.Step.Compile,
};
const AppOptions = struct {
    additional_deps: []const Dependency = &.{},
    dep_name: ?[]const u8 = "uph",
    plugins: []const []const u8,
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    var uph = getLibrary(b, target, optimize, UphOptions{ .link_dynamic = true });

    const testbed = createApp(
        b,
        target,
        optimize,
        "testbed",
        "testbed/app.zig",
        &uph,
        .{ .plugins = &.{"test_hotreload"} },
    );

    const install_uph = b.addInstallArtifact(
        uph.artifact,
        .{
            .dest_dir = .{ .override = .{ .custom = "../bin" } },
        },
    );

    setupCompileStep(b, "uph", install_uph);

    const install_cmd = b.addInstallArtifact(
        testbed,
        .{
            .dest_dir = .{ .override = .{ .custom = "../bin" } },
        },
    );

    install_cmd.step.dependOn(&install_uph.step);

    setupCompileStep(b, "testbed", install_cmd);

    setupRunStep(b, install_cmd.artifact);
}

pub fn createApp(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    app_name: []const u8,
    app_root: []const u8,
    uph: *LibMod,
    opt: AppOptions,
) *std.Build.Step.Compile {
    const game = b.createModule(.{
        .root_source_file = b.path(app_root),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "uph", .module = uph.module },
        },
    });

    const root = b.createModule(.{
        .root_source_file = b.path("src/app/entrypoint.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "uph", .module = uph.module },
            .{ .name = "game", .module = game },
        },
    });

    const exe = b.addExecutable(.{
        .name = b.fmt("{s}.out", .{app_name}),
        .root_module = root,
    });

    for (opt.plugins) |pname| {
        const plugin = createPlugin(
            b,
            pname,
            b.fmt("testbed/plugins/{s}.zig", .{pname}),
            target,
            optimize,
            uph,
            .{ .dep_name = null, .link_dynamic = true },
        );
        const install_plugin = b.addInstallArtifact(
            plugin,
            .{
                .dest_dir = .{
                    .override = .{ .custom = "../bin" },
                },
            },
        );
        b.step(b.fmt("plug-{s}", .{pname}), b.fmt("compile plugin: {s}", .{pname})).dependOn(&install_plugin.step);
        install_plugin.step.dependOn(&exe.step);
    }

    return exe;
}

pub fn getLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opt: UphOptions,
) LibMod {
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

    const zmath = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
    });
    uph_mod.addImport("zmath", zmath.module("root"));

    const zgui = b.dependency("zgui", .{
        .target = target,
        .backend = .sdl3_gpu,
    });
    uph_mod.addImport("zgui", zgui.module("root"));
    uph_mod.linkLibrary(zgui.artifact("imgui"));

    const entt = b.dependency("entt", .{});
    uph_mod.addImport("ecs", entt.module("zig-ecs"));

    uph_mod.addCSourceFiles(
        .{
            .files = &.{"./c/stb_image.c"},
        },
    );
    uph_mod.linkSystemLibrary("sdl3", .{});

    const lib: *std.Build.Step.Compile = b.addLibrary(.{
        .name = "uph",
        .root_module = uph_mod,
        .linkage = if (opt.link_dynamic) .dynamic else .static,
    });

    return .{ .module = uph_mod, .artifact = lib };
}

pub fn createPlugin(
    b: *std.Build,
    name: []const u8,
    plugin_root: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    uph: *LibMod,
    opt: UphOptions,
) *std.Build.Step.Compile {
    std.debug.assert(target.result.os.tag == .windows or target.result.os.tag == .linux or target.result.os.tag == .macos);
    std.debug.assert(opt.link_dynamic);

    // Create plugin module
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
    const builder = getUphBuilder(b, opt.dep_name);
    const root = b.createModule(.{
        .root_source_file = builder.path("src/plugin/plugin_entry.zig"),
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

    return lib;
}

fn getUphBuilder(b: *std.Build, dep_name: ?[]const u8) *std.Build {
    return if (dep_name) |dep| b.dependency(dep, .{ .skipbuild = true }).builder else b;
}

fn setupCompileStep(
    b: *std.Build,
    name: []const u8,
    install: *std.Build.Step.InstallArtifact,
) void {
    const compile_step = b.step(b.fmt("compile-{s}", .{name}), "Run the application");
    compile_step.dependOn(&install.step);
}

pub fn setupRunStep(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
) void {
    const run_cmd = b.addRunArtifact(exe);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
}
