const std = @import("std");
const uph = @import("../uph.zig");
const Objects = uph.uph3d.Objects;
const Assets = uph.uph3d.Assets;
const Transform = uph.uph3d.Transform;
const c = uph.clib;

// Debug mode - set to false for production
const DEBUG = false;

// Maximum vertex count - adjust based on your needs
const MAX_VERTEX = 3 * 1024 * 1024;
const MAX_INDEX = 6 * 1024 * 1024; // Allowing for more indices than vertices

pub const BatchError = error{
    NullRenderPass,
    EmptyBatch,
    BufferUploadFailed,
    InvalidIndexCount,
    RenderingFailed,
};

pub const Batch = struct {
    gpu: Objects.MeshGPU,
    meshes: std.ArrayList(*Objects.Mesh),

    vertices: std.ArrayList(Objects.Vertex),
    indices: std.ArrayList(Objects.Index),

    base_index: u16 = 0,
    atlas: ?Assets.TextureData,
    pipeline_handle: u32,
    camera: *uph.uph3d.Camera.Camera = undefined,
    transfer_buffer: *c.sdl.SDL_GPUTransferBuffer,
    draw_cmd_buf: u32,
    upload_cmd_buf: u32,
    ctx: uph.Context.Context,
    primitive_type: c.sdl.SDL_GPUPrimitiveType = c.sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,

    pub fn init(ctx: uph.Context.Context, pipeline_handle: u32, camera: *uph.uph3d.Camera.Camera) !*Batch {
        const allocator = ctx.allocator();
        const b = try allocator.create(Batch);

        if (DEBUG) std.debug.print("Creating batch with pipeline handle {d}\n", .{pipeline_handle});

        // Create vertex and index buffers with appropriate sizes
        const vbo = uph.Renderer.createBuffer(ctx.renderer().device, c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX, MAX_VERTEX * @sizeOf(Objects.Vertex)) orelse {
            return error.VBOCreationFailed;
        };
        const ibo = uph.Renderer.createBuffer(ctx.renderer().device, c.sdl.SDL_GPU_BUFFERUSAGE_INDEX, MAX_INDEX * @sizeOf(Objects.Index)) orelse {
            return error.IBOCreationFailed;
        };

        // Create a transfer buffer for uploading data to GPU
        const transfer_buffer = try ctx.renderer().createTransferBuffer(c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, @intCast(MAX_VERTEX * (@sizeOf(Objects.Vertex) + @sizeOf(Objects.Index))));

        b.* = Batch{
            .meshes = std.ArrayList(*Objects.Mesh).init(allocator),
            .ctx = ctx,
            .gpu = Objects.MeshGPU{
                .vbo = @constCast(vbo),
                .ibo = @constCast(ibo),
            },
            .vertices = std.ArrayList(Objects.Vertex).init(allocator),
            .indices = std.ArrayList(Objects.Index).init(allocator),

            .transfer_buffer = transfer_buffer,
            .pipeline_handle = pipeline_handle,
            .draw_cmd_buf = try ctx.renderer().newCommand(),
            .upload_cmd_buf = try ctx.renderer().newCommand(),
            .atlas = null,
            .camera = camera,
        };
        return b;
    }

    pub fn deinit(self: *Batch) void {
        if (DEBUG) std.debug.print("Cleaning up batch with {d} meshes\n", .{self.meshes.items.len});

        // Free all mesh memory
        for (self.meshes.items) |mesh_ptr| {
            self.ctx.allocator().free(mesh_ptr.vertices);
            self.ctx.allocator().free(mesh_ptr.indices);
            self.ctx.allocator().destroy(mesh_ptr);
        }
        self.meshes.deinit();
        self.vertices.deinit();
        self.indices.deinit();

        self.ctx.allocator().destroy(self);
    }
    pub fn draw(self: *Batch, delta_t: f32) !void {
        // Ensure we have something to draw
        if (self.meshes.items.len == 0) {
            if (DEBUG) std.debug.print("Warning: Attempted to draw empty batch\n", .{});
            return BatchError.EmptyBatch;
        }

        if (DEBUG) std.log.debug("Vertices: {any}\n", .{self.vertices.items});
        if (DEBUG) std.log.debug("Indices:  {any}\n", .{self.indices.items});

        // Get command buffer
        const upload_cmd = try self.ctx.renderer().getCommand(self.draw_cmd_buf);

        // Set target color
        try self.ctx.renderer().setTargetColor(upload_cmd);

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
            self.ctx.renderer().device,
            copy_pass.?,
            self.transfer_buffer,
            @intCast(self.vertices.items.len * @sizeOf(Objects.Vertex)),
            Objects.Vertex,
            self.vertices.items,
            self.gpu.vbo,
        );

        // Upload indices
        try uph.Renderer.uploadToGPU(
            self.ctx.renderer().device,
            copy_pass.?,
            self.transfer_buffer,
            @intCast(self.indices.items.len * @sizeOf(Objects.Index)),
            u16,
            self.indices.items,
            self.gpu.ibo,
        );

        // End copy pass
        c.sdl.SDL_EndGPUCopyPass(copy_pass);

        try self.ctx.renderer().submitCommand(self.upload_cmd_buf);

        const draw_cmd = try self.ctx.renderer().getCommand(self.draw_cmd_buf);

        if (DEBUG) std.debug.print("Total vertices: {d}, Total indices: {d}\n", .{ self.vertices.items.len, self.indices.items.len });

        // Begin render pass
        const render_pass = c.sdl.SDL_BeginGPURenderPass(draw_cmd.command_buffer, &self.ctx.renderer().target_info, 1, null);
        if (render_pass == null) return BatchError.NullRenderPass;

        // Bind graphics pipeline
        try self.ctx.renderer().bindGraphicsPipeline(render_pass, self.pipeline_handle);

        // Bind vertex and index buffers
        c.sdl.SDL_BindGPUVertexBuffers(render_pass, 0, &.{ .buffer = self.gpu.vbo, .offset = 0 }, 1);
        c.sdl.SDL_BindGPUIndexBuffer(render_pass, &.{ .buffer = self.gpu.ibo, .offset = 0 }, c.sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT);

        // Setup transform and uniform buffer data
        var trs = Transform.Transform.init();
        const ubo = Objects.UniformBufferObject{
            .model = trs.rotate(100, delta_t * 10, 0).model_matrix,
            .view = self.camera.view_matrix,
            .projection = self.camera.projection.getProjection(),
        };

        // Push uniform data
        c.sdl.SDL_PushGPUVertexUniformData(draw_cmd.command_buffer, 0, &ubo, @sizeOf(Objects.UniformBufferObject));

        // Ensure we have indices to draw
        if (self.indices.items.len == 0) return BatchError.InvalidIndexCount;

        // Draw the primitives
        c.sdl.SDL_DrawGPUIndexedPrimitives(
            render_pass,
            @intCast(self.indices.items.len), // Index count
            1,
            0, // Instance count (1 if no instancing)
            0, // First index
            0, // Vertex offset
        );
        // End render pass
        c.sdl.SDL_EndGPURenderPass(render_pass);
    }
    pub fn add(self: *Batch, mesh: Objects.Mesh) !void {
        const allocator = self.ctx.allocator();

        // Check if adding this mesh would exceed buffer limits
        if (self.base_index + mesh.vertices.len > MAX_VERTEX) {
            return error.VertexBufferFull;
        }

        // Create a new mesh instance
        const mesh_ptr = try allocator.create(Objects.Mesh);

        // Clone vertices
        const cloned_vertices = try allocator.alloc(Objects.Vertex, mesh.vertices.len);
        std.mem.copyForwards(Objects.Vertex, cloned_vertices, mesh.vertices);

        // Adjust indices to account for base_index and clone them
        var adjusted_indices = try allocator.alloc(u16, mesh.indices.len);
        for (mesh.indices, 0..) |idx, i| {
            adjusted_indices[i] = idx + self.base_index;
        }

        mesh_ptr.* = Objects.Mesh{
            .vertices = cloned_vertices,
            .indices = adjusted_indices,
            .num_indices = @intCast(adjusted_indices.len),
        };

        try self.meshes.append(mesh_ptr);

        try self.vertices.appendSlice(mesh_ptr.*.vertices);
        try self.indices.appendSlice(mesh_ptr.*.indices);
        self.base_index += @intCast(mesh.vertices.len);

        if (DEBUG) std.debug.print("Added mesh with {d} vertices and {d} indices. New base_index: {d}\n", .{ mesh.vertices.len, mesh.indices.len, self.base_index });
    }

    pub fn clear(self: *Batch) void {
        // Free all mesh memory
        for (self.meshes.items) |mesh_ptr| {
            self.ctx.allocator().free(mesh_ptr.vertices);
            self.ctx.allocator().free(mesh_ptr.indices);
            self.ctx.allocator().destroy(mesh_ptr);
        }
        self.meshes.clearRetainingCapacity();
        self.base_index = 0;

        if (DEBUG) std.debug.print("Cleared batch\n", .{});
    }
};
