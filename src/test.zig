// renderer.zig
const std = @import("std");
const sdl = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_gpu.h");
    @cInclude("SDL3/SDL_pixels.h");
    @cInclude("SDL3/SDL_video.h");
    @cInclude("SDL3/SDL_vulkan.h");
});
const stb = @cImport({
    @cInclude("stb/stb_image.h");
});
const zm = @import("zmath");
const zgui = @import("zgui");
const ecs = @import("ecs.zig");
const components = @import("components.zig");

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    window: ?*sdl.SDL_Window,
    device: ?*sdl.SDL_GPUDevice,
    pipeline: ?*sdl.SDL_GPUGraphicsPipeline,
    shader_vert: ?*sdl.SDL_GPUShader,
    shader_frag: ?*sdl.SDL_GPUShader,
    default_sampler: ?*sdl.SDL_GPUSampler,
    transfer_buffer: ?*sdl.SDL_GPUTransferBuffer,

    pub fn init(allocator: std.mem.Allocator, window_width: u32, window_height: u32, window_title: [*c]const u8) !Renderer {
        if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
            return error.SDLInitFailed;
        }

        const window = sdl.SDL_CreateWindow(window_title, window_width, window_height, sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE) orelse {
            return error.WindowCreationFailed;
        };

        const device = sdl.SDL_CreateGPUDevice(sdl.SDL_GPU_SHADERFORMAT_SPIRV, true, null) orelse {
            return error.DeviceCreationFailed;
        };

        if (sdl.SDL_ClaimWindowForGPUDevice(device, window) == false) {
            return error.WindowClaimFailed;
        }

        _ = sdl.SDL_SetGPUSwapchainParameters(device, window, sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, sdl.SDL_GPU_PRESENTMODE_MAILBOX);

        // Create default sampler
        const default_sampler = sdl.SDL_CreateGPUSampler(device, &sdl.SDL_GPUSamplerCreateInfo{
            .min_filter = sdl.SDL_GPU_FILTER_LINEAR,
            .mag_filter = sdl.SDL_GPU_FILTER_LINEAR,
            .address_mode_u = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_v = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_w = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        }) orelse {
            return error.SamplerCreationFailed;
        };

        // Load shaders
        const shader_vert = loadShader(device, "assets/shaders/compiled/PositionColor.vert.spv", sdl.SDL_GPU_SHADERSTAGE_VERTEX, 1, 0, 0, 0) orelse {
            return error.VertexShaderLoadFailed;
        };

        const shader_frag = loadShader(device, "assets/shaders/compiled/SolidColor.frag.spv", sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0, 0, 1) orelse {
            return error.FragmentShaderLoadFailed;
        };

        // Create pipeline
        const vertex_buffer_desc = sdl.SDL_GPUVertexBufferDescription{
            .slot = 0,
            .pitch = @sizeOf(Vertex),
            .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
        };

        const vertex_attributes = [_]sdl.SDL_GPUVertexAttribute{
            .{
                .location = 0,
                .buffer_slot = 0,
                .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                .offset = @offsetOf(Vertex, "position"),
            },
            .{
                .location = 1,
                .buffer_slot = 0,
                .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
                .offset = @offsetOf(Vertex, "color"),
            },
            .{
                .location = 2,
                .buffer_slot = 0,
                .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                .offset = @offsetOf(Vertex, "uv"),
            },
        };

        const color_target_descriptions = sdl.SDL_GPUColorTargetDescription{
            .format = sdl.SDL_GetGPUSwapchainTextureFormat(device, window),
        };

        const pipeline_info = sdl.SDL_GPUGraphicsPipelineCreateInfo{
            .vertex_shader = shader_vert,
            .fragment_shader = shader_frag,
            .vertex_input_state = .{
                .vertex_buffer_descriptions = &vertex_buffer_desc,
                .num_vertex_buffers = 1,
                .vertex_attributes = &vertex_attributes,
                .num_vertex_attributes = 3,
            },
            .target_info = .{
                .num_color_targets = 1,
                .color_target_descriptions = &color_target_descriptions,
            },
            .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .rasterizer_state = .{
                .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
            },
        };

        const pipeline = sdl.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse {
            return error.PipelineCreationFailed;
        };

        // Create transfer buffer for data uploading
        const transfer_buffer = sdl.SDL_CreateGPUTransferBuffer(device, &sdl.SDL_GPUTransferBufferCreateInfo{
            .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = 1024 * 1024, // 1MB should be enough for most transfers
        }) orelse {
            return error.TransferBufferCreationFailed;
        };

        return Renderer{
            .allocator = allocator,
            .window = window,
            .device = device,
            .pipeline = pipeline,
            .shader_vert = shader_vert,
            .shader_frag = shader_frag,
            .default_sampler = default_sampler,
            .transfer_buffer = transfer_buffer,
        };
    }

    pub fn deinit(self: *Renderer) void {
        if (self.transfer_buffer) |buffer| {
            sdl.SDL_ReleaseGPUTransferBuffer(self.device, buffer);
        }

        if (self.default_sampler) |sampler| {
            sdl.SDL_ReleaseGPUSampler(self.device, sampler);
        }

        if (self.shader_frag) |shader| {
            sdl.SDL_ReleaseGPUShader(self.device, shader);
        }

        if (self.shader_vert) |shader| {
            sdl.SDL_ReleaseGPUShader(self.device, shader);
        }

        if (self.pipeline) |pipeline| {
            sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, pipeline);
        }

        if (self.device) |device| {
            if (self.window) |window| {
                sdl.SDL_ReleaseWindowFromGPUDevice(device, window);
            }
            sdl.SDL_DestroyGPUDevice(device);
        }

        if (self.window) |window| {
            sdl.SDL_DestroyWindow(window);
        }

        sdl.SDL_Quit();
    }

    // Helper methods for resource creation
    pub fn createMeshComponent(self: *Renderer, vertices: []const Vertex, indices: []const u16) !components.MeshData {
        const vertex_buffer = createBuffer(self.device, sdl.SDL_GPU_BUFFERUSAGE_VERTEX, @intCast(u32, @sizeOf(Vertex) * vertices.len)) orelse {
            return error.VertexBufferCreationFailed;
        };

        const index_buffer = createBuffer(self.device, sdl.SDL_GPU_BUFFERUSAGE_VERTEX, @intCast(u32, @sizeOf(u16) * indices.len)) orelse {
            return error.IndexBufferCreationFailed;
        };

        // Upload data
        const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            return error.CommandBufferAcquisitionFailed;
        };

        const copy_pass = sdl.SDL_BeginGPUCopyPass(command_buffer) orelse {
            return error.CopyPassCreationFailed;
        };

        // Upload vertex data
        try uploadToGPU(self.device, copy_pass, self.transfer_buffer, 0, Vertex, vertices, vertex_buffer);

        // Upload index data
        try uploadToGPU(self.device, copy_pass, self.transfer_buffer, @intCast(u32, @sizeOf(Vertex) * vertices.len), u16, indices, index_buffer);

        sdl.SDL_EndGPUCopyPass(copy_pass);
        _ = sdl.SDL_SubmitGPUCommandBuffer(command_buffer);

        return components.MeshData{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .num_indices = @intCast(u32, indices.len),
        };
    }

    pub fn createTextureComponent(self: *Renderer, texture_path: []const u8) !components.TextureData {
        var texture_size = [2]usize{ 0, 0 };
        var image_data: [*c]u8 = stb.stbi_load(texture_path.ptr, @ptrCast(*c_int, &texture_size[0]), @ptrCast(*c_int, &texture_size[1]), null, 4);

        if (image_data == null) {
            return error.TextureLoadFailed;
        }
        defer stb.stbi_image_free(image_data);

        const texture_byte_size: u32 = @intCast(u32, texture_size[0] * texture_size[1] * 4);

        // Create texture
        const texture = sdl.SDL_CreateGPUTexture(self.device, &sdl.SDL_GPUTextureCreateInfo{
            .type = sdl.SDL_GPU_TEXTURETYPE_2D,
            .format = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
            .width = @intCast(u32, texture_size[0]),
            .height = @intCast(u32, texture_size[1]),
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        }) orelse {
            return error.TextureCreationFailed;
        };

        // Create transfer buffer for texture
        const texture_transfer_buffer = sdl.SDL_CreateGPUTransferBuffer(self.device, &sdl.SDL_GPUTransferBufferCreateInfo{
            .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = texture_byte_size,
        }) orelse {
            return error.TextureTransferBufferCreationFailed;
        };
        defer sdl.SDL_ReleaseGPUTransferBuffer(self.device, texture_transfer_buffer);

        // Upload texture data
        const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            return error.CommandBufferAcquisitionFailed;
        };

        const copy_pass = sdl.SDL_BeginGPUCopyPass(command_buffer) orelse {
            return error.CopyPassCreationFailed;
        };

        var pixels = image_data[0..texture_byte_size];
        try uploadTextureGPU(self.device, copy_pass, texture_transfer_buffer, texture, 0, u8, &pixels, texture_size, texture_byte_size);

        sdl.SDL_EndGPUCopyPass(copy_pass);
        _ = sdl.SDL_SubmitGPUCommandBuffer(command_buffer);

        return components.TextureData{
            .texture = texture,
            .sampler = self.default_sampler,
        };
    }

    // Render method to process all renderable entities
    pub fn render(self: *Renderer, registry: *ecs.Registry, active_camera_entity: ecs.EntityId) !void {
        // Get the active camera
        const camera_component = registry.getComponent(active_camera_entity, components.CameraData) orelse {
            return error.NoCameraComponent;
        };

        // Get all entities with Transform and Mesh components
        var renderable_entities = try registry.query(.{ components.Transform, components.MeshData });
        defer renderable_entities.deinit();

        // Begin frame rendering
        const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            return error.CommandBufferAcquisitionFailed;
        };

        var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
        if (sdl.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, self.window, &swapchain_texture, null, null) == false) {
            return error.SwapchainAcquisitionFailed;
        }

        if (swapchain_texture == null) {
            _ = sdl.SDL_SubmitGPUCommandBuffer(command_buffer);
            return error.NullSwapchainTexture;
        }

        var color_target_info = sdl.SDL_GPUColorTargetInfo{
            .texture = swapchain_texture,
            .clear_color = .{
                .r = 0.10,
                .g = 0.10,
                .b = 0.10,
                .a = 1.0,
            },
            .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
            .store_op = sdl.SDL_GPU_STOREOP_STORE,
        };

        // Begin ImGUI rendering if used
        zgui.backend.prepareDrawData(@ptrCast(command_buffer));

        const render_pass = sdl.SDL_BeginGPURenderPass(command_buffer, &color_target_info, 1, null) orelse {
            return error.RenderPassCreationFailed;
        };

        // Bind the pipeline
        sdl.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);

        // Render each entity
        for (renderable_entities.items) |entity_id| {
            const transform = registry.getComponent(entity_id, components.Transform).?;
            const mesh = registry.getComponent(entity_id, components.MeshData).?;

            // Update model matrix if needed
            transform.updateModelMatrix();

            // Bind vertex and index buffers
            const vert_buffer_binding = sdl.SDL_GPUBufferBinding{
                .buffer = mesh.vertex_buffer,
                .offset = 0,
            };
            sdl.SDL_BindGPUVertexBuffers(render_pass, 0, &vert_buffer_binding, 1);
            sdl.SDL_BindGPUIndexBuffer(render_pass, &.{ .buffer = mesh.index_buffer, .offset = 0 }, sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT);

            // Push uniform data (model-view-projection)
            const ubo = UniformBufferObject{
                .model = transform.model_matrix,
                .view = camera_component.view_matrix,
                .projection = camera_component.projection_matrix,
            };

            sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, &ubo, @sizeOf(UniformBufferObject));

            // Bind texture if entity has one
            if (registry.hasComponent(entity_id, components.TextureData)) {
                const texture_comp = registry.getComponent(entity_id, components.TextureData).?;
                sdl.SDL_BindGPUFragmentSamplers(render_pass, 0, &(sdl.SDL_GPUTextureSamplerBinding{ .texture = texture_comp.texture, .sampler = texture_comp.sampler }), 1);
            }

            // Draw
            sdl.SDL_DrawGPUIndexedPrimitives(render_pass, mesh.num_indices, 1, 0, 0, 0);
        }

        // Render ImGUI if used
        zgui.backend.renderDrawData(@ptrCast(command_buffer), @ptrCast(render_pass), null);

        sdl.SDL_EndGPURenderPass(render_pass);
        _ = sdl.SDL_SubmitGPUCommandBuffer(command_buffer);
    }

    // Utility functions (copied from your original code)
    fn loadShader(
        device: *sdl.SDL_GPUDevice,
        filename: [*c]const u8,
        stage: sdl.SDL_GPUShaderStage,
        uniform_buffer_count: u32,
        storage_buffer_count: u32,
        storage_texture_count: u32,
        sampler_count: u32,
    ) ?*sdl.SDL_GPUShader {
        // Implementation from your original code
    }

    fn createBuffer(device: *sdl.SDL_GPUDevice, usage: sdl.SDL_GPUBufferUsageFlags, size: u32) ?*sdl.SDL_GPUBuffer {
        // Implementation from your original code
    }

    fn uploadToGPU(
        device: *sdl.SDL_GPUDevice,
        copy_pass: *sdl.SDL_GPUCopyPass,
        transfer_buffer: *sdl.SDL_GPUTransferBuffer,
        buffer_offset: u32,
        comptime T: type,
        data: []const T,
        buffer: *sdl.SDL_GPUBuffer,
    ) !void {
        // Implementation from your original code
    }

    fn uploadTextureGPU(
        device: *sdl.SDL_GPUDevice,
        copy_pass: *sdl.SDL_GPUCopyPass,
        transfer_buffer: *sdl.SDL_GPUTransferBuffer,
        texture: *sdl.SDL_GPUTexture,
        buffer_offset: u32,
        comptime T: type,
        images_data: *[]u8,
        image_size: [2]usize,
        image_byte_size: usize,
    ) !void {
        // Implementation from your original code
    }
};
