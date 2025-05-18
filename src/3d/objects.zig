const std = @import("std");

const c = @import("../imports.zig");

const uph = @import("../uph.zig");

const Renderer = uph.Renderer;
const Types = uph.Types;
const uph3d = uph.uph3d;
const Transform = uph3d.Transform;

pub const Vertex = struct {
    position: Types.Vec3_f32,
    // uv: Types.Vec2_f32,
};

pub const Index = u16;

pub const Mesh = struct {
    vertices: []Vertex,
    indices: []Index,
};

pub const Renderable = struct {
    mesh: u32,
    trs: uph3d.Transform,
};

pub const UniformBufferObject = struct {
    model: Types.Mat4_f32,
    view: Types.Mat4_f32,
    projection: Types.Mat4_f32,
};

pub fn createMesh(vertices: []const Vertex, indices: []const u16) Mesh {
    return Mesh{
        .vertices = @constCast(vertices),
        .indices = @constCast(indices),
    };
}
