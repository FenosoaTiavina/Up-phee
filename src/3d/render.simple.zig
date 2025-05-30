const std = @import("std");

const uph = @import("../uph.zig");
const c = uph.clib;
const Renderer = uph.Renderer;
const Types = uph.Types;
const uph_3d = uph.uph_3d;

// Create a simple renderer (no batch-no instance)

pub const ObjectManager = struct {
    const ViewProj = struct {
        view: Types.Mat4_f32,
        projection: Types.Mat4_f32,
    };

    ctx: uph.Context.Context,

    renderpass: *c.sdl.SDL_GPURenderPass = undefined,

    camera: *uph_3d.Camera.Camera,

    gpu_buffer: uph_3d.Objects.MeshGPU,
    obj_vert_list: std.ArrayList(uph_3d.Objects.Vertex),
    obj_idx_list: std.ArrayList(uph_3d.Objects.Index),

    draw_cmd_handle: u32 = undefined,
    draw_cmd: *uph.Renderer.Cmd = undefined,

    pipeline: u32,
    objects_count: u32 = 0,

    pub fn init(
        ctx: uph.Context.Context,
        pipeline: u32,
        camera: *uph_3d.Camera.Camera,
        max_vertices: u32,
        max_indices: u32,
    ) !*ObjectManager {
        const obj_man = try ctx.renderer().allocator.create(ObjectManager);
        obj_man.*.draw_cmd_handle = try ctx.renderer().createCommand();
        obj_man.*.camera = camera;
        obj_man.*.pipeline = pipeline;
        obj_man.*.obj_vert_list = std.ArrayList(uph_3d.Objects.Vertex).init(ctx.allocator());
        obj_man.*.obj_idx_list = std.ArrayList(uph_3d.Objects.Index).init(ctx.allocator());
        obj_man.*.gpu_buffer = uph_3d.Objects.createMeshGPU(ctx.renderer().device, @intCast(max_vertices), @intCast(max_indices));
        obj_man.*.ctx = ctx;

        return obj_man;
    }

    pub fn deinit(self: *ObjectManager) void {
        self.obj_vert_list.deinit();
        self.obj_idx_list.deinit();
        uph_3d.Objects.releaseMeshGPU(self.ctx.renderer().device, &self.gpu_buffer);
        self.ctx.allocator().destroy(self);
    }

    pub fn beginDraw(self: *ObjectManager) !void {
        _ = &self; // autofix
        // Acquire swapchain texture
        try self.ctx.renderer().acquireSwapchainTexture(self.draw_cmd_handle);
    }

    pub fn draw(
        self: *ObjectManager,
        mesh: uph_3d.Objects.Mesh,
    ) !void {
        try self.obj_vert_list.appendSlice(mesh.vertices);
        try self.obj_idx_list.appendSlice(mesh.indices);

        self.objects_count += 1;
    }

    pub fn endDraw(self: *ObjectManager) !void {
        { // upload to gpu buffer
            const upload_cmd = try self.ctx.renderer().createRogueCommand();

            const copypass = c.sdl.SDL_BeginGPUCopyPass(upload_cmd.command_buffer) orelse {
                try self.ctx.renderer().submitRogueCommand(upload_cmd);
                return error.CopypassFailed;
            };

            const transferbuffer = try self.ctx.renderer().createTransferBuffer(
                c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                @intCast((self.obj_vert_list.items.len * @sizeOf(uph_3d.Objects.Vertex)) + (self.obj_idx_list.items.len * @sizeOf(uph_3d.Objects.Index))),
            );
            defer c.sdl.SDL_ReleaseGPUTransferBuffer(self.ctx.renderer().device, transferbuffer);

            try uph.Buffer.uploadToGPU(
                self.ctx.renderer().device,
                copypass,
                transferbuffer,
                0,
                uph_3d.Objects.Vertex,
                self.obj_vert_list.items,
                self.gpu_buffer.vbo,
            );
            try uph.Buffer.uploadToGPU(
                self.ctx.renderer().device,
                copypass,
                transferbuffer,
                @intCast(self.obj_vert_list.items.len * @sizeOf(uph_3d.Objects.Vertex)),
                uph_3d.Objects.Index,
                self.obj_idx_list.items,
                self.gpu_buffer.ibo,
            );
            c.sdl.SDL_EndGPUCopyPass(copypass);

            try self.ctx.renderer().submitRogueCommand(upload_cmd);
        }

        self.draw_cmd = try self.ctx.renderer().getCommand(self.draw_cmd_handle);

        self.renderpass = c.sdl.SDL_BeginGPURenderPass(self.draw_cmd.command_buffer, &self.ctx.renderer().target_info, 1, null) orelse {
            return error.RenderpassFailed;
        };

        // Bind pipeline
        {
            try self.ctx.renderer().bindGraphicsPipeline(self.renderpass, self.pipeline);
        }

        // Bind vertex and index buffers
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

        // Bind ViewProj uniform buffer (set 0, binding 0)
        const view_projection = ViewProj{
            .view = self.camera.view_matrix,
            .projection = self.camera.projection.getProjection(),
        };
        c.sdl.SDL_PushGPUVertexUniformData(self.draw_cmd.command_buffer, 0, &view_projection, @intCast(@sizeOf(ViewProj)));

        // // Bind SSBO storage buffer (set 1, binding 0)
        // c.sdl.SDL_BindGPUVertexStorageBuffers(self.renderpass, 0, &[_]*c.sdl.SDL_GPUBuffer{self.object_SSBO_buffer}, 1);

        // Draw Indexed
        c.sdl.SDL_DrawGPUIndexedPrimitives(self.renderpass, @intCast(self.obj_idx_list.items.len), 1, 0, 0, 0);

        // End render pass
        c.sdl.SDL_EndGPURenderPass(self.renderpass);

        try self.ctx.renderer().submitCommand(self.draw_cmd_handle);
        self.obj_vert_list.clearAndFree();
        self.obj_idx_list.clearAndFree();
    }
};
