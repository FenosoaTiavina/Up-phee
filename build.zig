const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const uph_module = getModule(b, "uph", "uph");

    const testbed_module = b.createModule(.{
        .root_source_file = b.path("src/testbed/main.zig"),
        .optimize = optimize,
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "testbed",
        .root_module = testbed_module,
    });
    exe.root_module.addImport("uph", uph_module);
}

pub const LibType = enum(i32) {
    static,
    dynamic, // requires DYLD_LIBRARY_PATH to point to the dylib path
    exe_compiled,
};

pub fn getModule(b: *std.Build, comptime mod_name: []const u8, comptime _namespace: []const u8) *std.Build.Module {
    return b.addModule(.{
        .root_source_file = b.path("src/" ++ _namespace ++ "/uph.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .name = mod_name,
    });
}

/// prefix_path is used to add package paths. It should be the the same path used to include this build file
pub fn linkArtifact(b: *std.Build, artifact: *std.Build.Step.Compile, lib_type: LibType, comptime name: []const u8, comptime namespace: []const u8) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    switch (lib_type) {
        .static => {
            const lib = b.addStaticLibrary(.{ .name = "uph", .root_source_file = "uph.zig", .optimize = optimize, .target = target });
            b.installArtifact(lib);

            artifact.linkLibrary(lib);
        },
        .dynamic => {
            const lib = b.addSharedLibrary(.{ .name = "uph", .root_source_file = "uph.zig", .optimize = optimize, .target = target });
            b.installArtifact(lib);

            artifact.linkLibrary(lib);
        },
        else => {},
    }

    artifact.root_module.addImport("uph", getModule(name, namespace));
}
