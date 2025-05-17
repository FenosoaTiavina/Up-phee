const std = @import("std");

const uph = @import("../uph.zig");

const c = @import("../imports.zig");
const Assets = @import("assets.zig");
const Objects = @import("objects.zig");
const Transform = @import("transform.zig");

pub const Cube = struct {
    object: Objects.Object,
    pub fn cube() Cube {
        const cube_verts = [_]Objects.Vertex{
            .{ // top-left
                .position = .{ -0.5, 0.5, 0 },
            },
            .{ // top-right
                .position = .{ 0.5, 0.5, 0 },
            },
            .{ // bottom-right
                .position = .{ 0.5, -0.5, 0 },
            },
            .{ // bottom-left
                .position = .{ -0.5, -0.5, 0 },
            },
        };
        const cube_indices = [_]Objects.Index{
            0, 1, 2, 2, 3, 0, // face 1
        };
        return Cube{
            .object = .{
                .mesh = Objects.createMesh(&cube_verts, &cube_indices),
                .model = Transform.Transform.init(),
            },
        };
    }
    pub fn addToBatch(self: *Cube, b: *uph.uph3d.Batch.Batch) !void {
        try b.add(self.object.mesh);
    }
};
