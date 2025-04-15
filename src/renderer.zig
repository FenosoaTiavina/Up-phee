// renderer.zig
const std = @import("std");
const zm = @import("zmath");
// const zgui = @import("zgui");
const ecs = @import("ecs");
const T_ = @import("./types.zig");
const components = @import("components.zig");

const c = @import("imports.zig");

const Window = struct {
    sdl_window: *c.sdl.SDL_Window,
    window_dimension: T_.Vec2_usize,
    window_title: [*c]const u8,

    pub fn init(window_width: u32, window_height: u32, window_title: [*c]const u8) !Window {
        if (!c.sdl.SDL_Init(c.sdl.SDL_INIT_VIDEO)) {
            return error.SDLInitFailed;
        }

        const window = c.sdl.SDL_CreateWindow(window_title, @intCast(window_width), @intCast(window_height), c.sdl.SDL_WINDOW_VULKAN | c.sdl.SDL_WINDOW_RESIZABLE) orelse {
            return error.WindowCreationFailed;
        };

        return Window{
            .sdl_window = window,
            .window_dimension = T_.Vec2_usize{ @intCast(window_width), @intCast(window_height) },
            .window_title = window_title,
        };
    }

    pub fn deinit(self: *Window) void {
        c.sdl.SDL_DestroyWindow(self.sdl_window);
        c.sdl.SDL_Quit();
    }
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    window: Window,
    device: ?*c.sdl.SDL_GPUDevice,
    pipeline: ?*c.sdl.SDL_GPUGraphicsPipeline,
    shader_vert: ?*c.sdl.SDL_GPUShader,
    shader_frag: ?*c.sdl.SDL_GPUShader,
    default_sampler: ?*c.sdl.SDL_GPUSampler,
    transfer_buffer: ?*c.sdl.SDL_GPUTransferBuffer,

    pub fn init(allocator: std.mem.Allocator, window_width: u32, window_height: u32, window_title: [*c]const u8) !Renderer {
        const window = try Window.init(window_width, window_height, window_title);

        const device = c.sdl.SDL_CreateGPUDevice(c.sdl.SDL_GPU_SHADERFORMAT_SPIRV, true, null) orelse {
            return error.DeviceCreationFailed;
        };

        if (c.sdl.SDL_ClaimWindowForGPUDevice(device, window.sdl_window) == false) {
            return error.WindowClaimFailed;
        }

        _ = c.sdl.SDL_SetGPUSwapchainParameters(device, window.sdl_window, c.sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, c.sdl.SDL_GPU_PRESENTMODE_MAILBOX);

        // Create default sampler
        const default_sampler = c.sdl.SDL_CreateGPUSampler(device, &c.sdl.SDL_GPUSamplerCreateInfo{
            .min_filter = c.sdl.SDL_GPU_FILTER_LINEAR,
            .mag_filter = c.sdl.SDL_GPU_FILTER_LINEAR,
            .address_mode_u = c.sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_v = c.sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_w = c.sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        }) orelse {
            return error.SamplerCreationFailed;
        };

        // Load shaders
        const shader_vert = loadShader(device, "assets/shaders/compiled/PositionColor.vert.spv", c.sdl.SDL_GPU_SHADERSTAGE_VERTEX, 1, 0, 0, 0) orelse {
            return error.VertexShaderLoadFailed;
        };

        const shader_frag = loadShader(device, "assets/shaders/compiled/SolidColor.frag.spv", c.sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0, 0, 1) orelse {
            return error.FragmentShaderLoadFailed;
        };

        // Create pipeline
        const vertex_buffer_desc = c.sdl.SDL_GPUVertexBufferDescription{
            .slot = 0,
            .pitch = @sizeOf(components.mesh.Vertex),
            .input_rate = c.sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
        };

        const vertex_attributes = [_]c.sdl.SDL_GPUVertexAttribute{
            .{
                .location = 0,
                .buffer_slot = 0,
                .format = c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                .offset = @offsetOf(components.mesh.Vertex, "position"),
            },
            .{
                .location = 1,
                .buffer_slot = 0,
                .format = c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
                .offset = @offsetOf(components.mesh.Vertex, "color"),
            },
            .{
                .location = 2,
                .buffer_slot = 0,
                .format = c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                .offset = @offsetOf(components.mesh.Vertex, "uv"),
            },
        };

        const color_target_descriptions = c.sdl.SDL_GPUColorTargetDescription{
            .format = c.sdl.SDL_GetGPUSwapchainTextureFormat(device, window.sdl_window),
        };

        const pipeline_info = c.sdl.SDL_GPUGraphicsPipelineCreateInfo{
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
            .primitive_type = c.sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .rasterizer_state = .{
                .fill_mode = c.sdl.SDL_GPU_FILLMODE_FILL,
            },
        };

        const pipeline = c.sdl.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse {
            return error.PipelineCreationFailed;
        };

        // Create transfer buffer for data uploading
        const transfer_buffer = c.sdl.SDL_CreateGPUTransferBuffer(device, &c.sdl.SDL_GPUTransferBufferCreateInfo{
            .usage = c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
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
            c.sdl.SDL_ReleaseGPUTransferBuffer(self.device, buffer);
        }

        if (self.default_sampler) |sampler| {
            c.sdl.SDL_ReleaseGPUSampler(self.device, sampler);
        }

        if (self.shader_frag) |shader| {
            c.sdl.SDL_ReleaseGPUShader(self.device, shader);
        }

        if (self.shader_vert) |shader| {
            c.sdl.SDL_ReleaseGPUShader(self.device, shader);
        }

        if (self.pipeline) |pipeline| {
            c.sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, pipeline);
        }

        if (self.device) |device| {
            c.sdl.SDL_ReleaseWindowFromGPUDevice(device, self.window.sdl_window);
            c.sdl.SDL_DestroyGPUDevice(device);
        }

        self.window.deinit();
    }

    // Helper methods for resource creation
    pub fn createMeshComponent(self: *Renderer, vertices: []const components.mesh.Vertex, indices: []const u16) !components.mesh.MeshData {
        const vertex_buffer = createBuffer(self.device.?, c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX, @intCast(@sizeOf(components.mesh.Vertex) * vertices.len)) orelse {
            return error.VertexBufferCreationFailed;
        };

        const index_buffer = createBuffer(self.device.?, c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX, @intCast(@sizeOf(u16) * indices.len)) orelse {
            return error.IndexBufferCreationFailed;
        };

        // Upload data
        const command_buffer = c.sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            return error.CommandBufferAcquisitionFailed;
        };

        const copy_pass = c.sdl.SDL_BeginGPUCopyPass(command_buffer) orelse {
            return error.CopyPassCreationFailed;
        };

        try uploadToGPU(self.device.?, copy_pass, self.transfer_buffer.?, 0, components.mesh.Vertex, vertices, vertex_buffer);
        try uploadToGPU(self.device.?, copy_pass, self.transfer_buffer.?, @intCast(@sizeOf(components.mesh.Vertex) * vertices.len), u16, indices, index_buffer);

        c.sdl.SDL_EndGPUCopyPass(copy_pass);
        _ = c.sdl.SDL_SubmitGPUCommandBuffer(command_buffer);

        return components.mesh.MeshData{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .num_indices = @intCast(indices.len),
        };
    }

    pub fn createTextureComponent(self: *Renderer, texture_path: []const u8) !components.mesh.TextureData {
        var texture_size = [2]usize{ 0, 0 };
        var image_data: [*c]u8 = c.stb.stbi_load(texture_path.ptr, @ptrCast(&texture_size[0]), @ptrCast(&texture_size[1]), null, 4);

        if (image_data == null) {
            return error.TextureLoadFailed;
        }
        defer c.stb.stbi_image_free(image_data);

        const texture_byte_size: u32 = @intCast(texture_size[0] * texture_size[1] * 4);

        // Create texture
        const texture = c.sdl.SDL_CreateGPUTexture(self.device, &c.sdl.SDL_GPUTextureCreateInfo{
            .type = c.sdl.SDL_GPU_TEXTURETYPE_2D,
            .format = c.sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
            .width = @intCast(texture_size[0]),
            .height = @intCast(texture_size[1]),
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .usage = c.sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        }) orelse {
            return error.TextureCreationFailed;
        };

        // Create transfer buffer for texture
        const texture_transfer_buffer = c.sdl.SDL_CreateGPUTransferBuffer(self.device, &c.sdl.SDL_GPUTransferBufferCreateInfo{
            .usage = c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = texture_byte_size,
        }) orelse {
            return error.TextureTransferBufferCreationFailed;
        };
        defer c.sdl.SDL_ReleaseGPUTransferBuffer(self.device, texture_transfer_buffer);

        // Upload texture data
        const command_buffer = c.sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            return error.CommandBufferAcquisitionFailed;
        };

        const copy_pass = c.sdl.SDL_BeginGPUCopyPass(command_buffer) orelse {
            return error.CopyPassCreationFailed;
        };

        var pixels = image_data[0..texture_byte_size];
        try uploadTextureGPU(self.device.?, copy_pass, texture_transfer_buffer, texture, 0, u8, &pixels, texture_size, texture_byte_size);

        c.sdl.SDL_EndGPUCopyPass(copy_pass);
        _ = c.sdl.SDL_SubmitGPUCommandBuffer(command_buffer);

        return components.mesh.TextureData{
            .texture = texture,
            .sampler = self.default_sampler,
        };
    }

    // Render method to process all renderable entities
    pub fn render(self: *Renderer, registry: *ecs.Registry, active_camera_entity: ecs.Entity) !void {
        // Get the active camera
        const camera_component = registry.get(components.camera.CameraData, active_camera_entity);

        // Get all entities with Transform and Mesh components
        var renderable_entities = registry.view(.{ components.transform.Transform, components.mesh.MeshData }, .{});
        // Begin frame rendering
        const command_buffer = c.sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            return error.CommandBufferAcquisitionFailed;
        };

        var swapchain_texture: ?*c.sdl.SDL_GPUTexture = null;
        if (c.sdl.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, self.*.window.sdl_window, &swapchain_texture, null, null) == false) {
            return error.SwapchainAcquisitionFailed;
        }

        if (swapchain_texture == null) {
            _ = c.sdl.SDL_SubmitGPUCommandBuffer(command_buffer);
            return error.NullSwapchainTexture;
        }

        var color_target_info = c.sdl.SDL_GPUColorTargetInfo{
            .texture = swapchain_texture,
            .clear_color = .{
                .r = 0.10,
                .g = 0.10,
                .b = 0.10,
                .a = 1.0,
            },
            .load_op = c.sdl.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.sdl.SDL_GPU_STOREOP_STORE,
        };

        // Begin ImGUI rendering if used
        // zgui.backend.prepareDrawData(@ptrCast(command_buffer));

        const render_pass = c.sdl.SDL_BeginGPURenderPass(command_buffer, &color_target_info, 1, null) orelse {
            return error.RenderPassCreationFailed;
        };

        // Bind the pipeline
        c.sdl.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);

        var iter = renderable_entities.entityIterator();
        // Render each entity
        while (iter.next()) |entity_id| {
            std.log.debug("{any}", .{camera_component});
            const transform = renderable_entities.get(components.transform.Transform, entity_id);
            const mesh = renderable_entities.get(components.mesh.MeshData, entity_id);

            // Update model matrix if needed
            components.transform.updateModelMatrix(transform);

            // Bind vertex and index buffers
            const vert_buffer_binding = c.sdl.SDL_GPUBufferBinding{
                .buffer = mesh.vertex_buffer,
                .offset = 0,
            };
            c.sdl.SDL_BindGPUVertexBuffers(render_pass, 0, &vert_buffer_binding, 1);
            c.sdl.SDL_BindGPUIndexBuffer(render_pass, &.{ .buffer = mesh.index_buffer, .offset = 0 }, c.sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT);

            // Push uniform data (model-view-projection)
            const ubo = components.render.UniformBufferObject{
                .model = transform.model_matrix,
                .view = camera_component.view_matrix,
                .projection = camera_component.projection_matrix,
            };

            c.sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, &ubo, @sizeOf(components.render.UniformBufferObject));

            // Bind texture if entity has one
            if (registry.has(components.mesh.TextureData, entity_id)) {
                const texture_comp: components.mesh.TextureData = renderable_entities.get(components.mesh.TextureData, entity_id).*;
                c.sdl.SDL_BindGPUFragmentSamplers(render_pass, 0, &(c.sdl.SDL_GPUTextureSamplerBinding{ .texture = texture_comp.texture, .sampler = texture_comp.sampler }), 1);
            }

            // Draw
            c.sdl.SDL_DrawGPUIndexedPrimitives(render_pass, mesh.num_indices, 1, 0, 0, 0);
        }

        // Render ImGUI if used
        // zgui.backend.renderDrawData(@ptrCast(command_buffer), @ptrCast(render_pass), null);

        c.sdl.SDL_EndGPURenderPass(render_pass);
        _ = c.sdl.SDL_SubmitGPUCommandBuffer(command_buffer);
    }

    pub fn getAspectRatio(self: *Renderer) f32 {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.sdl.SDL_GetWindowSize(self.*.window.sdl_window, &w, &h);
        return @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
    }

    // Utility functions (copied from your original code)
    fn loadShader(
        device: *c.sdl.SDL_GPUDevice,
        filename: [*c]const u8,
        stage: c.sdl.SDL_GPUShaderStage,
        uniform_buffer_count: u32,
        storage_buffer_count: u32,
        storage_texture_count: u32,
        sampler_count: u32,
    ) ?*c.sdl.SDL_GPUShader {
        if (c.sdl.SDL_GetPathInfo(filename, null) == false) {
            std.log.err("File ({s}) does not exist.\n", .{filename});
            return null;
        }

        var entrypoint: [*c]const u8 = undefined;
        const backend_formats = c.sdl.SDL_GetGPUShaderFormats(device);
        var format: c.sdl.SDL_GPUShaderFormat = c.sdl.SDL_GPU_SHADERFORMAT_INVALID;
        if (backend_formats & c.sdl.SDL_GPU_SHADERFORMAT_SPIRV != 0) {
            format = c.sdl.SDL_GPU_SHADERFORMAT_SPIRV;
            entrypoint = "main";
        }

        var code_size: usize = undefined;
        const code: [*c]const u8 = @ptrCast(c.sdl.SDL_LoadFile(filename, &code_size).?);

        defer c.sdl.SDL_free(@constCast(code));

        const shader_info = c.sdl.SDL_GPUShaderCreateInfo{
            .code = code,
            .code_size = code_size,
            .entrypoint = entrypoint,
            .format = format,
            .stage = stage,
            .num_samplers = sampler_count,
            .num_uniform_buffers = uniform_buffer_count,
            .num_storage_buffers = storage_buffer_count,
            .num_storage_textures = storage_texture_count,
        };

        const shader = c.sdl.SDL_CreateGPUShader(device, &shader_info);
        if (shader == null) {
            std.log.err("ERROR: SDL_CreateGPUShader failed: {s}\n", .{c.sdl.SDL_GetError()});
            return null;
        }

        return shader;
    }

    fn createBuffer(device: *c.sdl.SDL_GPUDevice, usage: c.sdl.SDL_GPUBufferUsageFlags, size: u32) ?*c.sdl.SDL_GPUBuffer {
        const buffer_create_info = c.sdl.SDL_GPUBufferCreateInfo{
            .usage = usage,
            .size = size,
        };
        return c.sdl.SDL_CreateGPUBuffer(device, &buffer_create_info);
    }

    fn uploadToGPU(
        device: *c.sdl.SDL_GPUDevice,
        copy_pass: *c.sdl.SDL_GPUCopyPass,
        transfer_buffer: *c.sdl.SDL_GPUTransferBuffer,
        buffer_offset: u32,
        comptime T: type,
        data: []const T,
        buffer: *c.sdl.SDL_GPUBuffer,
    ) !void {
        const total_size: u32 = @intCast(@sizeOf(T) * data.len);

        // Map the buffer memory
        const transfer_data = c.sdl.SDL_MapGPUTransferBuffer(device, transfer_buffer, false) orelse {
            std.log.err("SDL_MapGPUTransferBuffer Failed (upload_cmdbuf)", .{});
            return error.MapFailed;
        };

        // Cast the pointer to bytes and copy the data at the specified offset
        const transfer_bytes = @as([*]u8, @ptrCast(transfer_data));
        @memcpy(transfer_bytes[buffer_offset .. buffer_offset + total_size], @as([*]const u8, @ptrCast(data.ptr)));

        c.sdl.SDL_UnmapGPUTransferBuffer(device, transfer_buffer);

        const transfer_buffer_location = c.sdl.SDL_GPUTransferBufferLocation{
            .transfer_buffer = transfer_buffer,
            .offset = buffer_offset,
        };

        const buffer_region = c.sdl.SDL_GPUBufferRegion{
            .buffer = buffer,
            .offset = 0,
            .size = total_size,
        };

        c.sdl.SDL_UploadToGPUBuffer(copy_pass, &transfer_buffer_location, &buffer_region, false);
    }

    fn uploadTextureGPU(
        device: *c.sdl.SDL_GPUDevice,
        copy_pass: *c.sdl.SDL_GPUCopyPass,
        transfer_buffer: *c.sdl.SDL_GPUTransferBuffer,
        texture: *c.sdl.SDL_GPUTexture,
        buffer_offset: u32,
        comptime T: type,
        images_data: *[]u8,
        image_size: T_.Vec2_usize,
        image_byte_size: usize,
    ) !void {
        // Map the buffer memory
        const transfer_data = c.sdl.SDL_MapGPUTransferBuffer(device, transfer_buffer, false) orelse {
            std.log.err("SDL_MapGPUTransferBuffer Failed (upload_cmdbuf)", .{});
            return error.MapFailed;
        };

        // Cast the pointer to bytes and copy the data at the specified offset
        const transfer_bytes: [*]T = @ptrCast(transfer_data);
        @memcpy(transfer_bytes[buffer_offset .. buffer_offset + image_byte_size], images_data.ptr);
        c.sdl.SDL_UnmapGPUTransferBuffer(device, transfer_buffer);

        const texture_transfer_info = c.sdl.struct_SDL_GPUTextureTransferInfo{
            .transfer_buffer = transfer_buffer,
            .offset = buffer_offset,
        };

        // FIX: correct width and height parameters
        const texture_region = c.sdl.SDL_GPUTextureRegion{
            .texture = texture,
            .w = @intCast(image_size[0]),
            .h = @intCast(image_size[1]), // FIXed: was using 'y' property instead of 'h'
            .d = 1,
        };

        c.sdl.SDL_UploadToGPUTexture(copy_pass, &texture_transfer_info, &texture_region, false);
    }
};
