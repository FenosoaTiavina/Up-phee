const std = @import("std");

const ecs = @import("ecs");
const zm = @import("zmath");
const zgui = @import("zgui");

const T_ = @import("types.zig");
const c = @import("imports.zig");
const shader = @import("shader.zig");
const components = @import("./components/components.zig");

pub const Window = struct {
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
    device: *c.sdl.SDL_GPUDevice,
    default_sampler: ?*c.sdl.SDL_GPUSampler,
    transfer_buffer: ?*c.sdl.SDL_GPUTransferBuffer,
    command_buffers: std.ArrayList(*c.sdl.SDL_GPUCommandBuffer),
    render_pass: ?*c.sdl.SDL_GPURenderPass = null,
    pipelines: std.AutoHashMap(u32, *c.sdl.SDL_GPUGraphicsPipeline),

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, title: [*c]const u8) !Renderer {
        const window = try Window.init(width, height, title);
        const device = c.sdl.SDL_CreateGPUDevice(c.sdl.SDL_GPU_SHADERFORMAT_SPIRV, true, null) orelse return error.DeviceCreationFailed;
        if (!c.sdl.SDL_ClaimWindowForGPUDevice(device, window.sdl_window)) return error.WindowClaimFailed;

        _ = c.sdl.SDL_SetGPUSwapchainParameters(device, window.sdl_window, c.sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, c.sdl.SDL_GPU_PRESENTMODE_MAILBOX);

        const sampler = c.sdl.SDL_CreateGPUSampler(device, &.{
            .min_filter = c.sdl.SDL_GPU_FILTER_LINEAR,
            .mag_filter = c.sdl.SDL_GPU_FILTER_LINEAR,
            .address_mode_u = c.sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_v = c.sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_w = c.sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        }) orelse return error.SamplerCreationFailed;

        const transfer = c.sdl.SDL_CreateGPUTransferBuffer(device, &.{
            .usage = c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = 1024 * 1024,
        }) orelse return error.TransferBufferCreationFailed;

        return Renderer{
            .allocator = allocator,
            .window = window,
            .device = device,
            .default_sampler = sampler,
            .command_buffers = std.ArrayList(*c.sdl.SDL_GPUCommandBuffer).init(allocator),
            .transfer_buffer = transfer,
            .pipelines = std.AutoHashMap(u32, *c.sdl.SDL_GPUGraphicsPipeline).init(allocator),
        };
    }

    pub fn deinit(self: *Renderer) void {
        if (self.transfer_buffer) |buffer| {
            c.sdl.SDL_ReleaseGPUTransferBuffer(self.device, buffer);
        }

        if (self.default_sampler) |sampler| {
            c.sdl.SDL_ReleaseGPUSampler(self.device, sampler);
        }

        var it = self.pipelines.iterator();
        while (it.next()) |entry| {
            const pipeline = entry.value_ptr.*;
            c.sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, pipeline);
        }
        c.sdl.SDL_ReleaseWindowFromGPUDevice(self.device, self.window.sdl_window);
        c.sdl.SDL_DestroyGPUDevice(self.device);

        self.window.deinit();
    }

    pub fn getAspectRatio(self: *Renderer) f32 {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.sdl.SDL_GetWindowSize(self.*.window.sdl_window, &w, &h);
        return @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
    }

    pub fn beginFrame(self: *Renderer) !void {
        const command_buffer = c.sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            return error.CommandBufferAcquisitionFailed;
        };

        try self.*.command_buffers.append(command_buffer);

        var swapchain_texture: ?*c.sdl.SDL_GPUTexture = null;
        if (c.sdl.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, self.*.window.sdl_window, &swapchain_texture, null, null) == false) {
            return error.SwapchainAcquisitionFailed;
        }

        if (swapchain_texture == null) {
            return error.NullSwapchainTexture;
        }

        var color_target_info = c.sdl.SDL_GPUColorTargetInfo{
            .texture = swapchain_texture,
            .clear_color = .{
                .r = 0.28,
                .g = 0.28,
                .b = 0.28,
                .a = 1.0,
            },
            .load_op = c.sdl.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.sdl.SDL_GPU_STOREOP_STORE,
        };

        zgui.backend.prepareDrawData(@ptrCast(command_buffer));

        const render_pass = c.sdl.SDL_BeginGPURenderPass(command_buffer, &color_target_info, 1, null) orelse {
            return error.RenderPassCreationFailed;
        };

        self.*.render_pass = render_pass;

        var it = self.pipelines.iterator();
        while (it.next()) |entry| {
            const pipeline = entry.value_ptr.*;
            c.sdl.SDL_BindGPUGraphicsPipeline(self.render_pass, pipeline);
        }
    }

    pub fn render(self: *Renderer, registry: *ecs.Registry, active_camera_entity: ecs.Entity) !void {
        const cmd = self.command_buffers.items[0];

        const camera_component = registry.get(components.Camera.CameraData, active_camera_entity);

        var renderable_entities = registry.view(
            .{
                components.Transform.Transform,
                components.Mesh.MeshData,
            },
            .{},
        );

        var entt_view_iter = renderable_entities.entityIterator();

        while (entt_view_iter.next()) |entity| {
            const mesh = renderable_entities.get(components.Mesh.MeshData, entity);
            const trasform = renderable_entities.get(components.Transform.Transform, entity);

            if (registry.has(PipelineComponent, entity)) {
                const pipeline_comp =
                    registry.get(PipelineComponent, entity);
                c.sdl.SDL_BindGPUGraphicsPipeline(self.render_pass, self.pipelines.get(pipeline_comp.*.handle));
            }

            if (registry.has(components.Mesh.TextureData, entity)) {
                const texture_comp: components.Mesh.TextureData = renderable_entities.get(components.Mesh.TextureData, entity).*;
                c.sdl.SDL_BindGPUFragmentSamplers(
                    self.render_pass,
                    0,
                    &(c.sdl.SDL_GPUTextureSamplerBinding{ .texture = texture_comp.texture, .sampler = texture_comp.sampler }),
                    1,
                );
            }

            components.Mesh.updateAndRender(
                cmd,
                self.render_pass.?,
                trasform,
                mesh,
                camera_component,
            );
        }

        zgui.backend.renderDrawData(cmd, self.render_pass.?, null);
    }

    pub fn endFrame(self: *Renderer) !void {
        c.sdl.SDL_EndGPURenderPass(self.*.render_pass);

        for (self.command_buffers.items) |cmd_buf| {
            _ = c.sdl.SDL_SubmitGPUCommandBuffer(cmd_buf);
        }

        self.*.command_buffers.clearAndFree();
    }
};

const GraphicsPipelineDesc = struct {
    vertex_shader: shader.Shader,
    fragment_shader: shader.Shader,
    vertex_input_state: c.sdl.SDL_GPUVertexInputState,
    wireframe: bool,
};

const PipelineComponent = struct {
    handle: u32,
};

pub fn createGraphicsPipeline(renderer: *Renderer, desc: GraphicsPipelineDesc) !void {
    const shader_vert = desc.vertex_shader.module;
    const shader_frag = desc.fragment_shader.module;

    const pipeline_info = c.sdl.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = shader_vert,
        .fragment_shader = shader_frag,
        .vertex_input_state = desc.vertex_input_state,
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &.{
                .format = c.sdl.SDL_GetGPUSwapchainTextureFormat(renderer.device, renderer.window.sdl_window),
            },
        },
        .primitive_type = c.sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .fill_mode = if (desc.wireframe) c.sdl.SDL_GPU_FILLMODE_LINE else c.sdl.SDL_GPU_FILLMODE_FILL,
        },
    };

    const pipeline = c.sdl.SDL_CreateGPUGraphicsPipeline(renderer.device, &pipeline_info) orelse return error.PipelineCreationFailed;
    const id: u32 = std.hash.uint32(@intCast(@intFromPtr(pipeline)));
    try renderer.pipelines.put(id, pipeline);
}

pub fn createBuffer(
    device: *c.sdl.SDL_GPUDevice,
    usage: c.sdl.SDL_GPUBufferUsageFlags,
    size: u32,
) ?*c.sdl.SDL_GPUBuffer {
    const buffer_create_info = c.sdl.SDL_GPUBufferCreateInfo{
        .usage = usage,
        .size = size,
    };
    return c.sdl.SDL_CreateGPUBuffer(device, &buffer_create_info);
}

pub fn uploadToGPU(
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

pub fn uploadTextureGPU(
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
