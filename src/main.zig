const std = @import("std");

const za = @import("zalgebra");
/// END : IMPORTS -------------------------------------------------------------------------------------------------------------
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;

const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_gpu.h");
    @cInclude("SDL3/SDL_pixels.h");
    @cInclude("SDL3/SDL_video.h");
});
const Vec4_u8 = za.GenericVector(4, u8);

const Vertex = struct {
    position: za.Vec3,
    color: Vec4_u8,
};

const UniformBufferObejct = struct {
    mvp: Mat4,
};
/// END: Types -------------------------------------------------------------------------------------------------------------
const WINDOW_WIDTH = 1200;
const WINDOW_HEIGHT = 800;

fn printEvent(event: sdl.SDL_Event) void {
    switch (event.type) {
        sdl.SDL_EVENT_QUIT => std.log.info("Event: SDL_EVENT_QUIT", .{}),
        sdl.SDL_EVENT_KEY_DOWN => {
            const key_name = sdl.SDL_GetKeyName(event.key.key);
            std.log.info("Event: SDL_EVENT_KEY_DOWN - Key: {s} (code: {d})", .{ key_name, event.key.key });
        },
        sdl.SDL_EVENT_KEY_UP => {
            const key_name = sdl.SDL_GetKeyName(event.key.key);
            std.log.info("Event: SDL_EVENT_KEY_UP - Key: {s} (code: {d})", .{ key_name, event.key.key });
        },
        sdl.SDL_EVENT_MOUSE_MOTION => std.log.info("Event: SDL_EVENT_MOUSEMOTION - X: {d}, Y: {d}", .{ event.motion.x, event.motion.y }),
        sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => std.log.info("Event: SDL_EVENT_MOUSEBUTTONDOWN - Button: {d}", .{event.button.button}),
        sdl.SDL_EVENT_MOUSE_BUTTON_UP => std.log.info("Event: SDL_EVENT_MOUSEBUTTONUP - Button: {d}", .{event.button.button}),
        sdl.SDL_EVENT_WINDOW_SHOWN => std.log.info("Event: Window {s}", .{"SHOWN"}),
        sdl.SDL_EVENT_WINDOW_HIDDEN => std.log.info("Event: Window {s}", .{"HIDDEN"}),
        sdl.SDL_EVENT_WINDOW_EXPOSED => std.log.info("Event: Window {s}", .{"EXPOSED"}),
        sdl.SDL_EVENT_WINDOW_MOVED => std.log.info("Event: Window {s}", .{"MOVED"}),
        sdl.SDL_EVENT_WINDOW_RESIZED => std.log.info("Event: Window {s}", .{"RESIZED"}),
        sdl.SDL_EVENT_WINDOW_MINIMIZED => std.log.info("Event: Window {s}", .{"MINIMIZED"}),
        sdl.SDL_EVENT_WINDOW_MAXIMIZED => std.log.info("Event: Window {s}", .{"MAXIMIZED"}),
        sdl.SDL_EVENT_WINDOW_RESTORED => std.log.info("Event: Window {s}", .{"RESTORED"}),
        sdl.SDL_EVENT_WINDOW_MOUSE_ENTER => std.log.info("Event: Window {s}", .{"ENTER"}),
        sdl.SDL_EVENT_WINDOW_MOUSE_LEAVE => std.log.info("Event: Window {s}", .{"LEAVE"}),
        sdl.SDL_EVENT_WINDOW_FOCUS_GAINED => std.log.info("Event: Window {s}", .{"FOCUS_GAINED"}),
        sdl.SDL_EVENT_WINDOW_FOCUS_LOST => std.log.info("Event: Window {s}", .{"FOCUS_LOST"}),
        sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED => std.log.info("Event: Window {s}", .{"CLOSE REQUESTED"}),
        sdl.SDL_EVENT_WINDOW_HIT_TEST => std.log.info("Event: Window {s}", .{"HIT_TEST"}),
        else => std.log.info("Event: Unknown event type {d}", .{event.type}),
    }
}

fn handleEvent(event: sdl.SDL_Event, quit: *bool) void {
    printEvent(event);
    switch (event.type) {
        sdl.SDL_EVENT_QUIT => {
            quit.* = true;
        },
        sdl.SDL_EVENT_KEY_DOWN => {
            switch (event.key.key) {
                sdl.SDLK_Q => {
                    quit.* = true;
                },
                sdl.SDLK_W => {},
                sdl.SDLK_S => {},
                sdl.SDLK_D => {},
                else => {},
            }
        },
        else => {},
    }
}

fn loadShader(
    device: *sdl.SDL_GPUDevice,
    filename: [*c]const u8,
    stage: sdl.SDL_GPUShaderStage,
    sampler_count: u32,
    uniform_buffer_count: u32,
    storage_buffer_count: u32,
    storage_texture_count: u32,
) ?*sdl.SDL_GPUShader {
    if (sdl.SDL_GetPathInfo(filename, null) == false) {
        std.log.err("File ({s}) does not exist.\n", .{filename});
        return null;
    }

    var entrypoint: [*c]const u8 = undefined;
    const backend_formats = sdl.SDL_GetGPUShaderFormats(device);
    var format: sdl.SDL_GPUShaderFormat = sdl.SDL_GPU_SHADERFORMAT_INVALID;
    if (backend_formats & sdl.SDL_GPU_SHADERFORMAT_SPIRV != 0) {
        format = sdl.SDL_GPU_SHADERFORMAT_SPIRV;
        entrypoint = "main";
    }

    var code_size: usize = undefined;
    const code: [*c]const u8 = @ptrCast(sdl.SDL_LoadFile(filename, &code_size).?);

    defer sdl.SDL_free(@constCast(code));

    const shader_info = sdl.SDL_GPUShaderCreateInfo{
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

    const shader = sdl.SDL_CreateGPUShader(device, &shader_info);
    if (shader == null) {
        std.log.err("ERROR: SDL_CreateGPUShader failed: {s}\n", .{sdl.SDL_GetError()});
        return null;
    }

    return shader;
}

fn createBuffer(device: *sdl.SDL_GPUDevice, usage: sdl.SDL_GPUBufferUsageFlags, size: u32) ?*sdl.SDL_GPUBuffer {
    const buffer_create_info = sdl.SDL_GPUBufferCreateInfo{
        .usage = usage,
        .size = size,
    };
    return sdl.SDL_CreateGPUBuffer(device, &buffer_create_info);
}

fn uploadToBuffer(device: *sdl.SDL_GPUDevice, buffer: *sdl.SDL_GPUBuffer, comptime T: type, data: []const T) !void {
    const total_size: u32 = @intCast(@sizeOf(T) * data.len);

    const transfer_buffer_create_info = sdl.SDL_GPUTransferBufferCreateInfo{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = total_size,
    };

    const transfer_buffer = sdl.SDL_CreateGPUTransferBuffer(device, &transfer_buffer_create_info);
    defer sdl.SDL_ReleaseGPUTransferBuffer(device, transfer_buffer);

    // Map the buffer memory
    const transfer_data = sdl.SDL_MapGPUTransferBuffer(device, transfer_buffer, false) orelse {
        std.log.err("SDL_MapGPUTransferBuffer Failed (upload_cmdbuf)", .{});
        return error.MapFailed;
    };

    // Cast the pointer to the correct type and copy the data
    const typed_ptr = @as([*]T, @alignCast(@ptrCast(transfer_data)));
    @memcpy(typed_ptr[0..data.len], data);

    sdl.SDL_UnmapGPUTransferBuffer(device, transfer_buffer);

    const upload_cmdbuf = sdl.SDL_AcquireGPUCommandBuffer(device);
    const copy_pass = sdl.SDL_BeginGPUCopyPass(upload_cmdbuf);

    const transfer_buffer_location = sdl.SDL_GPUTransferBufferLocation{
        .transfer_buffer = transfer_buffer,
        .offset = 0,
    };

    const buffer_region = sdl.SDL_GPUBufferRegion{
        .buffer = buffer,
        .offset = 0,
        .size = total_size,
    };

    sdl.SDL_UploadToGPUBuffer(copy_pass, &transfer_buffer_location, &buffer_region, false);
    sdl.SDL_EndGPUCopyPass(copy_pass);

    if (sdl.SDL_SubmitGPUCommandBuffer(upload_cmdbuf) == false) {
        std.log.err("SDL_SubmitGPUCommandBuffer Failed (upload_cmdbuf)", .{});
        return error.SubmitFailed;
    }
}

pub fn main() !u8 {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        std.log.err("ERROR: SDL_Init failed: {s}\n", .{sdl.SDL_GetError()});
        return 1;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow("Pressure Simulation", WINDOW_WIDTH, WINDOW_HEIGHT, sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE);
    if (window == null) {
        std.log.err("ERROR: SDL_CreateWindow failed: {s}\n", .{sdl.SDL_GetError()});
        return 1;
    }
    defer sdl.SDL_DestroyWindow(window);

    const device = sdl.SDL_CreateGPUDevice(sdl.SDL_GPU_SHADERFORMAT_SPIRV, true, null) orelse {
        std.log.err("ERROR: SDL_CreateGPUDevice failed: {s}\n", .{sdl.SDL_GetError()});
        return 1;
    };
    defer sdl.SDL_DestroyGPUDevice(device);

    std.log.debug("OK: Created device with driver '{s}'\n", .{sdl.SDL_GetGPUDeviceDriver(device)});

    if (sdl.SDL_ClaimWindowForGPUDevice(device, window) == false) {
        std.log.err("ERROR: SDL_ClaimWindowForGPUDevice failed: {s}\n", .{sdl.SDL_GetError()});
        return 1;
    }
    defer sdl.SDL_ReleaseWindowFromGPUDevice(device, window);

    // Load shaders + create fill/line pipeline
    const shader_vert = loadShader(device, "shaders/compiled/PositionColor.vert.spv", sdl.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1, 0, 0);
    if (shader_vert == null) {
        std.log.err("ERROR: load_shader failed\n", .{});
        return 1;
    }
    defer sdl.SDL_ReleaseGPUShader(device, shader_vert);

    const shader_frag = loadShader(device, "shaders/compiled/SolidColor.frag.spv", sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0, 0, 0);
    if (shader_frag == null) {
        std.log.err("ERROR: load_shader failed\n", .{});
        return 1;
    }
    defer sdl.SDL_ReleaseGPUShader(device, shader_frag);

    const vertices = [_]Vertex{
        .{ // tl
            .position = za.Vec3.new(-0.5, 0.5, 0),
            .color = Vec4_u8.new(255, 126, 0, 255),
        },
        .{ // tr
            .position = za.Vec3.new(0.5, 0.5, 0),
            .color = Vec4_u8.new(0, 126, 255, 255),
        },
        .{ // br
            .position = za.Vec3.new(0.5, -0.5, 0),
            .color = Vec4_u8.new(0, 255, 126, 255),
        },
        .{ //bl
            .position = za.Vec3.new(-0.5, -0.5, 0),
            .color = Vec4_u8.new(126, 0, 255, 255),
        },
    };

    const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };

    const vertex_buffer: *sdl.SDL_GPUBuffer = createBuffer(device, sdl.SDL_GPU_BUFFERUSAGE_VERTEX, @sizeOf(Vertex) * vertices.len) orelse {
        std.log.err("Failed to create Vertex buffer\n", .{});
        return 1;
    };
    defer sdl.SDL_ReleaseGPUBuffer(device, vertex_buffer);

    const index_buffer = createBuffer(device, sdl.SDL_GPU_BUFFERUSAGE_VERTEX, @sizeOf(u16) * indices.len) orelse {
        std.log.err("Failed to create Index buffer\n", .{});
        return 1;
    };
    defer sdl.SDL_ReleaseGPUBuffer(device, index_buffer);

    uploadToBuffer(device, vertex_buffer, Vertex, &vertices) catch |err| {
        std.log.err("Failed to upload vertices: {}", .{err});
    };

    uploadToBuffer(device, index_buffer, u16, &indices) catch |err| {
        std.log.err("Failed to upload indices: {}", .{err});
    };

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
            .offset = 0,
        },
        .{
            .location = 1,
            .buffer_slot = 0,
            .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM,
            .offset = @sizeOf(Vec3),
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
            .num_vertex_attributes = 2,
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
        std.log.err("ERROR: SDL_CreateGPUGraphicsPipeline failed: {s}\n", .{sdl.SDL_GetError()});
        return 1;
    };

    defer sdl.SDL_ReleaseGPUGraphicsPipeline(device, pipeline);

    _ = sdl.SDL_SetWindowPosition(window, sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED);

    var w: c_int = @intCast(WINDOW_WIDTH);
    var h: c_int = @intCast(WINDOW_HEIGHT);
    _ = sdl.SDL_GetWindowSize(window, &w, &h);
    const aspect: f32 = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(w));

    const ROTATION_SPEED = 90.0;
    var rotation: f32 = 0.0;

    const projetction_mat: Mat4 = za.perspective(70.0, aspect, (1 / 1000), 100000);
    var quit = false;

    var last_ticks = sdl.SDL_GetTicks();
    while (!quit) {
        const new_ticks = sdl.SDL_GetTicks();
        const delta_time = @as(f32, @floatFromInt(new_ticks - last_ticks)) / 1000;
        last_ticks = new_ticks;
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event)) {
            handleEvent(event, &quit);
        }

        const cmdbuf = sdl.SDL_AcquireGPUCommandBuffer(device);
        if (cmdbuf == null) {
            std.log.err("ERROR: SDL_AcquireGPUCommandBuffer failed: {s}\n", .{sdl.SDL_GetError()});
            break;
        }

        var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
        if (sdl.SDL_WaitAndAcquireGPUSwapchainTexture(cmdbuf, window, &swapchain_texture, null, null) == false) {
            std.log.err("ERROR: SDL_WaitAndAcquireGPUSwapchainTexture failed: {s}\n", .{sdl.SDL_GetError()});
            break;
        }

        if (swapchain_texture == null) {
            std.log.err("ERROR: swapchain_texture is NULL\n", .{});
            _ = sdl.SDL_SubmitGPUCommandBuffer(cmdbuf);
            break;
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

        const render_pass = sdl.SDL_BeginGPURenderPass(cmdbuf, &color_target_info, 1, null);
        sdl.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);

        const vert_buffer_binding = sdl.SDL_GPUBufferBinding{
            .buffer = vertex_buffer,
            .offset = 0,
        };
        sdl.SDL_BindGPUVertexBuffers(render_pass, 0, &vert_buffer_binding, 1);
        sdl.SDL_BindGPUIndexBuffer(render_pass, &.{ .buffer = index_buffer, .offset = 0 }, sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT);

        rotation += ROTATION_SPEED * delta_time;
        const model_matrix = Mat4.mul(
            Mat4.fromTranslate(Vec3.new(0, 0, -5)),
            Mat4.fromRotation(rotation, Vec3.new(1, 1, 1)),
        );

        const ubo: UniformBufferObejct = .{
            .mvp = Mat4.mul(projetction_mat, model_matrix),
        };
        sdl.SDL_PushGPUVertexUniformData(cmdbuf, 0, &ubo, @sizeOf(UniformBufferObejct));
        sdl.SDL_DrawGPUIndexedPrimitives(render_pass, @intCast(indices.len), 1, 0, 0, 0);
        sdl.SDL_EndGPURenderPass(render_pass);

        _ = sdl.SDL_SubmitGPUCommandBuffer(cmdbuf);
    }

    return 0;
}
