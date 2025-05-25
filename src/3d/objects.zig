const std = @import("std");

const c = @import("../imports.zig");
const Renderer = @import("../renderer.zig");
const Types = @import("../types.zig");
const uph3d = @import("./3d.zig");
const Transform = @import("transform.zig").Transform;

pub const Vertex = struct {
    position: Types.Vec3_f32,
    // uv: Types.Vec2_f32,
};

pub const Index = u16;

pub const Mesh = struct {
    vertices: []Vertex,
    indices: []Index,
};

pub const MeshGPU = struct {
    vbo: *c.sdl.SDL_GPUBuffer,
    ibo: *c.sdl.SDL_GPUBuffer,
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

pub const ObjectManager = struct {
    mesh: Mesh,
};
