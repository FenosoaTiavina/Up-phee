const std = @import("std");

const ecs = @import("ecs");
const zm = @import("zmath");
const zgui = @import("zgui");

const Types = @import("types.zig");
const c = @import("imports.zig");
const Shader = @import("shader.zig");
const uph3d = @import("./3d/3d.zig");

pub const Window = struct {
    sdl_window: *c.sdl.SDL_Window,
    window_dimension: Types.Size,
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
            .window_dimension = Types.Size{ .width = @intCast(window_width), .height = @intCast(window_height) },
            .window_title = window_title,
        };
    }

    pub fn getSize(self: *Window) Types.Size {
        return self.window_dimension;
    }
    pub fn deinit(self: *Window) void {
        c.sdl.SDL_DestroyWindow(self.sdl_window);
        c.sdl.SDL_Quit();
    }
};

pub const Cmd = struct {
    pub const CmdType = enum { submitted, rogue };
    command_buffer: *c.sdl.SDL_GPUCommandBuffer,
    submition: union(CmdType) {
        submitted: bool,
        rogue: void,
    },
    pub fn init(allocator: std.mem.Allocator, cmd_b: *c.sdl.SDL_GPUCommandBuffer) !*Cmd {
        const cmd = try allocator.create(Cmd);
        cmd.*.command_buffer = cmd_b;
        return cmd;
    }

    pub fn deinit(self: *Cmd, allocator: std.mem.Allocator) void {
        allocator.free(self);
    }

    pub fn sumbit(self: *Cmd) bool {
        if (!c.sdl.SDL_SubmitGPUCommandBuffer(self.command_buffer)) {
            std.log.err("Failed cmd_buf.Submit {s} ", .{c.sdl.SDL_GetError()});
            return false;
        }

        switch (self.submition) {
            .submitted => |*s| {
                s.* = true;
            },
            .rogue => {},
        }

        return true;
    }
};

pub const RenderManager = struct {
    allocator: std.mem.Allocator,
    window: Window,
    device: *c.sdl.SDL_GPUDevice,
    default_sampler: *c.sdl.SDL_GPUSampler,
    command_buffers: std.AutoHashMap(u32, *Cmd),
    pipelines: std.AutoHashMap(u32, *c.sdl.SDL_GPUGraphicsPipeline),

    clear_color: Types.Vec4_f32,
    target_info: c.sdl.SDL_GPUColorTargetInfo = undefined,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, title: [*:0]const u8) !*RenderManager {
        var window = try Window.init(width, height, title);

        const device = c.sdl.SDL_CreateGPUDevice(c.sdl.SDL_GPU_SHADERFORMAT_SPIRV, true, null) orelse return error.DeviceCreationFailed;

        if (!c.sdl.SDL_ClaimWindowForGPUDevice(device, window.sdl_window))
            return error.WindowClaimFailed;

        _ = c.sdl.SDL_SetGPUSwapchainParameters(device, window.sdl_window, c.sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, c.sdl.SDL_GPU_PRESENTMODE_MAILBOX);

        const sampler = c.sdl.SDL_CreateGPUSampler(device, &.{
            .min_filter = c.sdl.SDL_GPU_FILTER_LINEAR,
            .mag_filter = c.sdl.SDL_GPU_FILTER_LINEAR,
            .address_mode_u = c.sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_v = c.sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_w = c.sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        }) orelse {
            c.sdl.SDL_DestroyGPUDevice(device);
            window.deinit();
            return error.SamplerCreationFailed;
        };

        const renderer = try allocator.create(RenderManager);

        const default_color = Types.Vec4_f32{ 0, 0, 0, 1 };

        renderer.* = RenderManager{
            .allocator = allocator,
            .window = window,
            .device = device,
            .default_sampler = sampler,
            .command_buffers = std.AutoHashMap(u32, *Cmd).init(allocator),
            .clear_color = default_color,
            .pipelines = std.AutoHashMap(u32, *c.sdl.SDL_GPUGraphicsPipeline).init(allocator),
        };
        return renderer;
    }

    pub fn deinit(self: *RenderManager) void {
        var it = self.pipelines.iterator();

        while (it.next()) |pipeline_entry| {
            c.sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, pipeline_entry.value_ptr.*);
            self.pipelines.removeByPtr(pipeline_entry.key_ptr);
        }

        self.pipelines.clearAndFree();
        self.pipelines.deinit();
        var cmd_it = self.command_buffers.iterator();

        while (cmd_it.next()) |cmd| {
            self.allocator.destroy(cmd.value_ptr.*);
        }
        self.command_buffers.deinit();

        c.sdl.SDL_ReleaseGPUSampler(self.device, self.default_sampler);

        c.sdl.SDL_ReleaseWindowFromGPUDevice(self.device, self.window.sdl_window);
        c.sdl.SDL_DestroyGPUDevice(self.device);

        self.window.deinit();

        self.allocator.destroy(self);
    }

    pub fn getAspectRatio(self: *const RenderManager) f32 {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.sdl.SDL_GetWindowSize(self.window.sdl_window, &w, &h);
        return @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
    }

    pub fn getPipeline(self: *RenderManager, pipeline_id: u32) !*c.sdl.SDL_GPUGraphicsPipeline {
        return self.pipelines.get(pipeline_id) orelse {
            return error.GraphicsPipelineDoesNotExist;
        };
    }

    pub fn bindGraphicsPipeline(
        self: *RenderManager,
        render_pass: ?*c.sdl.SDL_GPURenderPass,
        pipeline_handle: u32,
    ) !void {
        c.sdl.SDL_BindGPUGraphicsPipeline(render_pass, try self.getPipeline(pipeline_handle));
    }

    pub fn resetCommandBuffer(self: *RenderManager, id: u32) !void {
        const command_buffer = c.sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            return error.CommandBufferAcquisitionFailed;
        };

        const old = self.command_buffers.fetchRemove(id) orelse {
            return error.CmdNotFound;
        };
        old.value.deinit(self.allocator);

        try self.command_buffers.put(id, try Cmd.init(self.allocator, command_buffer));
    }

    pub fn newCommand(self: *RenderManager) !u32 {
        const command_buffer = c.sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            return error.CommandBufferAcquisitionFailed;
        };
        const id: u32 = self.command_buffers.count();

        try self.command_buffers.put(id, try Cmd.init(self.allocator, command_buffer));

        return id;
    }

    pub fn submitRogueCommand(self: *RenderManager, cmd: *u32) !void {
        if (!cmd.sumbit()) {
            std.log.err("Failed cmd_buf.Submit {s} ", .{c.sdl.SDL_GetError()});
            cmd.deinit(self.allocator);
            return error.CommandBufferSubmit;
        }
    }

    pub fn createRogueCommand(self: *RenderManager) !*Cmd {
        const command_buffer = c.sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            return error.CommandBufferAcquisitionFailed;
        };

        return try Cmd.init(self.allocator, command_buffer);
    }

    pub fn submitCommand(self: *RenderManager, id: u32) !void {
        var cmd = self.command_buffers.get(id) orelse {
            return error.CmdNotFound;
        };

        if (cmd.submition) {
            return error.CmdAlreadySubmitted;
        }

        if (!cmd.sumbit()) {
            std.log.err("Failed cmd_buf.Submit {s} ", .{c.sdl.SDL_GetError()});
            return error.CommandBufferSubmit;
        }
    }

    pub fn getCommandBuffer(self: *RenderManager, command_buffer_id: u32) !*Cmd {
        return self.command_buffers.get(command_buffer_id) orelse {
            return error.CommandBufferDoesNotExist;
        };
    }

    pub fn createTransferBuffer(
        self: *RenderManager,
        usage: c.sdl.SDL_GPUTransferBufferUsage,
        size: u32,
    ) !*c.sdl.SDL_GPUTransferBuffer {
        return c.sdl.SDL_CreateGPUTransferBuffer(self.device, &.{
            .usage = usage,
            .size = size,
        }) orelse return error.TransferBufferCreationFailed;
    }

    pub fn clear(self: *RenderManager, color: Types.Vec4_f32) void {
        self.clear_color = color;
    }

    pub fn setTargetColor(self: *RenderManager, cmd: *Cmd) !void {
        var swapchain_texture: ?*c.sdl.SDL_GPUTexture = null;
        if (c.sdl.SDL_WaitAndAcquireGPUSwapchainTexture(cmd.command_buffer, self.*.window.sdl_window, &swapchain_texture, null, null) == false) {
            return error.SwapchainAcquisitionFailed;
        }

        if (swapchain_texture == null) {
            return error.NullSwapchainTexture;
        }

        self.target_info = c.sdl.SDL_GPUColorTargetInfo{
            .texture = swapchain_texture,
            .clear_color = .{
                .r = self.clear_color[0],
                .g = self.clear_color[1],
                .b = self.clear_color[2],
                .a = self.clear_color[3],
            },
            .load_op = c.sdl.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.sdl.SDL_GPU_STOREOP_STORE,
        };
    }

    pub fn beginFrame(self: *RenderManager) !void {
        _ = self; // autofix

        // zgui.backend.prepareDrawData(@ptrCast(command_buffer));

        // const padding: f32 = 0.1;
        // const padding_x = @as(f32, @floatFromInt(self.window.getSize().width)) * padding;
        // const padding_y = @as(f32, @floatFromInt(self.window.getSize().height)) * padding;
        // const viewport = c.sdl.SDL_GPUViewport{
        //     .x = padding_x,
        //     .y = padding_y,
        //     .w = @as(f32, @floatFromInt(self.window.getSize().width)) - (padding_x * 2),
        //     .h = @as(f32, @floatFromInt(self.window.getSize().height)) - (padding_y * 2),
        //     .max_depth = 1,
        //     .min_depth = 0.1,
        // };
        // c.sdl.SDL_SetGPUViewport(self.render_pass, &viewport);
    }

    pub fn submitFrame(self: *RenderManager) !void {
        var cit = self.command_buffers.iterator();
        while (cit.next()) |cmd_entry| {
            switch (cmd_entry.value_ptr.*.submition) {
                .submitted => |s| {
                    if (!s) {
                        if (!cmd_entry.value_ptr.*.sumbit()) {
                            std.log.err("Failed cmd_buf.Submit {s} ", .{c.sdl.SDL_GetError()});
                            return error.CommandBufferSubmit;
                        }
                    }
                },
                .rogue => {},
            }
            try self.resetCommandBuffer(cmd_entry.key_ptr.*);
        }
    }
};

const GraphicsPipelineDesc = struct {
    vertex_shader: Shader,
    fragment_shader: Shader,
    vertex_input_state: c.sdl.SDL_GPUVertexInputState,
    cull_mode: c.sdl.SDL_GPUCullMode,
    front_face: c.sdl.SDL_GPUFrontFace,
    primitive_type: c.sdl.SDL_GPUPrimitiveType,
    wireframe: bool,
};

pub fn createGraphicsPipeline(renderer: *RenderManager, desc: GraphicsPipelineDesc) !u32 {
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
        .primitive_type = desc.primitive_type,
        .rasterizer_state = .{
            .cull_mode = desc.cull_mode,
            .front_face = desc.front_face,
            .fill_mode = if (desc.wireframe) c.sdl.SDL_GPU_FILLMODE_LINE else c.sdl.SDL_GPU_FILLMODE_FILL,
        },
    };

    const pipeline = c.sdl.SDL_CreateGPUGraphicsPipeline(renderer.device, &pipeline_info) orelse return error.PipelineCreationFailed;
    const id: u32 = renderer.pipelines.count();
    try renderer.pipelines.put(@intCast(id), pipeline);
    return id;
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
    image_size: Types.Vec2_usize,
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

    const texture_region = c.sdl.SDL_GPUTextureRegion{
        .texture = texture,
        .w = @intCast(image_size[0]),
        .h = @intCast(image_size[1]), // FIXed: was using 'y' property instead of 'h'
        .d = 1,
    };

    c.sdl.SDL_UploadToGPUTexture(copy_pass, &texture_transfer_info, &texture_region, false);
}
