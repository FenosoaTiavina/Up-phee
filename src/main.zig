const std = @import("std");

const zgui = @import("zgui");
const zm = @import("zmath");

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
/// END : IMPORTS -------------------------------------------------------------------------------------------------------------
const Vec2_f32 = @Vector(2, f32);
const Vec2_usize = @Vector(2, usize);

const Vec3_f32 = @Vector(3, f32);

const Vec4_u8 = @Vector(4, u8);
const Vec4_f32 = @Vector(4, f32);
const Mat4_f32 = [4]Vec4_f32;

const Vertex = struct {
    position: Vec3_f32,
    color: Vec4_f32,
    uv: Vec2_f32,
};

const UniformBufferObejct = struct {
    model: Mat4_f32,
    view: Mat4_f32,
    projection: Mat4_f32,
};

const Camera = struct {
    position: Vec3_f32 = Vec3_f32.zero(),
    look_at: Vec3_f32 = Vec3_f32.zero(),
    view: Mat4_f32 = Mat4_f32.zero(),

    fn get_position(self: *Camera) Vec3_f32 {
        return self.position;
    }
    fn update_position(self: *Camera, p_new_position: Vec3_f32) Vec3_f32 {
        self.*.position = p_new_position;
        return self.position;
    }

    fn view_matrix(self: *Camera) Mat4_f32 {
        return zm.lookAt(self.position, self.look_at, Vec3_f32.up());
    }
};

const World = struct {};

const Window = struct {
    sdl_window: *sdl.SDL_Window,
    window_title: [*c]u8,
    window_dimension: Vec2_usize,

    fn getAspectRatio(self: *Window) f32 {
        var w: c_int = @intCast(WINDOW_WIDTH);
        var h: c_int = @intCast(WINDOW_HEIGHT);
        _ = sdl.SDL_GetWindowSize(self.window, &w, &h);
        return @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
    }

    fn setup_window(self: *Window, window_title: []const u8, window_dimenseion: Vec2_usize) void {
        self.*.window_dimension = window_title;
        self.*.window_dimension = window_dimenseion;
    }

    fn init_sdl_window(self: *Window) !void {
        if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
            std.log.err("ERROR: SDL_Init failed: {s}\n", .{sdl.SDL_GetError()});
            return error.WindowInit;
        }
        self.sdl_window = sdl.SDL_CreateWindow(self.window_title, self.window_dimension[0], self.window_dimension[1], sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE) orelse {
            std.log.err("ERROR: SDL_CreateWindow failed: {s}\n", .{sdl.SDL_GetError()});
            return error.windowcreation;
        };
    }

    fn get_sdl_window(self: *Window) *sdl.SDL_Window {
        return self.sdl_window;
    }

    fn destroy_and_quit(self: *Window) void {
        sdl.SDL_DestroyWindow(self.sdl_window);
        sdl.SDL_Quit();
    }
};

const Renderer = struct {
    g_window: *Window,
    gpu_device: *sdl.SDL_GPUDevice,

    fn prepareFrame() !void {}
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
        sdl.SDL_EVENT_MOUSE_WHEEL => std.log.info("Event: SDL_EVENT_MOUSEMOTION - X: {d}, Y: {d}", .{ event.motion.x, event.motion.y }),
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

fn getAspectRatio(window: *sdl.SDL_Window) f32 {
    var w: c_int = @intCast(WINDOW_WIDTH);
    var h: c_int = @intCast(WINDOW_HEIGHT);
    _ = sdl.SDL_GetWindowSize(window, &w, &h);
    return @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
}

fn loadShader(
    device: *sdl.SDL_GPUDevice,
    filename: [*c]const u8,
    stage: sdl.SDL_GPUShaderStage,
    uniform_buffer_count: u32,
    storage_buffer_count: u32,
    storage_texture_count: u32,
    sampler_count: u32,
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

fn uploadToGPU(
    device: *sdl.SDL_GPUDevice,
    copy_pass: *sdl.SDL_GPUCopyPass,
    transfer_buffer: *sdl.SDL_GPUTransferBuffer,
    buffer_offset: u32,
    comptime T: type,
    data: []const T,
    buffer: *sdl.SDL_GPUBuffer,
) !void {
    const total_size: u32 = @intCast(@sizeOf(T) * data.len);

    // Map the buffer memory
    const transfer_data = sdl.SDL_MapGPUTransferBuffer(device, transfer_buffer, false) orelse {
        std.log.err("SDL_MapGPUTransferBuffer Failed (upload_cmdbuf)", .{});
        return error.MapFailed;
    };

    // Cast the pointer to bytes and copy the data at the specified offset
    const transfer_bytes = @as([*]u8, @ptrCast(transfer_data));
    @memcpy(transfer_bytes[buffer_offset .. buffer_offset + total_size], @as([*]const u8, @ptrCast(data.ptr)));

    sdl.SDL_UnmapGPUTransferBuffer(device, transfer_buffer);

    const transfer_buffer_location = sdl.SDL_GPUTransferBufferLocation{
        .transfer_buffer = transfer_buffer,
        .offset = buffer_offset,
    };

    const buffer_region = sdl.SDL_GPUBufferRegion{
        .buffer = buffer,
        .offset = 0,
        .size = total_size,
    };

    sdl.SDL_UploadToGPUBuffer(copy_pass, &transfer_buffer_location, &buffer_region, false);
}

fn uploadTextureGPU(
    device: *sdl.SDL_GPUDevice,
    copy_pass: *sdl.SDL_GPUCopyPass,
    transfer_buffer: *sdl.SDL_GPUTransferBuffer,
    texture: *sdl.SDL_GPUTexture,
    buffer_offset: u32,
    comptime T: type,
    images_data: *[]u8,
    image_size: Vec2_usize,
    image_byte_size: usize,
) !void {
    // Map the buffer memory
    const transfer_data = sdl.SDL_MapGPUTransferBuffer(device, transfer_buffer, false) orelse {
        std.log.err("SDL_MapGPUTransferBuffer Failed (upload_cmdbuf)", .{});
        return error.MapFailed;
    };

    // Cast the pointer to bytes and copy the data at the specified offset
    const transfer_bytes: [*]T = @ptrCast(transfer_data);
    @memcpy(transfer_bytes[buffer_offset .. buffer_offset + image_byte_size], images_data.ptr);
    sdl.SDL_UnmapGPUTransferBuffer(device, transfer_buffer);

    const texture_transfer_info = sdl.struct_SDL_GPUTextureTransferInfo{
        .transfer_buffer = transfer_buffer,
        .offset = buffer_offset,
    };

    // FIX: correct width and height parameters
    const texture_region = sdl.SDL_GPUTextureRegion{
        .texture = texture,
        .w = @intCast(image_size[0]),
        .h = @intCast(image_size[1]), // FIXed: was using 'y' property instead of 'h'
        .d = 1,
    };

    sdl.SDL_UploadToGPUTexture(copy_pass, &texture_transfer_info, &texture_region, false);
}

pub fn main() !u8 {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        std.log.err("ERROR: SDL_Init failed: {s}\n", .{sdl.SDL_GetError()});
        return 1;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow("Pressure Simulation", WINDOW_WIDTH, WINDOW_HEIGHT, sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE) orelse {
        std.log.err("ERROR: SDL_CreateWindow failed: {s}\n", .{sdl.SDL_GetError()});
        return 1;
    };
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

    _ = sdl.SDL_SetGPUSwapchainParameters(device, window, sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, sdl.SDL_GPU_PRESENTMODE_MAILBOX);

    // Load shaders + create fill/line pipeline
    // FIX: Increase sampler count for vertex shader to 0 and for fragment shader to 1
    const shader_vert = loadShader(device, "shaders/compiled/PositionColor.vert.spv", sdl.SDL_GPU_SHADERSTAGE_VERTEX, 1, 0, 0, 0);
    if (shader_vert == null) {
        std.log.err("ERROR: load_shader failed\n", .{});
        return 1;
    }
    defer sdl.SDL_ReleaseGPUShader(device, shader_vert);

    const shader_frag = loadShader(device, "shaders/compiled/SolidColor.frag.spv", sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0, 0, 1);
    if (shader_frag == null) {
        std.log.err("ERROR: load_shader failed\n", .{});
        return 1;
    }
    defer sdl.SDL_ReleaseGPUShader(device, shader_frag);

    var texture_size = Vec2_usize{ 0, 0 };
    var pixels: []u8 = undefined;
    var image_data: [*c]u8 = stb.stbi_load(
        "assets/kenney_prototypeTextures/PNG/Purple/texture_10.png",
        @ptrCast(&texture_size[0]),
        @ptrCast(&texture_size[1]),
        null,
        4,
    );

    // FIX: Calculate correct byte size
    const texture_byte_size: u32 = @intCast(texture_size[0] * texture_size[1] * 4);
    if (image_data != null) {
        pixels = image_data[0..@intCast(texture_size[0] * texture_size[1] * 4)];
        std.log.debug("images {d}x{d}: {d}", .{
            texture_size[0],
            texture_size[1],
            texture_byte_size,
        });
    } else {
        std.debug.print("failed to load \"{s}\": {s}\n", .{ "assets/kenney_prototypeTextures/PNG/Purple/texture_10.png", stb.stbi_failure_reason() });
        return 1;
    }
    defer stb.stbi_image_free(image_data); // FIX: Free the image data after use

    // FIX: Correct texture width and height
    const texture = sdl.SDL_CreateGPUTexture(device, &sdl.SDL_GPUTextureCreateInfo{
        .type = sdl.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .width = @intCast(texture_size[0]), // FIXed: was switched
        .height = @intCast(texture_size[1]), // FIXed: was switched
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
    }) orelse {
        std.log.err("SDL_CreateGPUTexture failed {s}", .{sdl.SDL_GetError()});
        return 1;
    };
    defer sdl.SDL_ReleaseGPUTexture(device, texture);

    // FIX: Corrected UV coordinates for the vertices
    const vertices = [_]Vertex{
        .{ // top-left
            .position = Vec3_f32{ -0.5, 0.5, 0 },
            .color = Vec4_f32{ 1.0, 1.0, 1.0, 1.0 },
            .uv = Vec2_f32{ 0.0, 0.0 },
        },
        .{ // top-right
            .position = Vec3_f32{ 0.5, 0.5, 0 },
            .color = Vec4_f32{ 1.0, 1.0, 1.0, 1.0 },
            .uv = Vec2_f32{ 1.0, 0.0 },
        },
        .{ // bottom-right
            .position = Vec3_f32{ 0.5, -0.5, 0 },
            .color = Vec4_f32{ 1.0, 1.0, 1.0, 1.0 },
            .uv = Vec2_f32{ 1.0, 1.0 },
        },
        .{ // bottom-left
            .position = Vec3_f32{ -0.5, -0.5, 0 },
            .color = Vec4_f32{ 1.0, 1.0, 1.0, 1.0 },
            .uv = Vec2_f32{ 0.0, 1.0 },
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

    const vertices_byte_size = @sizeOf(Vertex) * vertices.len;
    const indices_byte_size = @sizeOf(u16) * indices.len;
    const total_byte_size = vertices_byte_size + indices_byte_size;

    const transfer_buffer = sdl.SDL_CreateGPUTransferBuffer(device, &sdl.SDL_GPUTransferBufferCreateInfo{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = total_byte_size,
    }) orelse {
        std.log.err("ERROR: SDL_CreateGPUTransferBuffer failed: {s}\n", .{sdl.SDL_GetError()});
        return 1;
    };
    defer sdl.SDL_ReleaseGPUTransferBuffer(device, transfer_buffer);

    const texture_transfer_buffer = sdl.SDL_CreateGPUTransferBuffer(device, &sdl.SDL_GPUTransferBufferCreateInfo{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = texture_byte_size,
    }) orelse {
        std.log.err("ERROR: SDL_CreateGPUTransferBuffer failed: {s}\n", .{sdl.SDL_GetError()});
        return 1;
    };
    defer sdl.SDL_ReleaseGPUTransferBuffer(device, texture_transfer_buffer);

    const upload_cmdbuf = sdl.SDL_AcquireGPUCommandBuffer(device) orelse {
        std.log.err("ERROR: SDL_AcquireGPUCommandBuffer failed: {s}\n", .{sdl.SDL_GetError()});
        return 1;
    };

    // Begin copy pass for uploading both buffers
    const copy_pass = sdl.SDL_BeginGPUCopyPass(upload_cmdbuf) orelse {
        std.log.err("ERROR: SDL_BeginGPUCopyPass failed: {s}\n", .{sdl.SDL_GetError()});
        return 1;
    };

    // Upload vertex data (at offset 0)
    try uploadToGPU(device, copy_pass, transfer_buffer, 0, Vertex, &vertices, vertex_buffer);

    // Upload index data (at offset after vertex data)
    try uploadToGPU(device, copy_pass, transfer_buffer, vertices_byte_size, u16, &indices, index_buffer);
    try uploadTextureGPU(device, copy_pass, texture_transfer_buffer, texture, 0, u8, &pixels, texture_size, texture_byte_size);

    // End the copy pass and submit the command buffer
    sdl.SDL_EndGPUCopyPass(copy_pass);

    _ = sdl.SDL_SubmitGPUCommandBuffer(upload_cmdbuf);

    // Create a sampler for the texture
    const sampler = sdl.SDL_CreateGPUSampler(device, &sdl.SDL_GPUSamplerCreateInfo{
        .min_filter = sdl.SDL_GPU_FILTER_LINEAR,
        .mag_filter = sdl.SDL_GPU_FILTER_LINEAR,
        .address_mode_u = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    });
    defer sdl.SDL_ReleaseGPUSampler(device, sampler);

    const vertex_buffer_desc = sdl.SDL_GPUVertexBufferDescription{
        .slot = 0,
        .pitch = @sizeOf(Vertex),
        .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
        .instance_step_rate = 0,
    };

    // FIX: Correct the vertex attribute layout
    const vertex_attributes = [_]sdl.SDL_GPUVertexAttribute{
        .{ // Position
            .location = 0,
            .buffer_slot = 0,
            .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
            .offset = @offsetOf(Vertex, "position"),
        },
        .{ // Color
            .location = 1,
            .buffer_slot = 0,
            .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
            .offset = @offsetOf(Vertex, "color"),
        },
        .{ // UV
            .location = 2,
            .buffer_slot = 0,
            .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
            .offset = @offsetOf(Vertex, "uv"),
        },
    };

    const color_target_descriptions = sdl.SDL_GPUColorTargetDescription{
        .format = sdl.SDL_GetGPUSwapchainTextureFormat(device, window),
    };

    // FIX: Use correct number of vertex attributes
    const pipeline_info = sdl.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = shader_vert,
        .fragment_shader = shader_frag,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &vertex_buffer_desc,
            .num_vertex_buffers = 1,
            .vertex_attributes = &vertex_attributes,
            .num_vertex_attributes = 3, // FIXed: was 2, needs to be 3 for position, color, uv
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

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();
    zgui.init(gpa);
    defer zgui.deinit();

    // Setup Dear ImGui style
    zgui.getStyle().setColorsDark();
    //zgui.getStyle().setColorsLight();

    // Setup Platform/Renderer backends
    zgui.backend.init(window, .{
        .device = device,
        .color_target_format = sdl.SDL_GetGPUSwapchainTextureFormat(device, window),
        .msaa_samples = sdl.SDL_GPU_SAMPLECOUNT_1,
    });
    defer zgui.backend.deinit();

    var aspect: f32 = getAspectRatio(window);

    const ROTATION_SPEED = 90.0;
    const MOVE_SPEED = 10;
    _ = MOVE_SPEED; // autofix
    const LOOK_SPEED = 1;
    _ = LOOK_SPEED; // autofix

    var rotation: f32 = 0.0;

    var projection_mat: Mat4_f32 = zm.perspectiveFovRh(70.0, aspect, 0.0001, 10000.0); // FIX: Use more reasonable near/far planes
    const camera_position = Vec4_f32{ 0.0, 0.0, -5.0, 1.0 };
    const camera_target = Vec4_f32{ 0, 0, 0, 1.0 };
    const camera_front = Vec4_f32{ 0.0, 0.0, -1.0, 1.0 };
    _ = camera_front; // autofix

    var mouse_grabbed: bool = false;
    var last_ticks = sdl.SDL_GetTicks();
    var quit = false;
    var mouse_coords = Vec2_f32{ 0, 0 };
    main_loop: while (!quit) {
        const new_ticks = sdl.SDL_GetTicks();
        const delta_time = @as(f32, @floatFromInt(new_ticks - last_ticks)) / 1000;
        last_ticks = new_ticks;
        var event: sdl.SDL_Event = undefined;

        while (sdl.SDL_PollEvent(&event)) {
            // printEvent(event);
            _ = zgui.backend.processEvent(&event);

            switch (event.type) {
                sdl.SDL_EVENT_QUIT => {
                    quit = true;
                },
                sdl.SDL_EVENT_KEY_DOWN => {
                    switch (event.key.key) {
                        sdl.SDLK_Q => {
                            quit = true;
                        },
                        sdl.SDLK_G => {
                            mouse_grabbed = !mouse_grabbed;
                            _ = sdl.SDL_SetWindowMouseGrab(window, mouse_grabbed);
                            _ = sdl.SDL_SetWindowRelativeMouseMode(window, mouse_grabbed);
                        },
                        sdl.SDLK_W => {},
                        sdl.SDLK_S => {},
                        sdl.SDLK_A => {},
                        sdl.SDLK_D => {},

                        else => {},
                    }
                },

                sdl.SDL_EVENT_MOUSE_MOTION => {
                    const last_mouse_coords = mouse_coords;
                    mouse_coords = Vec2_f32{ event.motion.x, event.motion.y };
                    if (sdl.SDL_GetWindowMouseGrab(window)) {
                        if (mouse_coords[0] > last_mouse_coords[0]) {} else if (mouse_coords[0] < last_mouse_coords[0]) {}
                        if (mouse_coords[1] > last_mouse_coords[1]) {} else if (mouse_coords[1] < last_mouse_coords[1]) {}
                    }
                },

                sdl.SDL_EVENT_WINDOW_RESIZED => {
                    aspect = getAspectRatio(window);
                    projection_mat = zm.perspectiveFovRh(70.0, aspect, 0.0001, 10000.0); // FIX: Use more reasonable near/far planes

                },

                else => {},
            }
        }

        var fb_width: c_int = 0;
        var fb_height: c_int = 0;
        if (!sdl.SDL_GetWindowSize(window, &fb_width, &fb_height)) {
            std.log.err("SDL_GetWindowSizeInPixels failed: {s}\n", .{sdl.SDL_GetError()});
            return 1;
        }

        const fb_scale = sdl.SDL_GetWindowDisplayScale(window);

        zgui.backend.newFrame(@intCast(fb_width), @intCast(fb_height), fb_scale);

        // Show a simple window
        zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .first_use_ever });
        if (zgui.begin("info", .{})) {
            zgui.text("camera position :{any},{any},{any}", .{
                camera_position[0],
                camera_position[1],
                camera_position[2],
            });
        }
        zgui.end();

        // The SDL3+GPU backend requires calling zgui.backend.render() before rendering ImGui
        zgui.backend.render();

        const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(device);
        if (command_buffer == null) {
            std.log.err("ERROR: SDL_AcquireGPUCommandBuffer failed: {s}\n", .{sdl.SDL_GetError()});
            break;
        }

        var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
        if (sdl.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, window, &swapchain_texture, null, null) == false) {
            std.log.err("ERROR: SDL_WaitAndAcquireGPUSwapchainTexture failed: {s}\n", .{sdl.SDL_GetError()});
            break :main_loop;
        }

        if (swapchain_texture == null) {
            std.log.err("ERROR: swapchain_texture is NULL\n", .{});
            _ = sdl.SDL_SubmitGPUCommandBuffer(command_buffer);
            break :main_loop;
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

        zgui.backend.prepareDrawData(@ptrCast(command_buffer));

        const render_pass = sdl.SDL_BeginGPURenderPass(command_buffer, &color_target_info, 1, null) orelse {
            std.log.err("ERROR: SDL_BeginGPURenderPass failed: {s}\n", .{sdl.SDL_GetError()});
            return 1;
        };
        sdl.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);

        const vert_buffer_binding = sdl.SDL_GPUBufferBinding{
            .buffer = vertex_buffer,
            .offset = 0,
        };
        sdl.SDL_BindGPUVertexBuffers(render_pass, 0, &vert_buffer_binding, 1);
        sdl.SDL_BindGPUIndexBuffer(render_pass, &.{ .buffer = index_buffer, .offset = 0 }, sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT);

        rotation += ROTATION_SPEED * delta_time;
        // Create a model matrix with rotation for better visualization
        const model_mat = zm.translationV(Vec4_f32{ 0, 0, 0, 0 });
        const view = zm.lookAtRh(camera_position, camera_target, Vec4_f32{ 0, 1, 0, 0 });

        const ubo: UniformBufferObejct = .{
            .model = model_mat,
            .view = view,
            .projection = projection_mat,
        };

        // Push uniform data
        sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, &ubo, @sizeOf(UniformBufferObejct));

        // Bind texture sampler to fragment shader
        sdl.SDL_BindGPUFragmentSamplers(render_pass, 0, &(sdl.SDL_GPUTextureSamplerBinding{ .texture = texture, .sampler = sampler }), 1);

        // Draw the quad
        sdl.SDL_DrawGPUIndexedPrimitives(render_pass, @intCast(indices.len), 1, 0, 0, 0);
        zgui.backend.renderDrawData(@ptrCast(command_buffer), @ptrCast(render_pass), null);

        sdl.SDL_EndGPURenderPass(render_pass);

        try errify(sdl.SDL_SubmitGPUCommandBuffer(command_buffer));
    }

    return 0;
}

/// Converts the return value of an SDL function to an error union.
pub inline fn errify(value: anytype) error{SdlError}!switch (@typeInfo(@TypeOf(value))) {
    .bool => void,
    .pointer, .optional => @TypeOf(value.?),
    .int => |info| switch (info.signedness) {
        .signed => @TypeOf(@max(0, value)),
        .unsigned => @TypeOf(value),
    },
    else => @compileError("unerrifiable type: " ++ @typeName(@TypeOf(value))),
} {
    return switch (@typeInfo(@TypeOf(value))) {
        .bool => if (!value) error.SdlError,
        .pointer, .optional => value orelse error.SdlError,
        .int => |info| switch (info.signedness) {
            .signed => if (value >= 0) @max(0, value) else error.SdlError,
            .unsigned => if (value != 0) value else error.SdlError,
        },
        else => comptime unreachable,
    };
}
