// main.zig
const std = @import("std");

const uph = @import("uph");

const ecs = uph.ecs;
const zgui = uph.zgui;
const zmath = uph.zmath;

const c = uph.clib;
const Renderer = uph.Renderer;
const shader = uph.Shader;
const Components = uph.Components;

const EventSystem = uph.Events;
const Keys = EventSystem.keys.Keys;
const InputSystem = EventSystem.input.InputSystem;

const Types = uph.Types;

const WINDOW_WIDTH = 1200;
const WINDOW_HEIGHT = 800;

fn on_move_key(_: *EventSystem.EventManager, event_received: *EventSystem.EventMap, delta_time: *f32, ctx: *anyopaque) bool {
    const cam: *Components.Camera.Camera = @ptrCast(@alignCast(ctx));
    var movement = Types.Vec3_f32{ 0.0, 0.0, 0.0 };

    for (event_received.keys.items) |ev_k| {
        if (ev_k.code == .Key_W and ev_k.pressed) {
            movement[2] += 1.0; // Forward is positive Z in camera space
        }
        if (ev_k.code == .Key_S and ev_k.pressed) {
            movement[2] -= 1.0; // Backward is negative Z in camera space
        }
        if (ev_k.code == .Key_A and ev_k.pressed) {
            movement[0] -= 1.0; // Left is negative X in camera space
        }
        if (ev_k.code == .Key_D and ev_k.pressed) {
            movement[0] += 1.0; // Right is positive X in camera space
        }
    }

    // Only proceed if there's any movement
    if (movement[0] != 0.0 or movement[1] != 0.0 or movement[2] != 0.0) {
        // Calculate length of the movement vector
        const length_squared = movement[0] * movement[0] +
            movement[1] * movement[1] +
            movement[2] * movement[2];

        // Normalize only if length is not 1 (diagonal movement)
        if (length_squared > 1.0001) {
            const length = @sqrt(length_squared);
            movement[0] /= length;
            movement[1] /= length;
            movement[2] /= length;
        }

        // Scale movement by delta time and speed
        const scaled_movement = Types.Vec3_f32{
            movement[0] * delta_time.* * cam.speed,
            movement[1] * delta_time.* * cam.speed,
            movement[2] * delta_time.* * cam.speed,
        };

        // Apply movement to camera
        Components.Camera.move(cam, scaled_movement);
    }

    return true;
}

fn on_mouse_motion(_: *EventSystem.EventManager, event_received: *EventSystem.EventMap, _: *f32, ctx: *anyopaque) bool {
    const cam: *Components.Camera.Camera = @ptrCast(@alignCast(ctx));

    if (event_received.mouse_motion != null and event_received.grabbed != null and event_received.grabbed.? == true) {
        Components.Camera.rotate(cam, event_received.mouse_motion.?.x_rel, event_received.mouse_motion.?.y_rel, 0, true);
    }

    return true;
}

fn toggle_grabbed(_: *EventSystem.EventManager, event_received: *EventSystem.EventMap, _: *f32, ctx: *anyopaque) bool {
    const sdl_win: *c.sdl.SDL_Window = @ptrCast(@alignCast(ctx));

    for (event_received.keys.items) |ev_k| {
        if (ev_k.code == .Key_G and ev_k.pressed == true and event_received.grabbed != null) {
            const state = !event_received.grabbed.?;
            _ = c.sdl.SDL_SetWindowRelativeMouseMode(sdl_win, state);
            _ = c.sdl.SDL_SetWindowMouseGrab(sdl_win, state);
        }
    }
    return true;
}

pub fn main() !void {
    // Create an allocator
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    // Initialize the ECS registry
    var registry = ecs.Registry.init(allocator);

    var game_renderer = try Renderer.Renderer.init(allocator, WINDOW_WIDTH, WINDOW_HEIGHT, "HEHE");
    defer game_renderer.deinit();

    // Initialize zgui
    zgui.init(allocator);
    defer zgui.deinit();
    //
    zgui.getStyle().setColorsDark();

    zgui.backend.init(game_renderer.window.sdl_window, .{
        .device = game_renderer.device,
        .color_target_format = game_renderer.getSwapchainTextureFormat(),
        .msaa_samples = c.sdl.SDL_GPU_SAMPLECOUNT_1,
    });

    defer zgui.backend.deinit();

    // Initialize the renderer
    // Create a camera entity
    const camera_entity = registry.create();
    const aspect = game_renderer.getAspectRatio();

    // Add camera component
    registry.add(camera_entity, Components.Camera.init(.{ 0, 0, -5 }, .{ 0, 0, 0 }, aspect, false));

    // Create a quad entity
    const quad_entity = registry.create();

    // Create mesh component for quad
    const vertices = [_]Components.Mesh.Vertex{
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
    const mesh = try Components.Mesh.createMeshComponent(&game_renderer, &vertices, &indices);

    registry.add(quad_entity, mesh);

    // Create texture component
    const texture = try Components.Mesh.createTextureComponent(&game_renderer, "assets/kenney_prototypeTextures/PNG/Purple/texture_10.png");
    registry.add(quad_entity, texture);

    try Renderer.createGraphicsPipeline(&game_renderer, .{
        .vertex_shader = try shader.Shader.loadShader(game_renderer.device, "assets/shaders/compiled/PositionColor.vert.spv", c.sdl.SDL_GPU_SHADERSTAGE_VERTEX, 1, 0, 0, 0),
        .fragment_shader = try shader.Shader.loadShader(game_renderer.device, "assets/shaders/compiled/SolidColor.frag.spv", c.sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0, 0, 1),
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &c.sdl.SDL_GPUVertexBufferDescription{
                .slot = 0,
                .pitch = @sizeOf(Components.Mesh.Vertex),
                .input_rate = c.sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
                .instance_step_rate = 0,
            },
            .num_vertex_buffers = 1,
            .vertex_attributes = &[_]c.sdl.SDL_GPUVertexAttribute{
                .{
                    .location = 0,
                    .buffer_slot = 0,
                    .format = c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    .offset = @offsetOf(Components.Mesh.Vertex, "position"),
                },
                .{
                    .location = 1,
                    .buffer_slot = 0,
                    .format = c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
                    .offset = @offsetOf(Components.Mesh.Vertex, "color"),
                },
                .{
                    .location = 2,
                    .buffer_slot = 0,
                    .format = c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                    .offset = @offsetOf(Components.Mesh.Vertex, "uv"),
                },
            },
            .num_vertex_attributes = 3,
        },
        .wireframe = false,
    });

    // Add transform component
    const transform = Components.Transform.init();
    registry.add(quad_entity, transform);

    // Game loop variables
    var mouse_grabbed = false;
    _ = &mouse_grabbed; // autofix
    var last_ticks = c.sdl.SDL_GetTicks();
    var quit = false;
    _ = &quit;

    const cam = registry.get(Components.Camera.Camera, camera_entity);

    var delta_time: f32 = 0;

    var event_manager = try EventSystem.EventManager.init(allocator, &delta_time);
    defer event_manager.deinit();

    var input_manager = InputSystem.init(allocator, &event_manager);
    defer input_manager.deinit();

    try event_manager.subscribe(
        try EventSystem.EventMap.init(
            event_manager.allocator,
            &[_]EventSystem.KeyEvent.Key{
                .{ .code = .Key_W, .pressed = true },
                .{ .code = .Key_S, .pressed = true },
                .{ .code = .Key_A, .pressed = true },
                .{ .code = .Key_D, .pressed = true },
            },
            null,
            null,
            null,
            null,
        ),
        true,
        EventSystem.EventCallback.init(
            cam,
            on_move_key,
        ),
    );
    try event_manager.subscribe(
        try EventSystem.EventMap.init(
            event_manager.allocator,
            &[_]EventSystem.KeyEvent.Key{
                .{ .code = .Key_G, .pressed = true },
            },
            null,
            null,
            null,
            null,
        ),
        true,
        EventSystem.EventCallback.init(
            game_renderer.window.sdl_window,
            toggle_grabbed,
        ),
    );

    try event_manager.subscribe(
        try EventSystem.EventMap.init(
            event_manager.allocator,
            null,
            null,
            null,
            EventSystem.MouseEvent.Motion{},
            null,
        ),
        true,
        EventSystem.EventCallback.init(
            cam,
            on_mouse_motion,
        ),
    );

    // Main game loop
    while (!quit) {
        const new_ticks = c.sdl.SDL_GetTicks();
        delta_time = @as(f32, @floatFromInt(new_ticks - last_ticks)) / 1000;
        last_ticks = new_ticks;

        quit = try input_manager.pollEvents(game_renderer.window.sdl_window, true);

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
                registry.get(Components.Camera.Camera, camera_entity).*.front[0],
                registry.get(Components.Camera.Camera, camera_entity).*.front[1],
                registry.get(Components.Camera.Camera, camera_entity).*.front[2],
            });
            zgui.text("camera front :{any},{any},{any}", .{
                registry.get(Components.Camera.Camera, camera_entity).*.front[0],
                registry.get(Components.Camera.Camera, camera_entity).*.front[1],
                registry.get(Components.Camera.Camera, camera_entity).*.front[2],
            });

            zgui.text("camera position :{any},{any},{any}", .{
                registry.get(Components.Camera.Camera, camera_entity).*.position[0],
                registry.get(Components.Camera.Camera, camera_entity).*.position[1],
                registry.get(Components.Camera.Camera, camera_entity).*.position[2],
            });

            if (zgui.button("reset Cam", .{})) {
                cam.*.position = .{ 0, 0, -5, 1.0 }; // W component should be 1.0
                Components.Camera.update(cam);
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
