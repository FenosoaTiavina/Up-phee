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
            .{
                // f-tl
                .position = .{ -0.5, 0.5, 0.5 },
                // .uv = .{ 0, 0 },
            },
            .{
                // f-tr
                .position = .{ 0.5, 0.5, 0.5 },
                // .uv = .{ 0, 1 },
            },
            .{
                // f-bl
                .position = .{ -0.5, -0.5, 0.5 },
                // .uv = .{ 1, 0 },
            },
            .{
                // f-br
                .position = .{ 0.5, -0.5, 0.5 },
                // .uv = .{ 1, 1 },
            },
            .{
                // b-tl
                .position = .{ -0.5, 0.5, -0.5 },
                // .uv = .{ 1, 1 },
            },
            .{
                // b-tr
                .position = .{ 0.5, 0.5, -0.5 },
                // .uv = .{ 0, 1 },
            },
            .{
                // b-bl
                .position = .{ -0.5, -0.5, -0.5 },
                // .uv = .{ 1, 0 },
            },
            .{
                // b-br
                .position = .{ 0.5, -0.5, -0.5 },
                // .uv = .{ 0, 0 },
            },
        };
        const cube_indices = [_]Objects.Index{
            //Top
            2, 6, 7,
            2, 3, 7,
            //Bottom
            0, 4, 5,
            0, 1, 5,
            //Left
            0, 2, 6,
            0, 4, 6,
            //Right
            1, 3, 7,
            1, 5, 7,
            //Front
            0, 2, 3,
            0, 1, 3,
            //Back
            4, 6, 7,
            4, 5, 7,
        };
        return Cube{
            .object = .{
                .mesh = Objects.createMesh(&cube_verts, &cube_indices),
                .model = Transform.Transform.init(),
            },
        };
    }
    pub fn addToBatch(self: *Cube, b: *uph.uph3d.Batch) !void {
        try b.add(self.object.mesh);
    }
};
