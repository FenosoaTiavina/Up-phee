// main.zig
const std = @import("std");

const ecs = @import("ecs");
const zgui = @import("zgui");

const c = @import("imports.zig");
const components = @import("components.zig");
const renderer = @import("engine/renderer.zig");
const shader = @import("engine/shader.zig");

const EventSystem = @import("engine/event/event.zig");
const Keys = @import("engine/event/keys.zig").Keys;
const KeyBitfield = @import("engine/event/keybitfield.zig").KeyBitfield;
const InputSystem = @import("engine/event/input.zig").InputSystem;

const T_ = @import("types.zig");

const WINDOW_WIDTH = 1200;
const WINDOW_HEIGHT = 800;

fn on_move_key(event_manager: *EventSystem.EventManager, event_received: *EventSystem.EventMap, delta_time: *f32, ctx: *anyopaque) bool {
    _ = delta_time; // autofix
    _ = event_manager; // autofix
    const cam: *components.camera.CameraData = @ptrCast(@alignCast(ctx));
    _ = cam; // autofix

    std.log.debug("move {any}", .{event_received.*.keys});

    return true;
}

pub fn main() !void {
    // Create an allocator
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    // Initialize the ECS registry
    var registry = ecs.Registry.init(allocator);

    var game_renderer = try renderer.Renderer.init(allocator, WINDOW_WIDTH, WINDOW_HEIGHT, "HEHE");
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

    // Initialize the renderer
    // Create a camera entity
    const camera_entity = registry.create();
    const aspect = game_renderer.getAspectRatio();

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
    var mouse_grabbed = false;
    _ = &mouse_grabbed; // autofix
    var last_ticks = c.sdl.SDL_GetTicks();
    var quit = false;
    _ = &quit;

    const cam = registry.get(components.camera.CameraData, camera_entity);
    var delta_time: f32 = 0;
    var event_manager = try EventSystem.EventManager.init(allocator, &delta_time);
    defer event_manager.deinit();

    var input_manager = InputSystem.init(allocator, &event_manager);
    defer input_manager.deinit();

    try event_manager.subscribe(
        try EventSystem.EventMap.listener(
            &[_]EventSystem.KeyEvent.Key{
                .{ .code = .Key_W, .pressed = true },
                .{ .code = .Key_S, .pressed = true },
            },
            null,
            null,
            null,
            null,
        ),
        false,
        EventSystem.EventCallback.init(
            cam,
            on_move_key,
        ),
    );

    // Main game loop
    while (!quit) {
        const new_ticks = c.sdl.SDL_GetTicks();
        delta_time = @as(f32, @floatFromInt(new_ticks - last_ticks)) / 1000;
        last_ticks = new_ticks;

        quit = try input_manager.pollEvents();

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
            zgui.text("camera front :{any},{any},{any}", .{
                registry.get(components.camera.CameraData, camera_entity).*.front[0],
                registry.get(components.camera.CameraData, camera_entity).*.front[1],
                registry.get(components.camera.CameraData, camera_entity).*.front[2],
            });

            zgui.text("camera position :{any},{any},{any}", .{
                registry.get(components.camera.CameraData, camera_entity).*.position[0],
                registry.get(components.camera.CameraData, camera_entity).*.position[1],
                registry.get(components.camera.CameraData, camera_entity).*.position[2],
            });

            if (zgui.button("reset Cam", .{})) {
                cam.*.position = .{ 0, 0, -5, 0 };
                components.camera.update(cam);
            }
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
