const std = @import("std");

pub fn build(builder: *std.Build) !void {
    const target = builder.standardTargetOptions(.{});
    const optimize = .Debug;

    var exe: *std.Build.Step.Compile = undefined;
    exe = builder.addExecutable(.{
        .name = "game_sdl3",
        .root_source_file = builder.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zalgebra = builder.dependency("zalgebra", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zalgebra", zalgebra.module("zalgebra"));

    const zgui = builder.dependency("zgui", .{
        .target = target,
        .backend = .sdl3_gpu,
        // .with_implot = true,
        // .with_node_editor = true,
        // .with_te = true,
    });
    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.linkLibrary(zgui.artifact("imgui"));

    exe.linkSystemLibrary("sdl3");

    exe.addCSourceFiles(.{
        .files = &[_][]const u8{"c/stb_image.c"},
    });

    builder.installArtifact(exe);

    try run(exe, builder);
}

fn run(exe: *std.Build.Step.Compile, builder: *std.Build) !void {
    const run_cmd = builder.addRunArtifact(exe);

    run_cmd.step.dependOn(builder.getInstallStep());

    if (builder.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = builder.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
