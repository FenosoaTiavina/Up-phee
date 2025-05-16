// create a batch:
//  VertexB
//  IndexB
//  index nums
//  pipeline handle

// Draw,
// Add to batch
// Batch pool

const std = @import("std");

const uph = @import("../uph.zig");

const c = @import("../imports.zig");
const Assets = @import("assets.zig");
const Objects = @import("objects.zig");
const Transform = @import("transform.zig");

const MAX_VERTEX = 3 * 1024 * 1024;
pub const Batch = struct {
    gpu: Objects.MeshGPU,
    meshes: std.ArrayList(*Objects.Mesh),
    base_index: u16 = 0,
    atlas: ?Assets.TextureData,
    pipeline_handle: u32,
    camera: *uph.uph3d.Camera.Camera = undefined,
    transfer_buffer: *c.sdl.SDL_GPUTransferBuffer,
    command_buffer: u32,
    ctx: uph.Context.Context,

    pub fn create(ctx_val: uph.Context.Context, pipeline_handle: u32, camera: *uph.uph3d.Camera.Camera) !*Batch {
        const b = try ctx_val.allocator().create(Batch);

        const vbo = uph.Renderer.createBuffer(ctx_val.renderer().device, c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX, MAX_VERTEX * @sizeOf(Objects.Vertex)).?;
        const ibo = uph.Renderer.createBuffer(ctx_val.renderer().device, c.sdl.SDL_GPU_BUFFERUSAGE_INDEX, MAX_VERTEX * @sizeOf(Objects.Index)).?;

        const transfer_buffer = try ctx_val.renderer().createTransferBuffer(
            c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            @intCast(MAX_VERTEX * (@sizeOf(Objects.Mesh))),
        );

        const meshes_array = std.ArrayList(*Objects.Mesh).init(ctx_val.allocator());
        b.* = Batch{
            .meshes = meshes_array,
            .ctx = ctx_val,
            .gpu = Objects.MeshGPU{
                .vbo = @constCast(vbo),
                .ibo = @constCast(ibo),
            },
            .transfer_buffer = transfer_buffer,
            .pipeline_handle = pipeline_handle,
            .command_buffer = try ctx_val.renderer().newCommandBuffer(),
            .atlas = null,
            .camera = camera,
        };
        return b;
    }

    pub fn deinit(self: *Batch) void {
        for (self.meshes.items) |mesh_ptr| {
            self.*.ctx.allocator().destroy(mesh_ptr);
        }
        self.meshes.deinit();
        self.ctx.allocator().destroy(self);
    }

    pub fn add(self: *Batch, mesh: Objects.Mesh) !void {
        const allocator = self.ctx.allocator();
        const mesh_ptr = try allocator.create(Objects.Mesh);

        var adjusted_indices = try std.ArrayList(u16).initCapacity(allocator, mesh.indices.len);
        for (mesh.indices) |idx| {
            try adjusted_indices.append(idx + self.base_index);
        }

        mesh_ptr.* = Objects.Mesh{
            .vertices = mesh.vertices,
            .indices = adjusted_indices.toOwnedSlice(),
            .num_indices = @intCast(adjusted_indices.items.len),
        };

        try self.meshes.append(mesh_ptr);
        self.base_index += @intCast(mesh.vertices.len);
    }

    pub fn draw(self: *Batch) !void {
        std.debug.print("base_index: {}\n", .{self.base_index});
        // acquire a command buffer
        const command_buffer = try self.ctx.renderer().getCommandBuffer(self.command_buffer);
        try self.ctx.renderer().setTargetColor(command_buffer);

        // Upload data
        const copy_pass = c.sdl.SDL_BeginGPUCopyPass(command_buffer) orelse {
            return error.CopyPassCreationFailed;
        };

        var vertex_offset: u32 = 0;
        var index_offset: u32 = 0;
        self.base_index = 0;
        var total_indices: u32 = 0;

        for (self.meshes.items) |msh| {
            try uph.Renderer.uploadToGPU(
                self.ctx.renderer().device,
                copy_pass,
                self.transfer_buffer,
                vertex_offset,
                Objects.Vertex,
                msh.vertices,
                self.gpu.vbo,
            );

            try uph.Renderer.uploadToGPU(
                self.ctx.renderer().device,
                copy_pass,
                self.transfer_buffer,
                index_offset,
                u16,
                msh.indices,
                self.gpu.ibo,
            );

            vertex_offset += @intCast(msh.vertices.len * @sizeOf(Objects.Vertex));
            index_offset += @intCast(msh.indices.len * @sizeOf(Objects.Index));
            total_indices += msh.num_indices;
        }
        c.sdl.SDL_EndGPUCopyPass(copy_pass);
        const render_pass = c.sdl.SDL_BeginGPURenderPass(command_buffer, &self.ctx.renderer().target_info, 1, null);
        if (render_pass == null) return error.InvalidRenderPass;

        try self.ctx.renderer().bindGraphicsPipeline(render_pass, self.pipeline_handle);

        // Bind the shared vertex/index buffers
        c.sdl.SDL_BindGPUVertexBuffers(render_pass, 0, &.{ .buffer = self.gpu.vbo, .offset = 0 }, 1);
        c.sdl.SDL_BindGPUIndexBuffer(render_pass, &.{ .buffer = self.gpu.ibo, .offset = 0 }, c.sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT);

        var trs = Transform.Transform.init();
        const ubo = Objects.UniformBufferObject{
            .model = trs.rotate(9, 9, 9).model_matrix,
            .view = self.camera.view_matrix,
            .projection = self.camera.projection_matrix,
        };

        c.sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, &ubo, @sizeOf(Objects.UniformBufferObject));

        c.sdl.SDL_DrawGPUIndexedPrimitives(render_pass, self.base_index, total_indices, 0, 0, 0);

        c.sdl.SDL_EndGPURenderPass(render_pass);
    }
};
