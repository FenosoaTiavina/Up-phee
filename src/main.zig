// main.zig
const std = @import("std");

const ecs = @import("ecs");
const zgui = @import("zgui");

const c = @import("imports.zig");
const components = @import("components.zig");
const renderer = @import("renderer.zig");
const shader = @import("shader.zig");
const T_ = @import("types.zig");

const WINDOW_WIDTH = 1200;
const WINDOW_HEIGHT = 800;

pub fn main() !void {
    // Create an allocator
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    // Initialize the ECS registry
    var registry = ecs.Registry.init(allocator);

    // Initialize the renderer
    var game_renderer = try renderer.Renderer.init(allocator, WINDOW_WIDTH, WINDOW_HEIGHT, "Pressure Simulation");
    defer game_renderer.deinit();

    // Initialize zgui
    zgui.init(allocator);
    defer zgui.deinit();
    //
    zgui.getStyle().setColorsDark();

    zgui.backend.init(game_renderer.window.sdl_window, .{
        .device = game_renderer.device.?,
        .color_target_format = c.sdl.SDL_GetGPUSwapchainTextureFormat(game_renderer.device, game_renderer.window.sdl_window),
        .msaa_samples = c.sdl.SDL_GPU_SAMPLECOUNT_1,
    });
    defer zgui.backend.deinit();

    // Create a camera entity
    const camera_entity = registry.create();
    var aspect = game_renderer.getAspectRatio();

    // Add camera component
    registry.add(camera_entity, components.camera.init(.{ 0, 0, -5 }, .{ 0, 0, 0 }, aspect));

    // Create a quad entity
    const quad_entity = registry.create();

    // Create mesh component for quad
    const vertices = [_]components.mesh.Vertex{
        .{ // top-left
            .position = .{ -0.5, 0.5, 0 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 0.0, 0.0 },
        },
        .{ // top-right
            .position = .{ 0.5, 0.5, 0 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 1.0, 0.0 },
        },
        .{ // bottom-right
            .position = .{ 0.5, -0.5, 0 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 1.0, 1.0 },
        },
        .{ // bottom-left
            .position = .{ -0.5, -0.5, 0 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 0.0, 1.0 },
        },
    };

    const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };

    // Create mesh component
    const mesh = try components.mesh.createMeshComponent(&game_renderer, &vertices, &indices);

    registry.add(quad_entity, mesh);

    // Create texture component
    const texture = try components.mesh.createTextureComponent(&game_renderer, "assets/kenney_prototypeTextures/PNG/Purple/texture_10.png");
    registry.add(quad_entity, texture);

    try renderer.createGraphicsPipeline(&game_renderer, .{
        .vertex_shader = try shader.Shader.loadShader(game_renderer.device.?, "assets/shaders/compiled/PositionColor.vert.spv", c.sdl.SDL_GPU_SHADERSTAGE_VERTEX, 1, 0, 0, 0),
        .fragment_shader = try shader.Shader.loadShader(game_renderer.device.?, "assets/shaders/compiled/SolidColor.frag.spv", c.sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0, 0, 1),
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &c.sdl.SDL_GPUVertexBufferDescription{
                .slot = 0,
                .pitch = @sizeOf(components.mesh.Vertex),
                .input_rate = c.sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
                .instance_step_rate = 0,
            },
            .num_vertex_buffers = 1,
            .vertex_attributes = &[_]c.sdl.SDL_GPUVertexAttribute{
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
            },
            .num_vertex_attributes = 3,
        },
        .wireframe = false,
    });

    // Add transform component
    const transform = components.transform.init();
    registry.add(quad_entity, transform);

    // Game loop variables
    const ROTATION_SPEED = std.math.degreesToRadians(10); // in radians
    _ = ROTATION_SPEED; // autofix
    const MOVE_SPEED = 10;
    _ = MOVE_SPEED; // autofix
    var mouse_grabbed = false;
    var last_ticks = c.sdl.SDL_GetTicks();
    var quit = false;

    // Main game loop
    while (!quit) {
        const new_ticks = c.sdl.SDL_GetTicks();
        const delta_time = @as(f32, @floatFromInt(new_ticks - last_ticks)) / 1000;
        _ = delta_time; // autofix
        last_ticks = new_ticks;

        var event: c.sdl.SDL_Event = undefined;
        const move_vec = [3]f32{ 0, 0, 0 };
        _ = move_vec; // autofix

        // Process events
        while (c.sdl.SDL_PollEvent(&event)) {
            _ = zgui.backend.processEvent(&event);
            switch (event.type) {
                c.sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED, c.sdl.SDL_EVENT_QUIT => {
                    quit = true;
                },
                c.sdl.SDL_EVENT_KEY_DOWN => {
                    switch (event.key.key) {
                        c.sdl.SDLK_Q => {
                            quit = true;
                        },
                        c.sdl.SDLK_G => {
                            mouse_grabbed = !mouse_grabbed;
                            _ = c.sdl.SDL_SetWindowMouseGrab(game_renderer.window.sdl_window, mouse_grabbed);
                            _ = c.sdl.SDL_SetWindowRelativeMouseMode(game_renderer.window.sdl_window, mouse_grabbed);
                        },
                        c.sdl.SDLK_W => {},
                        c.sdl.SDLK_S => {},
                        c.sdl.SDLK_A => {},
                        c.sdl.SDLK_D => {},

                        else => {},
                    }
                },

                c.sdl.SDL_EVENT_MOUSE_MOTION => {
                    const mouse_motion = T_.Vec2_f32{ event.motion.xrel, event.motion.yrel };
                    if (c.sdl.SDL_GetWindowMouseGrab(game_renderer.window.sdl_window)) {
                        const last_cam = registry.get(components.camera.CameraData, camera_entity);
                        components.camera.rotate(last_cam, mouse_motion[0], -mouse_motion[1], 0, true);
                    }
                },

                c.sdl.SDL_EVENT_WINDOW_RESIZED => {
                    aspect = game_renderer.getAspectRatio();
                    components.camera.updateResize(registry.get(components.camera.CameraData, camera_entity), aspect);
                },

                else => {},
            }
        }

        var fb_width: c_int = 0;
        var fb_height: c_int = 0;
        if (!c.sdl.SDL_GetWindowSize(game_renderer.window.sdl_window, &fb_width, &fb_height)) {
            std.log.err("SDL_GetWindowSizeInPixels failed: {s}\n", .{c.sdl.SDL_GetError()});
            return error.SDLGetWindowSize;
        }

        const fb_scale = c.sdl.SDL_GetWindowDisplayScale(game_renderer.window.sdl_window);

        zgui.backend.newFrame(@intCast(fb_width), @intCast(fb_height), fb_scale);

        // Show a simple window
        zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .first_use_ever });
        if (zgui.begin("info", .{})) {
            zgui.text("camera target :{any},{any},{any}", .{
                registry.get(components.camera.CameraData, camera_entity).*.front[0],
                registry.get(components.camera.CameraData, camera_entity).*.front[1],
                registry.get(components.camera.CameraData, camera_entity).*.front[2],
            });

            zgui.text("camera position :{any},{any},{any}", .{
                registry.get(components.camera.CameraData, camera_entity).*.position[0],
                registry.get(components.camera.CameraData, camera_entity).*.position[1],
                registry.get(components.camera.CameraData, camera_entity).*.position[2],
            });
        }
        zgui.end();

        // The SDL3+GPU backend requires calling zgui.backend.render() before rendering ImGui

        zgui.backend.render();
        try game_renderer.beginFrame();
        try game_renderer.render(&registry, camera_entity);
        try game_renderer.endFrame();
    }

    registry.deinit();
}
