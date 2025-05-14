const std = @import("std");

const uph = @import("uph");

const c = @import("../imports.zig");
const Assets = @import("assets.zig");
const Objects = @import("objects.zig");

pub const Cube = struct {
    object: Objects.Object = .{
        .mesh = .{
            .vertices = .{
                Objects.Vertex{
                    // f-tl
                    .position = uph.Types.Vec3_f32{ -0.5, 0.5, 0.5 },
                    .uv = uph.Types.Vec2_f32{ 0, 0 },
                },
                Objects.Vertex{
                    // f-tr
                    .position = uph.Types.Vec3_f32{ 0.5, 0.5, 0.5 },
                    .uv = uph.Types.Vec2_f32{ 0, 1 },
                },
                Objects.Vertex{
                    // f-bl
                    .position = uph.Types.Vec3_f32{ -0.5, -0.5, 0.5 },
                    .uv = uph.Types.Vec2_f32{ 1, 0 },
                },
                Objects.Vertex{
                    // f-br
                    .position = uph.Types.Vec3_f32{ 0.5, -0.5, 0.5 },
                    .uv = uph.Types.Vec2_f32{ 1, 1 },
                },
                Objects.Vertex{
                    // b-tl
                    .position = uph.Types.Vec3_f32{ -0.5, 0.5, -0.5 },
                    .uv = uph.Types.Vec2_f32{ 1, 1 },
                },
                Objects.Vertex{
                    // b-tr
                    .position = uph.Types.Vec3_f32{ 0.5, 0.5, -0.5 },
                    .uv = uph.Types.Vec2_f32{ 0, 1 },
                },
                Objects.Vertex{
                    // b-bl
                    .position = uph.Types.Vec3_f32{ -0.5, -0.5, -0.5 },
                    .uv = uph.Types.Vec2_f32{ 1, 0 },
                },
                Objects.Vertex{
                    // b-br
                    .position = uph.Types.Vec3_f32{ 0.5, -0.5, -0.5 },
                    .uv = uph.Types.Vec2_f32{ 0, 0 },
                },
            },
            .indices = .{},
            .num_indices = 36,
        },
    },
};
