const std = @import("std");

const ecs = @import("ecs");
const zgui = @import("zgui");
const zm = @import("zmath");

const uph_3d = @import("./3d/3d.zig");
const c = @import("imports.zig");
const Types = @import("types.zig");

const Renderer = @This();

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

allocator: std.mem.Allocator,
window: Window,
device: *c.sdl.SDL_GPUDevice,
default_sampler: *c.sdl.SDL_GPUSampler,
command_buffers: std.AutoHashMap(u32, *Cmd),
pipelines: std.AutoHashMap(u32, *c.sdl.SDL_GPUGraphicsPipeline),

clear_color: Types.Vec4_f32,
target_info: c.sdl.SDL_GPUColorTargetInfo = undefined,
swapchain_texture: ?*c.sdl.SDL_GPUTexture = null,

pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, title: [*:0]const u8) !*Renderer {
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

    const renderer = try allocator.create(Renderer);

    const default_color = Types.Vec4_f32{ 0, 0, 0, 1 };

    renderer.* = Renderer{
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

pub fn deinit(self: *Renderer) void {
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

pub fn getAspectRatio(self: *const Renderer) f32 {
    var w: c_int = 0;
    var h: c_int = 0;
    _ = c.sdl.SDL_GetWindowSize(self.window.sdl_window, &w, &h);
    return @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
}

pub fn getPipeline(self: *Renderer, pipeline_id: u32) !*c.sdl.SDL_GPUGraphicsPipeline {
    return self.pipelines.get(pipeline_id) orelse {
        return error.GraphicsPipelineDoesNotExist;
    };
}

pub fn bindGraphicsPipeline(
    self: *Renderer,
    render_pass: ?*c.sdl.SDL_GPURenderPass,
    pipeline_handle: u32,
) !void {
    c.sdl.SDL_BindGPUGraphicsPipeline(render_pass, try self.getPipeline(pipeline_handle));
}

pub fn resetCommandBuffer(self: *Renderer, id: u32) !void {
    const command_buffer = c.sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
        return error.CommandBufferAcquisitionFailed;
    };

    const old = self.command_buffers.fetchRemove(id) orelse {
        return error.CmdNotFound;
    };
    self.allocator.destroy(old.value);

    try self.command_buffers.put(id, try Cmd.init(self.allocator, command_buffer));
}

pub fn createRogueCommand(self: *Renderer) !*Cmd {
    const command_buffer = c.sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
        return error.CommandBufferAcquisitionFailed;
    };

    return try Cmd.init(self.allocator, command_buffer);
}

pub fn submitRogueCommand(self: *Renderer, cmd: *Cmd) !void {
    if (!cmd.sumbit()) {
        std.log.err("Failed cmd_buf.Submit {s} ", .{c.sdl.SDL_GetError()});
        self.allocator.destroy(cmd);
        return error.CommandBufferSubmit;
    }

    self.allocator.destroy(cmd);
}

pub fn createCommand(self: *Renderer) !u32 {
    const command_buffer = c.sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
        return error.CommandBufferAcquisitionFailed;
    };
    const id: u32 = self.command_buffers.count();

    try self.command_buffers.put(id, try Cmd.init(self.allocator, command_buffer));

    return id;
}

pub fn getCommand(self: *Renderer, command_buffer_id: u32) !*Cmd {
    return self.command_buffers.get(command_buffer_id) orelse {
        return error.CommandBufferDoesNotExist;
    };
}

pub fn submitCommand(self: *Renderer, cmd_handle: u32) !void {
    const cmd = try self.getCommand(cmd_handle);

    if (!cmd.sumbit()) {
        std.log.err("Failed cmd_buf.Submit {s} ", .{c.sdl.SDL_GetError()});
        return error.CommandBufferSubmit;
    }

    try self.resetCommandBuffer(cmd_handle);
}

pub fn createTransferBuffer(
    self: *Renderer,
    usage: c.sdl.SDL_GPUTransferBufferUsage,
    size: u32,
) !*c.sdl.SDL_GPUTransferBuffer {
    return c.sdl.SDL_CreateGPUTransferBuffer(self.device, &.{
        .usage = usage,
        .size = size,
    }) orelse return error.TransferBufferCreationFailed;
}

pub fn clear(self: *Renderer) !void {
    const cmd = try self.createRogueCommand();
    if (c.sdl.SDL_WaitAndAcquireGPUSwapchainTexture(cmd.command_buffer, self.*.window.sdl_window, &self.swapchain_texture, null, null) == false) {
        return error.SwapchainAcquisitionFailed;
    }
    if (self.swapchain_texture == null) {
        return error.NullSwapchainTexture;
    }

    self.target_info = c.sdl.SDL_GPUColorTargetInfo{
        .texture = self.swapchain_texture,
        .clear_color = .{
            .r = self.clear_color[0],
            .g = self.clear_color[1],
            .b = self.clear_color[2],
            .a = self.clear_color[3],
        },
        .load_op = c.sdl.SDL_GPU_LOADOP_CLEAR,
        .store_op = c.sdl.SDL_GPU_STOREOP_STORE,
    };
    try self.submitRogueCommand(cmd);
}

pub fn setClearColor(self: *Renderer, color: Types.Vec4_f32) void {
    self.clear_color = color;
}

pub fn beginFrame(self: *Renderer) !void {
    _ = &self; // autofix
    try self.clear();
}

pub fn submitFrame(self: *Renderer) !void {
    var cit = self.command_buffers.iterator();
    while (cit.next()) |cmd_entry| {
        switch (cmd_entry.value_ptr.*.submition) {
            .submitted => |s| {
                if (s == false) {
                    std.log.debug("sumbit cmd id :{d}", .{cmd_entry.key_ptr.*});
                    if (!cmd_entry.value_ptr.*.sumbit()) {
                        std.log.err("Failed cmd_buf.Submit {s} ", .{c.sdl.SDL_GetError()});
                        return error.CommandBufferSubmit;
                    }
                }
                try self.resetCommandBuffer(cmd_entry.key_ptr.*);
            },
            .rogue => {},
        }
    }
}
