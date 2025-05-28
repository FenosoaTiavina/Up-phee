const std = @import("std");

const uph = @import("../uph.zig");
const c = uph.clib;
const Renderer = uph.Renderer;
const Types = uph.Types;
const uph_3d = uph.uph_3d;

// Instanced
pub const ObjectInstanceManager = struct {
    // const ObjectSSBO = struct {
    //     model: Types.Mat4_f32,
    //     color: Types.Vec4_f32,
    // };

    const ViewProj = struct {
        view: Types.Mat4_f32,
        projection: Types.Mat4_f32,
    };

    ctx: uph.Context.Context,

    mesh: uph_3d.Objects.Mesh,
    gpu_buffer: uph_3d.Objects.MeshGPU,
    object_SSBO_buffer: *c.sdl.SDL_GPUBuffer,

    max_object_number: u32,
    objects_count: u32 = 0,

    renderpass: *c.sdl.SDL_GPURenderPass = undefined,

    camera: *uph_3d.Camera.Camera,

    draw_cmd_handle: u32 = undefined,
    draw_cmd: *uph.Renderer.Cmd = undefined,

    pipeline: u32,

    // Buffer to batch object data uploads
    // object_data_batch: std.ArrayList(ObjectSSBO),
    object_data_batch: std.ArrayList(Types.Vec4_f32),

    pub fn init(
        ctx: uph.Context.Context,
        mesh: uph_3d.Objects.Mesh,
        max_objects_number: u32,
        pipeline: u32,
        camera: *uph_3d.Camera.Camera,
    ) !*ObjectInstanceManager {
        const obj_man = try ctx.renderer().allocator.create(ObjectInstanceManager);

        obj_man.*.ctx = ctx;
        obj_man.*.mesh = mesh;
        obj_man.*.gpu_buffer = uph_3d.Objects.createMeshGPU(ctx.renderer().device, @intCast(mesh.vertices.len), @intCast(mesh.indices.len));

        // Create SSBO buffer for object data
        obj_man.*.object_SSBO_buffer = uph.Buffer.createBuffer(
            ctx.renderer().device,
            c.sdl.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
            @intCast(@sizeOf(Types.Vec4_f32) * max_objects_number),
        ).?;

        obj_man.*.max_object_number = max_objects_number;
        obj_man.*.objects_count = 0;
        obj_man.*.camera = camera;
        obj_man.*.pipeline = pipeline;
        obj_man.*.draw_cmd_handle = try ctx.renderer().createCommand();

        // Initialize batch array
        obj_man.*.object_data_batch = std.ArrayList(Types.Vec4_f32).init(ctx.renderer().allocator);

        { // Upload mesh data to GPU
            const upload_cmd = try ctx.renderer().createRogueCommand();

            const copypass = c.sdl.SDL_BeginGPUCopyPass(upload_cmd.command_buffer) orelse {
                try ctx.renderer().submitRogueCommand(upload_cmd);
                return error.CopypassFailed;
            };

            const transferbuffer = try ctx.renderer().createTransferBuffer(
                c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                @intCast((mesh.vertices.len * @sizeOf(uph_3d.Objects.Vertex)) + (mesh.indices.len * @sizeOf(uph_3d.Objects.Index))),
            );
            defer c.sdl.SDL_ReleaseGPUTransferBuffer(ctx.renderer().device, transferbuffer);

            try uph.Buffer.uploadToGPU(
                ctx.renderer().device,
                copypass,
                transferbuffer,
                0,
                uph_3d.Objects.Vertex,
                mesh.vertices,
                obj_man.gpu_buffer.vbo,
            );
            try uph.Buffer.uploadToGPU(
                ctx.renderer().device,
                copypass,
                transferbuffer,
                @intCast(mesh.vertices.len * @sizeOf(uph_3d.Objects.Vertex)),
                uph_3d.Objects.Index,
                mesh.indices,
                obj_man.gpu_buffer.ibo,
            );
            c.sdl.SDL_EndGPUCopyPass(copypass);

            try ctx.renderer().submitRogueCommand(upload_cmd);
        }

        return obj_man;
    }

    pub fn deinit(self: *ObjectInstanceManager) void {
        // Release all buffers
        uph_3d.Objects.releaseMeshGPU(self.ctx.renderer().device, &self.gpu_buffer);
        // c.sdl.SDL_ReleaseGPUBuffer(self.ctx.renderer().device, self.object_SSBO_buffer);

        self.object_data_batch.deinit();
        self.ctx.allocator().destroy(self);
    }

    pub fn beginDraw(self: *ObjectInstanceManager) !void {
        // Clear the batch for new frame
        self.object_data_batch.clearRetainingCapacity();
        self.objects_count = 0;

        // Acquire swapchain texture
        try self.ctx.renderer().acquireSwapchainTexture(self.draw_cmd_handle);
    }

    pub fn draw(
        self: *ObjectInstanceManager,
        transform: Types.Mat4_f32,
        color: Types.Vec4_f32,
    ) !void {
        _ = transform; // autofix
        if (self.objects_count > self.max_object_number) {
            return error.MaxObjectsExceeded;
        }

        // Add object data to batch
        try self.object_data_batch.append(color);

        self.objects_count += 1;
    }

    pub fn endDraw(self: *ObjectInstanceManager) !void {
        if (self.objects_count == 0) return;

        const upload_cmd = try self.ctx.renderer().createRogueCommand();
        { // Upload batched object data to SSBO

            const copypass = c.sdl.SDL_BeginGPUCopyPass(upload_cmd.command_buffer) orelse {
                return error.CopypassFailed;
            };

            const transferbuffer = try self.ctx.renderer().createTransferBuffer(
                c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                @intCast(@sizeOf(Types.Vec4_f32) * self.objects_count),
            );
            defer c.sdl.SDL_ReleaseGPUTransferBuffer(self.ctx.renderer().device, transferbuffer);

            try uph.Buffer.uploadToGPU(
                self.ctx.renderer().device,
                copypass,
                transferbuffer,
                0,
                Types.Vec4_f32,
                self.object_data_batch.items,
                self.object_SSBO_buffer,
            );
            c.sdl.SDL_EndGPUCopyPass(copypass);
        }

        {
            // Upload ViewProj data to uniform buffer
            const copypass = c.sdl.SDL_BeginGPUCopyPass(upload_cmd.command_buffer) orelse {
                return error.CopypassFailed;
            };

            const transferbuffer = try self.ctx.renderer().createTransferBuffer(
                c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                @intCast(@sizeOf(ViewProj)),
            );
            defer c.sdl.SDL_ReleaseGPUTransferBuffer(self.ctx.renderer().device, transferbuffer);

            c.sdl.SDL_EndGPUCopyPass(copypass);
        }

        try self.ctx.renderer().submitRogueCommand(upload_cmd);

        self.draw_cmd = try self.ctx.renderer().getCommand(self.draw_cmd_handle);

        { // Create render pass
            self.renderpass = c.sdl.SDL_BeginGPURenderPass(self.draw_cmd.command_buffer, &self.ctx.renderer().target_info, 1, null) orelse {
                return error.RenderpassFailed;
            };
        }

        try self.ctx.renderer().bindGraphicsPipeline(self.renderpass, self.pipeline);

        { // Bind SSBO storage buffer (set 0, binding 0)
            const shared_buffers = [_]*c.sdl.SDL_GPUBuffer{self.object_SSBO_buffer};
            c.sdl.SDL_BindGPUVertexStorageBuffers(self.renderpass, 1, &shared_buffers, 1);
        }

        { // Bind vertex and index buffers
            c.sdl.SDL_BindGPUVertexBuffers(
                self.renderpass,
                0,
                &c.sdl.struct_SDL_GPUBufferBinding{ .buffer = self.gpu_buffer.vbo, .offset = 0 },
                1,
            );
            c.sdl.SDL_BindGPUIndexBuffer(
                self.renderpass,
                &c.sdl.struct_SDL_GPUBufferBinding{ .buffer = self.gpu_buffer.ibo, .offset = 0 },
                c.sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT,
            );
        }

        { // Bind ViewProj uniform buffer (set 0, binding 0)
            const view_projection = ViewProj{
                .view = self.camera.view_matrix,
                .projection = self.camera.projection.getProjection(),
            };
            c.sdl.SDL_PushGPUVertexUniformData(self.draw_cmd.command_buffer, 0, &view_projection, @intCast(@sizeOf(ViewProj)));
        }

        // Draw instanced
        c.sdl.SDL_DrawGPUIndexedPrimitives(self.renderpass, @intCast(self.mesh.indices.len), self.objects_count, 0, 0, 0);

        // End render pass
        c.sdl.SDL_EndGPURenderPass(self.renderpass);

        try self.ctx.renderer().submitCommand(self.draw_cmd_handle);

        self.object_data_batch.clearRetainingCapacity();
        self.objects_count = 0;
    }
};
