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

pub const ObjectInstanceManager = struct {
    const ObjectSSBO = struct {
        model: Types.Mat4_f32,
        color: Types.Vec4_f32,
    };

    const ViewProj = struct {
        view: Types.Mat4_f32,
        projection: Types.Mat4_f32,
    };

    ctx: uph.Context.Context,

    mesh: Mesh,
    gpu_buffer: MeshGPU,
    object_SSBO_buffer: *c.sdl.SDL_GPUBuffer,

    max_object_number: u32,
    objects_count: u32 = 0,

    renderpass: *c.sdl.SDL_GPURenderPass = undefined,

    camera: *uph_3d.Camera.Camera,

    draw_cmd_handle: u32 = undefined,
    draw_cmd: *uph.Renderer.Cmd = undefined,

    pipeline: u32,

    // Buffer to batch object data uploads
    object_data_batch: std.ArrayList(ObjectSSBO),

    pub fn init(
        ctx: uph.Context.Context,
        mesh: Mesh,
        max_objects_number: u32,
        pipeline: u32,
        camera: *uph_3d.Camera.Camera,
    ) !*ObjectInstanceManager {
        const obj_man = try ctx.renderer().allocator.create(ObjectInstanceManager);

        obj_man.*.ctx = ctx;
        obj_man.*.mesh = mesh;
        obj_man.*.gpu_buffer = createMeshGPU(ctx.renderer().device, @intCast(mesh.vertices.len), @intCast(mesh.indices.len));

        // Create SSBO buffer for object data
        obj_man.*.object_SSBO_buffer = uph.Buffer.createBuffer(
            ctx.renderer().device,
            c.sdl.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
            @intCast(@sizeOf(ObjectSSBO) * max_objects_number),
        ).?;
        obj_man.*.max_object_number = max_objects_number;
        obj_man.*.objects_count = 0;
        obj_man.*.camera = camera;
        obj_man.*.pipeline = pipeline;
        obj_man.*.draw_cmd_handle = try ctx.renderer().createCommand();

        // Initialize batch array
        obj_man.*.object_data_batch = std.ArrayList(ObjectSSBO).init(ctx.renderer().allocator);
        try obj_man.*.object_data_batch.ensureTotalCapacity(max_objects_number);

        // Upload mesh data to GPU
        {
            const upload_cmd = try ctx.renderer().createRogueCommand();

            const copypass = c.sdl.SDL_BeginGPUCopyPass(upload_cmd.command_buffer) orelse {
                try ctx.renderer().submitRogueCommand(upload_cmd);
                return error.CopypassFailed;
            };

            const transferbuffer = try ctx.renderer().createTransferBuffer(
                c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                @intCast((mesh.vertices.len * @sizeOf(Vertex)) + (mesh.indices.len * @sizeOf(Index))),
            );
            defer c.sdl.SDL_ReleaseGPUTransferBuffer(ctx.renderer().device, transferbuffer);

            try uph.Buffer.uploadToGPU(
                ctx.renderer().device,
                copypass,
                transferbuffer,
                0,
                Vertex,
                mesh.vertices,
                obj_man.gpu_buffer.vbo,
            );
            try uph.Buffer.uploadToGPU(
                ctx.renderer().device,
                copypass,
                transferbuffer,
                @intCast(mesh.vertices.len * @sizeOf(Vertex)),
                Index,
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
        releaseMeshGPU(self.ctx.renderer().device, &self.gpu_buffer);
        c.sdl.SDL_ReleaseGPUBuffer(self.ctx.renderer().device, self.object_SSBO_buffer);

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
        // Check if we've reached the maximum number of objects
        if (self.objects_count >= self.max_object_number) {
            return error.MaxObjectsExceeded;
        }

        // Add object data to batch
        try self.object_data_batch.append(.{
            .model = transform,
            .color = color,
        });

        self.objects_count += 1;
    }

    pub fn endDraw(self: *ObjectInstanceManager) !void {
        if (self.objects_count == 0) return;

        // Upload batched object data to SSBO
        {
            const upload_cmd = try self.ctx.renderer().createRogueCommand();

            const copypass = c.sdl.SDL_BeginGPUCopyPass(upload_cmd.command_buffer) orelse {
                return error.CopypassFailed;
            };

            const transferbuffer = try self.ctx.renderer().createTransferBuffer(
                c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                @intCast(@sizeOf(ObjectSSBO) * self.objects_count),
            );
            defer c.sdl.SDL_ReleaseGPUTransferBuffer(self.ctx.renderer().device, transferbuffer);

            try uph.Buffer.uploadToGPU(
                self.ctx.renderer().device,
                copypass,
                transferbuffer,
                0,
                ObjectSSBO,
                self.object_data_batch.items,
                self.object_SSBO_buffer,
            );
            c.sdl.SDL_EndGPUCopyPass(copypass);

            try self.ctx.renderer().submitRogueCommand(upload_cmd);
        }

        // Upload ViewProj data to uniform buffer
        {
            const upload_cmd = try self.ctx.renderer().createRogueCommand();

            const copypass = c.sdl.SDL_BeginGPUCopyPass(upload_cmd.command_buffer) orelse {
                return error.CopypassFailed;
            };

            const transferbuffer = try self.ctx.renderer().createTransferBuffer(
                c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                @intCast(@sizeOf(ViewProj)),
            );
            defer c.sdl.SDL_ReleaseGPUTransferBuffer(self.ctx.renderer().device, transferbuffer);

            c.sdl.SDL_EndGPUCopyPass(copypass);

            try self.ctx.renderer().submitRogueCommand(upload_cmd);
        }

        self.draw_cmd = try self.ctx.renderer().getCommand(self.draw_cmd_handle);
        // Create render pass
        {
            self.renderpass = c.sdl.SDL_BeginGPURenderPass(self.draw_cmd.command_buffer, &self.ctx.renderer().target_info, 1, null) orelse {
                return error.RenderpassFailed;
            };
        }

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
        // c.sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, &ubo, @sizeOf(components.render.UniformBufferObject));
        const view_projection = ViewProj{
            .view = self.camera.view_matrix,
            .projection = self.camera.projection.getProjection(),
        };
        c.sdl.SDL_PushGPUVertexUniformData(self.draw_cmd.command_buffer, 0, &view_projection, @intCast(@sizeOf(ViewProj)));

        // Bind SSBO storage buffer (set 1, binding 0)
        c.sdl.SDL_BindGPUVertexStorageBuffers(self.renderpass, 0, &[_]*c.sdl.SDL_GPUBuffer{self.object_SSBO_buffer}, 1);

        // Draw instanced
        c.sdl.SDL_DrawGPUIndexedPrimitives(self.renderpass, @intCast(self.mesh.indices.len), self.objects_count, 0, 0, 0);

        // End render pass
        c.sdl.SDL_EndGPURenderPass(self.renderpass);

        try self.ctx.renderer().submitCommand(self.draw_cmd_handle);
    }
};

// Create a simple renderer (no batch-no instance)

pub const ObjectManager = struct {
    const ViewProj = struct {
        view: Types.Mat4_f32,
        projection: Types.Mat4_f32,
    };

    ctx: uph.Context.Context,

    renderpass: *c.sdl.SDL_GPURenderPass = undefined,

    camera: *uph_3d.Camera.Camera,

    gpu_buffer: MeshGPU,
    obj_vert_list: std.ArrayList(Vertex),
    obj_idx_list: std.ArrayList(Index),

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
        obj_man.*.obj_vert_list = std.ArrayList(Vertex).init(ctx.allocator());
        obj_man.*.obj_idx_list = std.ArrayList(Index).init(ctx.allocator());
        obj_man.*.gpu_buffer = createMeshGPU(ctx.renderer().device, @intCast(max_vertices), @intCast(max_indices));
        obj_man.*.ctx = ctx;

        return obj_man;
    }

    pub fn deinit(self: *ObjectManager) void {
        self.obj_vert_list.deinit();
        self.obj_idx_list.deinit();
        releaseMeshGPU(self.ctx.renderer().device, &self.gpu_buffer);
        self.ctx.allocator().destroy(self);
    }

    pub fn beginDraw(self: *ObjectManager) !void {
        _ = &self; // autofix
        // Acquire swapchain texture
        try self.ctx.renderer().acquireSwapchainTexture(self.draw_cmd_handle);
    }

    pub fn draw(
        self: *ObjectManager,
        mesh: Mesh,
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
                @intCast((self.obj_vert_list.items.len * @sizeOf(Vertex)) + (self.obj_idx_list.items.len * @sizeOf(Index))),
            );
            defer c.sdl.SDL_ReleaseGPUTransferBuffer(self.ctx.renderer().device, transferbuffer);

            try uph.Buffer.uploadToGPU(
                self.ctx.renderer().device,
                copypass,
                transferbuffer,
                0,
                Vertex,
                self.obj_vert_list.items,
                self.gpu_buffer.vbo,
            );
            try uph.Buffer.uploadToGPU(
                self.ctx.renderer().device,
                copypass,
                transferbuffer,
                @intCast(self.obj_vert_list.items.len * @sizeOf(Vertex)),
                Index,
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
