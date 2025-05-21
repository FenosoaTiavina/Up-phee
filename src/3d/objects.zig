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

pub const MeshGPU = struct {
    vbo: *c.sdl.SDL_GPUBuffer,
    ibo: *c.sdl.SDL_GPUBuffer,
};

pub const Mesh = struct {
    vertices: []Vertex,
    indices: []Index,
    num_indices: u16,
};

pub const Object = struct {
    mesh: Mesh,
    model: Transform,
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
        .num_indices = @intCast(indices.len),
    };
}

// pub fn createMeshComponent(rd: *Renderer.RenderManager, vertices: []const Vertex, indices: []const u16) !MeshGPU {
//     const vertex_buffer = Renderer.createBuffer(rd.device, c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX, @intCast(@sizeOf(Vertex) * vertices.len)) orelse {
//         return error.VertexBufferCreationFailed;
//     };
//
//     const index_buffer = Renderer.createBuffer(rd.device, c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX, @intCast(@sizeOf(u16) * indices.len)) orelse {
//         return error.IndexBufferCreationFailed;
//     };
//
//     // Upload data
//     const command_buffer = c.sdl.SDL_AcquireGPUCommandBuffer(rd.device) orelse {
//         return error.CommandBufferAcquisitionFailed;
//     };
//
//     const copy_pass = c.sdl.SDL_BeginGPUCopyPass(command_buffer) orelse {
//         return error.CopyPassCreationFailed;
//     };
//
//     try Renderer.uploadToGPU(rd.device, copy_pass, rd.transfer_buffer, 0, Vertex, vertices, vertex_buffer);
//     try Renderer.uploadToGPU(rd.device, copy_pass, rd.transfer_buffer, @intCast(@sizeOf(Vertex) * vertices.len), u16, indices, index_buffer);
//
//     c.sdl.SDL_EndGPUCopyPass(copy_pass);
//     _ = c.sdl.SDL_SubmitGPUCommandBuffer(command_buffer);
//
//     return MeshGPU{
//         .vertex_buffer = vertex_buffer,
//         .index_buffer = index_buffer,
//         .num_indices = @intCast(indices.len),
//     };
// }
