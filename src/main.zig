const std = @import("std");

const za = @import("zalgebra");
/// END : IMPORTS -------------------------------------------------------------------------------------------------------------
const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Vec4_u8 = za.GenericVector(4, u8);
const Vec4 = za.Vec4;
const Mat4 = za.Mat4;

const stb = @cImport({
    @cInclude("stb/stb_image.h");
});

const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_gpu.h");
    @cInclude("SDL3/SDL_pixels.h");
    @cInclude("SDL3/SDL_video.h");
});

const Vertex = struct {
    position: za.Vec3,
    color: Vec4,
    uv: Vec2,
};

const UniformBufferObejct = struct {
    model: Mat4,
    view: Mat4,
    projection: Mat4,
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
    image_size: za.Vec2_usize,
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
        .w = @intCast(image_size.x()),
        .h = @intCast(image_size.y()), // FIXed: was using 'y' property instead of 'h'
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

    var texture_size = za.Vec2_usize.new(0, 0);
    var pixels: []u8 = undefined;
    var image_data: [*c]u8 = stb.stbi_load(
        "assets/kenney_prototypeTextures/PNG/Purple/texture_10.png",
        @ptrCast(texture_size.xMut()),
        @ptrCast(texture_size.yMut()),
        null,
        4,
    );

    // FIX: Calculate correct byte size
    const texture_byte_size: u32 = @intCast(texture_size.x() * texture_size.y() * 4);
    if (image_data != null) {
        pixels = image_data[0..@intCast(texture_size.x() * texture_size.y() * 4)];
        std.log.debug("images {d}x{d}: {d}", .{
            texture_size.x(),
            texture_size.y(),
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
        .width = @intCast(texture_size.x()), // FIXed: was switched
        .height = @intCast(texture_size.y()), // FIXed: was switched
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
            .position = za.Vec3.new(-0.5, 0.5, 0),
            .color = Vec4.new(1.0, 1.0, 1.0, 1.0),
            .uv = Vec2.new(0.0, 0.0),
        },
        .{ // top-right
            .position = za.Vec3.new(0.5, 0.5, 0),
            .color = Vec4.new(1.0, 1.0, 1.0, 1.0),
            .uv = Vec2.new(1.0, 0.0),
        },
        .{ // bottom-right
            .position = za.Vec3.new(0.5, -0.5, 0),
            .color = Vec4.new(1.0, 1.0, 1.0, 1.0),
            .uv = Vec2.new(1.0, 1.0),
        },
        .{ // bottom-left
            .position = za.Vec3.new(-0.5, -0.5, 0),
            .color = Vec4.new(1.0, 1.0, 1.0, 1.0),
            .uv = Vec2.new(0.0, 1.0),
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
            .fill_mode = sdl.SDL_GPU_FILLMODE_LINE,
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
    // FIX: Calculate aspect ratio correctly
    const aspect: f32 = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));

    const ROTATION_SPEED = 90.0;
    var rotation: f32 = 0.0;
    var translate_z: f32 = 0.0; // FIX: Start with a negative Z to see the quad
    const MOVE_SPEED = 0.7;

    const projection_mat: Mat4 = za.perspective(70.0, aspect, 0.0001, 10000.0); // FIX: Use more reasonable near/far planes
    var quit = false;

    var camera_pos = Vec3.new(0.0, 0.0, 0.0);
    const camera_front = Vec3.new(0.0, 0.0, -1.0);
    const camera_up = Vec3.new(0.0, 1.0, 0.0);

    var last_ticks = sdl.SDL_GetTicks();
    while (!quit) {
        const new_ticks = sdl.SDL_GetTicks();
        const delta_time = @as(f32, @floatFromInt(new_ticks - last_ticks)) / 1000;
        last_ticks = new_ticks;
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event)) {
            switch (event.type) {
                sdl.SDL_EVENT_QUIT => {
                    quit = true;
                },
                sdl.SDL_EVENT_KEY_DOWN => {
                    switch (event.key.key) {
                        sdl.SDLK_Q => {
                            quit = true;
                        },
                        sdl.SDLK_W => {
                            translate_z += MOVE_SPEED; // Move forward
                        },
                        sdl.SDLK_S => {
                            translate_z -= MOVE_SPEED; // Move backward
                        },
                        else => {},
                    }
                },
                sdl.SDL_EVENT_MOUSE_WHEEL => {
                    translate_z += (event.wheel.y * MOVE_SPEED);
                },
                else => {},
            }
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

        const render_pass = sdl.SDL_BeginGPURenderPass(cmdbuf, &color_target_info, 1, null) orelse {
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
        const model_mat = Mat4.mul(
            Mat4.fromTranslate(Vec3.new(0, 0, translate_z)),
            Mat4.fromRotation(rotation, Vec3.new(0, 1, 0)),
        );
        const view = za.lookAt(camera_pos, camera_pos.add(camera_front), camera_up);

        const ubo: UniformBufferObejct = .{
            .model = model_mat,
            .view = view,
            .projection = projection_mat,
        };

        // Push uniform data
        sdl.SDL_PushGPUVertexUniformData(cmdbuf, 0, &ubo, @sizeOf(UniformBufferObejct));

        // Bind texture sampler to fragment shader
        sdl.SDL_BindGPUFragmentSamplers(render_pass, 0, &(sdl.SDL_GPUTextureSamplerBinding{ .texture = texture, .sampler = sampler }), 1);

        // Draw the quad
        sdl.SDL_DrawGPUIndexedPrimitives(render_pass, @intCast(indices.len), 1, 0, 0, 0);
        sdl.SDL_EndGPURenderPass(render_pass);

        _ = sdl.SDL_SubmitGPUCommandBuffer(cmdbuf);
    }

    return 0;
}
