const Vertex = @import("mesh.zig").Vertex;
const Index = @import("mesh.zig").Index;

const Batch = @import("batch.zig");

pub const Cube = struct {
    vertices: []const Vertex = &[_]Vertex{
        .{ // 0
            .position = .{ -0.5, -0.5, 0.5 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 0.0, 0.0 },
        },
        .{ // 1
            .position = .{ 0.5, -0.5, 0.5 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 0.0, 0.0 },
        },
        .{ // 2
            .position = .{ -0.5, 0.5, 0.5 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 0.0, 0.0 },
        },
        .{ // 3
            .position = .{ 0.5, 0.5, 0.5 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 0.0, 0.0 },
        },
        .{ // 0
            .position = .{ -0.5, -0.5, -0.5 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 0.0, 0.0 },
        },
        .{ // 1
            .position = .{ 0.5, -0.5, -0.5 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 0.0, 0.0 },
        },
        .{ // 2
            .position = .{ -0.5, 0.5, -0.5 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 0.0, 0.0 },
        },
        .{ // 3
            .position = .{ 0.5, 0.5, -0.5 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 0.0, 0.0 },
        },
    },
    indices: []const Index = &[_]Index{
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
    },

    pub fn cube() Cube {
        return Cube{};
    }
    pub fn addToBatch(self: *Cube, b: *Batch) void {
        b.addMesh(self.vertices, self.indices);
    }
};
