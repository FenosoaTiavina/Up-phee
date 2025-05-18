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
    dep_name: ?[]const u8 = "uph",
    plugins: []const []const u8,
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const testbed = createUphApp(
        b,
        target,
        optimize,
        "testbed",
        "testbed/app.zig",
        .{
            .plugins = &.{"test_hotreload"},
        },
    );

    setupRunStep(b, testbed);
}

pub fn createUphApp(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    app_name: []const u8,
    app_root: []const u8,
    opt: AppOptions,
) *std.Build.Step.Compile {
    const uph = getLibrary(b, target, optimize, UphOptions{ .link_dynamic = true });

    const game = b.createModule(.{
        .root_source_file = b.path(app_root),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "uph", .module = uph.module },
        },
    });

    const root = b.createModule(.{
        .root_source_file = b.path("src/entrypoint.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "uph", .module = uph.module },
            .{ .name = "game", .module = game },
        },
    });

    const exe = b.addExecutable(.{
        .name = app_name,
        .root_module = root,
    });

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
            .{
                .dest_dir = .{
                    .override = .{ .custom = "bin" },
                },
            },
        );
        b.step(pname, b.fmt("compile plugin {s}", .{pname})).dependOn(&install_plugin.step);
        install_plugin.step.dependOn(&exe.step);
    }

    const install_uph = b.addInstallArtifact(
        uph.artifact,
        .{
            .dest_dir = .{
                .override = .{ .custom = "bin" },
            },
        },
    );

    b.installArtifact(exe);

    exe.step.dependOn(&install_uph.step);

    return exe;
}

pub fn getLibrary(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, opt: UphOptions) struct {
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

    var lib: *std.Build.Step.Compile = undefined;
    lib = if (opt.link_dynamic)
        b.addSharedLibrary(.{ .name = "uph", .root_module = uph_mod })
    else
        b.addStaticLibrary(.{ .name = "uph", .root_module = uph_mod });

    return .{ .module = uph_mod, .artifact = lib };
}

pub fn createPlugin(
    b: *std.Build,
    name: []const u8,
    plugin_root: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    opt: UphOptions,
) *std.Build.Step.Compile {
    std.debug.assert(target.result.os.tag == .windows or target.result.os.tag == .linux or target.result.os.tag == .macos);
    std.debug.assert(opt.link_dynamic);
    const uph = getLibrary(b, target, optimize, .{
        .dep_name = opt.dep_name,
        .link_dynamic = opt.link_dynamic,
    });

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
    const builder = getuphBuilder(b, opt.dep_name);
    const root = b.createModule(.{
        .root_source_file = builder.path("src/plugin_entry.zig"),
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

    const install_uph = b.addInstallArtifact(uph.artifact, .{
        .dest_dir = .{
            .override = .{ .custom = "bin" },
        },
    });

    lib.step.dependOn(&install_uph.step);

    return lib;
}

fn getuphBuilder(b: *std.Build, dep_name: ?[]const u8) *std.Build {
    return if (dep_name) |dep| b.dependency(dep, .{ .skipbuild = true }).builder else b;
}

pub fn setupRunStep(
    b: *std.Build,
    testbed: *std.Build.Step.Compile,
) void {
    const run_cmd = b.addRunArtifact(testbed);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.setCwd(b.path("./bin"));

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
}
