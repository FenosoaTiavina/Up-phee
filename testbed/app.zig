const std = @import("std");
const builtin = @import("builtin");

const uph = @import("uph");
const zgui = uph.zgui;
const ecs = uph.ecs;

// Initialize the ECS registry
var registry: ecs.Registry = undefined;

var camera_entity: ecs.Entity = undefined;

var cam_data: *uph.uph3d.Camera.Camera = undefined;

const log = std.log.scoped(.GAME);

const String = []const u8;

pub fn cam_move(cam: *uph.uph3d.Camera.Camera, e: uph.Input.Event, delta_time: f32) void {
    _ = e; // autofix
    // Initialize movement vector
    var movement = uph.Types.Vec3_f32{ 0.0, 0.0, 0.0 };

    // Check WASD keys for movement
    if (uph.Input.input_manager.isKeyDown(.w)) {
        movement[2] += 1.0; // Forward is positive Z in camera space
    } else if (uph.Input.input_manager.isKeyDown(.s)) {
        movement[2] -= 1.0; // Backward is negative Z in camera space
    }
    if (uph.Input.input_manager.isKeyDown(.a)) {
        movement[0] -= 1.0; // Left is negative X in camera space
    } else if (uph.Input.input_manager.isKeyDown(.d)) {
        movement[0] += 1.0; // Right is positive X in camera space
    }

    // Normalize movement vector if needed (for diagonal movement)
    const length_squared = movement[0] * movement[0] +
        movement[1] * movement[1] +
        movement[2] * movement[2];

    if (length_squared > 0.001) { // Only normalize if there's actual movement
        if (length_squared > 1.001) { // Only normalize if length is not already ~1
            const length = @sqrt(length_squared);
            movement[0] /= length;
            movement[1] /= length;
            movement[2] /= length;
        }

        // We don't need to scale movement by delta_time here, as our refactored
        // Camera.move function already handles time-based movement with acceleration

        // Apply movement to camera - let the camera handle acceleration
        uph.uph3d.Camera.move(cam, movement, delta_time);
    } else {
        // Still call move with zero movement to allow deceleration
        uph.uph3d.Camera.move(cam, movement, delta_time);
    }
}

pub fn cam_rotate(cam: *uph.uph3d.Camera.Camera, e: uph.Input.Event, delta_time: f32) void {
    _ = delta_time; // autofix
    if (e.mouse_motion.relative) {
        uph.uph3d.Camera.rotate(cam, e.mouse_motion.delta.x, e.mouse_motion.delta.y, 0, true);
    }
}

pub fn config(ctx: uph.Context.Context) !uph.Config.Config {
    const exe_path = try std.fs.selfExePathAlloc(ctx.allocator());
    defer ctx.allocator().free(exe_path);
    const opt_exe_dir: String = std.fs.path.dirname(exe_path) orelse {
        return error.ExeDirFail;
    };
    var new_config = ctx.cfg();

    new_config.uph_exe_dir = try ctx.allocator().dupe(u8, opt_exe_dir);

    return new_config;
}

pub fn init(ctx: uph.Context.Context) !void {
    try ctx.registerPlugin("test_hotreload", "./libtest_hotreload.so", true);

    std.log.debug("Hello from entry point", .{}); // Fixed typo

    registry = ecs.Registry.init(ctx.allocator());

    camera_entity = registry.create();

    // Add camera component
    registry.add(
        camera_entity,
        uph.uph3d.Camera.init(
            .{ 0, 0, -5 },
            .{ 0, 0, 0 },
            ctx.renderer().window.window_dimension,
            .prespective,
            0.0001,
            10000,
            45,
        ),
    );
    cam_data = registry.get(uph.uph3d.Camera.Camera, camera_entity);

    const g_id1 = try uph.Renderer.createGraphicsPipeline(ctx.renderer(), .{
        .name = "default",
        .vertex_shader = try uph.Shader.loadShader(ctx.renderer().device, "assets/shaders/compiled/PositionColor.vert.spv", uph.clib.sdl.SDL_GPU_SHADERSTAGE_VERTEX, 1, 0, 0, 0),
        .fragment_shader = try uph.Shader.loadShader(ctx.renderer().device, "assets/shaders/compiled/SolidColor.frag.spv", uph.clib.sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0, 0, 0),
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &uph.clib.sdl.SDL_GPUVertexBufferDescription{
                .slot = 0,
                .pitch = @sizeOf(uph.uph3d.Objects.Vertex),
                .input_rate = uph.clib.sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
                .instance_step_rate = 0,
            },
            .num_vertex_buffers = 1,
            .vertex_attributes = &[_]uph.clib.sdl.SDL_GPUVertexAttribute{
                .{
                    .location = 0,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    .offset = @offsetOf(uph.uph3d.Objects.Vertex, "position"),
                },
            },
            .num_vertex_attributes = 1,
        },
        .cull_mode = uph.clib.sdl.SDL_GPU_CULLMODE_BACK,
        .front_face = uph.clib.sdl.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        .primitive_type = uph.clib.sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .wireframe = false,
    });
    _ = &g_id1; // autofix

    ctx.renderer().clear(uph.Types.Vec4_f32{
        0.28,
        0.28,
        0.28,
        1.00,
    });
}

pub fn event(ctx: uph.Context.Context, e: uph.Input.Event) !void {
    if (e == .quit) {
        log.debug("Bye!", .{});
        ctx.kill(true);
    }

    if (e == .window and e.window.type == .resized) {
        log.debug("Resized", .{});
        uph.uph3d.Camera.updateResize(cam_data, e.window.type.resized.width, e.window.type.resized.height);
    }
    if (e == .key_down) {
        if (uph.Input.input_manager.isKeyDown(.w) or
            uph.Input.input_manager.isKeyDown(.s) or
            uph.Input.input_manager.isKeyDown(.a) or
            uph.Input.input_manager.isKeyDown(.d))
        {
            cam_move(cam_data, e, ctx.deltaTime());
        }
        if (e.key_down.keycode == .g) {
            _ = uph.clib.sdl.SDL_SetWindowRelativeMouseMode(ctx.window().sdl_window, !e.key_down.relative);
        }
    }
    if (e == .mouse_motion) {
        cam_rotate(cam_data, e, ctx.deltaTime());
    }
}

pub fn update(ctx: uph.Context.Context) !void {
    _ = &ctx; // autofix
}

pub fn draw(ctx: uph.Context.Context) !void {
    _ = &ctx; // autofix
    // Debug: Print batch content information before drawing
}

pub fn quit(ctx: uph.Context.Context) void {
    // your deinit code

    registry.deinit();
    ctx.allocator().free(ctx.cfg().uph_exe_dir);
}
