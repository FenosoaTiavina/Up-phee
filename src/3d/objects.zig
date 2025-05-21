// src/uph/uph3d/objects.zig
const std = @import("std");

const uph = @import("../uph.zig");
const c = uph.clib;
const sdl = c.sdl;
const Types = uph.Types;

// Assuming uph.zig exposes Renderer and other top-level modules
// For SDL_gpu types and functions
// Alias for c.sdl
// For Vec3_f32, Mat4_f32 etc.

// Vertex structure as defined in objects.txt [cite: 9]
pub const Vertex = struct {
    position: Types.Vec3_f32,
    // uv: Types.Vec2_f32, // Uncomment if you add UVs to your vertex data
    // color: Types.Vec4_f32, // Example: Add color if needed
};

// Index type as defined in objects.txt [cite: 10]
pub const Index = u16;

// CPU-side Mesh structure as defined in objects.txt [cite: 10]
pub const Mesh = struct {
    vertices: []const Vertex,
    indices: []const Index,
};

pub const GPUObject = struct {
    vbo: *c.sdl.struct_SDL_GPUBuffer,
    ibo: *c.sdl.struct_SDL_GPUBuffer,
    max_objects: u32,
    index_per_object: u32,
    vertices_per_object: u32,
    object_count: u32,
    pipeline_handle: u32,

    pub fn init(ctx: uph.Context.Context, max_objects: u32, vertices_per_object: u32, indices_per_object: u32, pipeline: u32) !*GPUObject {
        const gpu_obj = try ctx.allocator().create(GPUObject);
        gpu_obj.* = GPUObject{
            .vbo = uph.Renderer.createBuffer(
                ctx.renderer().device,
                c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
                max_objects * @sizeOf(Vertex),
            ) orelse
                return error.FailedVBOCreation,
            .ibo = uph.Renderer.createBuffer(
                ctx.renderer().device,
                c.sdl.SDL_GPU_BUFFERUSAGE_INDEX,
                max_objects * indices_per_object * @sizeOf(Index),
            ) orelse
                return error.FailedIBOCreation,
            .object_count = 0,
            .max_objects = max_objects,
            .index_per_object = indices_per_object,
            .vertices_per_object = vertices_per_object,
            .pipeline_handle = pipeline,
        };
        return gpu_obj;
    }

    pub fn deinit(self: *GPUObject, ctx: uph.Context.Context) void {
        c.sdl.SDL_ReleaseGPUBuffer(ctx.renderer().device, self.vbo);
        c.sdl.SDL_ReleaseGPUBuffer(ctx.renderer().device, self.ibo);

        ctx.allocator().destroy(self);
    }

    pub fn addMesh(self: *GPUObject, ctx: uph.Context.Context, mesh: Mesh) !void {
        if (self.object_count == self.max_objects) {
            return error.GPUObjectFull;
        }

        if (mesh.vertices.len != self.vertices_per_object or mesh.indices.len != self.index_per_object) {
            return error.MeshNotMatching;
        }

        const mesh_transfer_buffer = ctx.renderer().createTransferBuffer(
            c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            @as(u32, @intCast(@sizeOf(Vertex) * mesh.vertices.len)) + @as(u32, @intCast(@sizeOf(Index) * mesh.indices.len)),
        ) orelse {
            return error.TextureTransferBufferCreationFailed;
        };
        defer ctx.renderer().releaseTransferBuffer(mesh_transfer_buffer);

        const cmd = try ctx.renderer().createRogueCommand();

        const copy_pass = c.sdl.SDL_BeginGPUCopyPass(cmd.command_buffer) orelse {
            return error.CopyPassCreationFailed;
        };

        const vertex_byte_offset = self.object_count * @sizeOf(Vertex) * self.vertices_per_object;
        try ctx.renderer().uploadToGPU(copy_pass, mesh_transfer_buffer, vertex_byte_offset, Vertex, mesh.vertices, self.vbo);

        // For the IBO (index buffer)
        const index_byte_offset = self.object_count * @sizeOf(u16) * self.index_per_object;
        try ctx.renderer().uploadToGPU(copy_pass, mesh_transfer_buffer, index_byte_offset, u16, mesh.indices, self.ibo);

        c.sdl.SDL_EndGPUCopyPass(copy_pass);

        self.object_count += 1;
    }

    pub fn draw(self: *GPUObject, ctx: uph.Context.Context) !void {
        if (self.object_count == 0) return;

        const draw_cmd_id = try ctx.renderer().newCommand();
        const draw_cmd = try ctx.renderer().getCommandBuffer(draw_cmd_id);

        // Begin render pass
        const render_pass = c.sdl.SDL_BeginGPURenderPass(draw_cmd.command_buffer, &ctx.renderer().target_info, 1, null);
        if (render_pass == null) return error.NullRenderPass;

        // Bind graphics pipeline
        try ctx.renderer().bindPipeline(render_pass, self.pipeline_handle);

        // Bind vertex and index buffers
        c.sdl.SDL_BindGPUVertexBuffers(render_pass, 0, &.{ .buffer = self.vbo, .offset = 0 }, 1);
        c.sdl.SDL_BindGPUIndexBuffer(render_pass, &.{ .buffer = self.ibo, .offset = 0 }, c.sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT);

        // Setup transform and uniform buffer data
        // var trs = Transform.Transform.init();
        // const ubo = Objects.UniformBufferObject{
        //     .model = trs.rotate(100, delta_t * 10, 0).model_matrix,
        //     .view = self.camera.view_matrix,
        //     .projection = self.camera.projection_matrix,
        // };

        // // Push uniform data
        // c.sdl.SDL_PushGPUVertexUniformData(draw_cmd.command_buffer, 0, &ubo, @sizeOf(Objects.UniformBufferObject));

        // Ensure we have indices to draw

        // Draw the primitives
        c.sdl.SDL_DrawGPUIndexedPrimitives(
            render_pass,
            self.index_per_object * self.object_count, // Index count
            1,
            0, // Instance count (1 if no instancing)
            0, // First index
            0, // Vertex offset
        );
        // End render pass
        c.sdl.SDL_EndGPURenderPass(render_pass);
    }
};

pub fn createMesh(vertices: []const Vertex, indices: []const Index) Mesh {
    return Mesh{
        .vertices = vertices,
        .indices = indices,
    };
}

pub const GlobalUniformData = struct {
    view_proj_matrix: Types.Mat4_f32,
    // Add other global shader data here, e.g.:
    // camera_position: Types.Vec3_f32,
    // light_direction: Types.Vec3_f32,
};
