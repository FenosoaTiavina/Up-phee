// main.zig
const std = @import("std");
const zgui = @import("zgui");
const ecs = @import("ecs");
const components = @import("components.zig");
const renderer = @import("renderer.zig");

const c = @import("imports.zig");

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

    // // Initialize zgui
    // zgui.init(allocator);
    // defer zgui.deinit();
    //
    // zgui.getStyle().setColorsDark();

    // zgui.backend.init(game_renderer.window.sdl_window, .{
    //     .device = game_renderer.device.?,
    //     .color_target_format = c.sdl.SDL_GetGPUSwapchainTextureFormat(game_renderer.device, game_renderer.window.sdl_window),
    //     .msaa_samples = c.sdl.SDL_GPU_SAMPLECOUNT_1,
    // });
    // defer zgui.backend.deinit();

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
    const mesh = try game_renderer.createMeshComponent(&vertices, &indices);

    registry.add(quad_entity, mesh);

    // Create texture component
    const texture = try game_renderer.createTextureComponent("assets/kenney_prototypeTextures/PNG/Purple/texture_10.png");
    registry.add(quad_entity, texture);

    // Add transform component
    const transform = components.transform.init();
    registry.add(quad_entity, transform);

    // Game loop variables
    const ROTATION_SPEED = std.math.degreesToRadians(10); // in radians
    _ = ROTATION_SPEED; // autofix
    const MOVE_SPEED = 10;
    _ = MOVE_SPEED; // autofix
    const mouse_grabbed = false;
    _ = mouse_grabbed; // autofix
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
            // _ = zgui.backend.processEvent(&event);

            switch (event.type) {
                c.sdl.SDL_EVENT_QUIT => {
                    quit = true;
                },
                else => {},
            }

            try game_renderer.render(&registry, camera_entity);
        }
    }

    registry.deinit();
}
