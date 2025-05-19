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

pub const GPUObjet = struct {
    gpu_vertex_buffer: *c.sdl.SDL_GPUBuffer,
    vertex_buffer_offset: u32,
    gpu_index_buffer: *c.sdl.SDL_GPUBuffer,
    index_buffer_offset: u32,
};

pub fn createGPUObject(
    renderer: *uph.Renderer.RenderManager,
    size: struct {
        indices: u32,
        vertices: u32,
    },
) !*GPUObjet {
    var gpu_buf = try renderer.allocator.create(GPUObjet);

    gpu_buf = &.{
        .gpu_vertex_buffer = uph.Renderer.createBuffer(renderer.device, c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX, size) orelse {
            return error.VertexBufferCreation;
        },
        .gpu_index_buffer = uph.Renderer.createBuffer(renderer.device, c.sdl.SDL_GPU_BUFFERUSAGE_INDEX, size) orelse {
            return error.IndexBufferCreation;
        },
        .vertex_buffer_offset = 0,
        .index_buffer_offset = 0,
    };

    return gpu_buf;
}

pub fn destroyGPUObject(
    self: *GPUObjet,
    renderer: *uph.Renderer.RenderManager,
) void {
    c.sdl.SDL_ReleaseGPUBuffer(renderer.device, self.gpu_vertex_buffer);
    c.sdl.SDL_ReleaseGPUBuffer(renderer.device, self.gpu_index_buffer);
    renderer.allocator.free(self);
}

pub fn appendMeshToGPU_Object(
    renderer: *uph.Renderer.RenderManager,
    self: *GPUObjet,
    transfer_buffer: *c.sdl.SDL_GPUTransferBuffer,
    meshes: Mesh,
) !void {
    if (meshes.items.len == 0) {
        return error.EmptyMesh;
    }

    // Get command buffer
    const upload_cmd = try renderer.createRogueCommand();

    // Begin copy pass for uploading data to GPU
    const copy_pass = c.sdl.SDL_BeginGPUCopyPass(upload_cmd.command_buffer);
    if (copy_pass == null) return error.CopyPassFailed;

    // var vertex_offset: u32 = 0;
    // var index_offset: u32 = 0;
    // var total_indices: u32 = 0;
    // var total_vertices: u32 = 0;

    // Upload all mesh data to GPU
    // for (self.meshes.items) |msh| {
    //     if (DEBUG) std.debug.print("Uploading mesh: {d} vertices, {d} indices\n", .{ msh.vertices.len, msh.indices.len });
    //
    // Upload vertices
    try uph.Renderer.uploadToGPU(
        renderer.device,
        copy_pass.?,
        transfer_buffer,
        self.index_buffer_offset,
        Vertex,
        meshes.vertices,
        self.gpu_vertex_buffer,
    );

    // Upload indices
    try uph.Renderer.uploadToGPU(
        renderer.device,
        copy_pass.?,
        self.transfer_buffer,
        self.index_buffer_offset,
        Index,
        meshes.indices,
        self.gpu_index_buffer,
    );

    self.vertex_buffer_offset += @intCast(meshes.vertices.len * @sizeOf(Vertex));
    self.vertex_buffer_offset += @intCast(meshes.vertices.len * @sizeOf(Vertex));

    // End copy pass
    c.sdl.SDL_EndGPUCopyPass(copy_pass);

    try renderer.submitRogueCommand(upload_cmd);
}

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
