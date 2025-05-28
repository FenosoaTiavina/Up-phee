const std = @import("std");

const uph = @import("../uph.zig");
const c = uph.clib;
const Renderer = uph.Renderer;
const Types = uph.Types;
const uph_3d = uph.uph_3d;

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

pub fn createMeshGPU(device: *c.sdl.SDL_GPUDevice, vertex_max: u32, index_max: u32) MeshGPU {
    return MeshGPU{
        .vbo = uph.Buffer.createBuffer(
            device,
            c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
            @intCast(@sizeOf(Vertex) * vertex_max),
        ).?,
        .ibo = uph.Buffer.createBuffer(
            device,
            c.sdl.SDL_GPU_BUFFERUSAGE_INDEX,
            @intCast(@sizeOf(Index) * index_max),
        ).?,
    };
}

pub fn releaseMeshGPU(
    device: *c.sdl.SDL_GPUDevice,
    mesh_gpu: *MeshGPU,
) void {
    c.sdl.SDL_ReleaseGPUBuffer(device, mesh_gpu.vbo);
    c.sdl.SDL_ReleaseGPUBuffer(device, mesh_gpu.ibo);
}

pub fn createMesh(vertices: []const Vertex, indices: []const u16) Mesh {
    return Mesh{
        .vertices = @constCast(vertices),
        .indices = @constCast(indices),
    };
}

pub const ObjectInstanceManager = @import("./render.instanced.zig").ObjectInstanceManager;
pub const ObjectManager = @import("./render.simple.zig").ObjectManager;
