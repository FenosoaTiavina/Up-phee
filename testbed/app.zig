const std = @import("std");
const builtin = @import("builtin");

const uph = @import("uph");
const zgui = uph.zgui;
const ecs = uph.ecs;

var registry: ecs.Registry = undefined;

var camera_entity: ecs.Entity = undefined;

var cam_data: *uph.uph_3d.Camera.Camera = undefined;

var cube_manager: *uph.uph_3d.Cubes.Cube = undefined;

var rand: std.Random = undefined;

var rotation: f32 = 0;

pub fn cam_input(cam: *uph.uph_3d.Camera.Camera, e: uph.Input.Event, delta_time: f32) void {
    if (e == .mouse_motion) {
        if (e.mouse_motion.relative) {
            uph.uph_3d.Camera.rotate(cam, e.mouse_motion.delta.x, e.mouse_motion.delta.y, delta_time);
        }
    }

    if (e == .key_down) {
        var movement = uph.Types.Vec3_f32{ 0.0, 0.0, 0.0 };

        // Check WASD keys for movement
        if (uph.Input.input_manager.isKeyDown(.w)) {
            movement[2] += 1.0; // Forward is positive Z in camera space
        } else if (uph.Input.input_manager.isKeyDown(.s)) {
            movement[2] -= 1.0; // Backward is negative Z in camera space
        }
        if (uph.Input.input_manager.isKeyDown(.a)) {
            movement[0] += 1.0;
        } else if (uph.Input.input_manager.isKeyDown(.d)) {
            movement[0] -= 1.0;
        }

        uph.uph_3d.Camera.move(cam, movement, delta_time);
    }

    uph.uph_3d.Camera.update(cam, delta_time);
}

pub fn config(ctx: uph.Context.Context) !uph.Config.Config {
    const exe_path = try std.fs.selfExePathAlloc(ctx.allocator());
    defer ctx.allocator().free(exe_path);
    const opt_exe_dir: []const u8 = std.fs.path.dirname(exe_path) orelse {
        return error.ExeDirFail;
    };
    var new_config = ctx.cfg();

    new_config.uph_exe_dir = try ctx.allocator().dupe(u8, opt_exe_dir);

    return new_config;
}

const log = std.log.scoped(.GAME);

pub fn init(ctx: uph.Context.Context) !void {
    try ctx.registerPlugin("test_hotreload", "./libtest_hotreload.so", true);

    std.log.debug("Hello from entry point", .{}); // Fixed typo

    registry = ecs.Registry.init(ctx.allocator());

    camera_entity = registry.create();

    // Add camera component
    registry.add(
        camera_entity,
        uph.uph_3d.Camera.init(
            .prespective,
            ctx.renderer().window.window_dimension.width,
            ctx.renderer().window.window_dimension.height,
            0.001,
            1_000,
            70,
        ),
    );
    cam_data = registry.get(uph.uph_3d.Camera.Camera, camera_entity);

    const g_id1 = try uph.Pipeline.createGraphicsPipeline(ctx.renderer(), .{
        .vertex_shader = try uph.Shader.loadShader(
            ctx.renderer().device,
            "assets/shaders/compiled/Instanced.vert.spv",
            uph.clib.sdl.SDL_GPU_SHADERSTAGE_VERTEX,
            1, // num_uniform_buffers (ViewProj + any others)
            1, // num_storage_buffers (ObjectBuffer SSBO)
            0, // num_storage_textures
            0, // num_samplers (set this based on your shader's needs)
        ),
        .fragment_shader = try uph.Shader.loadShader(
            ctx.renderer().device,
            "assets/shaders/compiled/SolidColor.frag.spv",
            uph.clib.sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
            0,
            0,
            0,
            0,
        ),
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &uph.clib.sdl.SDL_GPUVertexBufferDescription{
                .slot = 0,
                .pitch = @sizeOf(uph.uph_3d.Objects.Vertex),
                .input_rate = uph.clib.sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX, // Changed from INSTANCE
                .instance_step_rate = 0,
            },
            .num_vertex_buffers = 1,
            .vertex_attributes = &[_]uph.clib.sdl.SDL_GPUVertexAttribute{
                .{
                    .location = 0,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    .offset = @offsetOf(uph.uph_3d.Objects.Vertex, "position"),
                },
            },
            .num_vertex_attributes = 1,
        },
        .width = ctx.window().getSize().width,
        .height = ctx.window().getSize().height,
        .cull_mode = uph.clib.sdl.SDL_GPU_CULLMODE_BACK,
        .front_face = uph.clib.sdl.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        .primitive_type = uph.clib.sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .wireframe = false,
    });

    _ = &g_id1; // autofix

    ctx.renderer().setClearColor(uph.Types.Vec4_f32{
        0.28,
        0.28,
        0.28,
        1.00,
    });

    cube_manager = try uph.uph_3d.Cubes.Cube.init(ctx, g_id1, cam_data, 11);

    var prng = std.Random.DefaultPrng.init(@as(u64, @bitCast(std.time.milliTimestamp())));
    rand = prng.random();
}

pub fn event(ctx: uph.Context.Context, e: uph.Input.Event) !void {
    if (e == .quit) {
        log.debug("Bye!", .{});
        ctx.kill(true);
    }

    if (e == .window and e.window.type == .resized) {
        cam_data.projection.update(e.window.type.resized.width, e.window.type.resized.height);
        try uph.Pipeline.recreateDepthStencil(
            ctx.renderer(),
            e.window.type.resized.width,
            e.window.type.resized.height,
        );
    }

    if (e == .key_down) {
        if (e.key_down.keycode == .g) {
            _ = uph.clib.sdl.SDL_SetWindowRelativeMouseMode(ctx.window().sdl_window, !e.key_down.relative);
        }
    }
    cam_input(cam_data, e, ctx.deltaTime());
}

pub fn update(ctx: uph.Context.Context) !void {
    _ = &ctx; // autofix
    rotation += 25 * ctx.deltaTime();
    rotation = uph.zmath.clamp(rotation, 0, 306);
}

pub fn draw(ctx: uph.Context.Context) !void {
    _ = &ctx; // autofix
    try cube_manager.beginDraw();

    for (0..9) |i| {
        var trs = uph.uph_3d.Transform.Transform.init();
        _ = trs
            .translate(@as(f32, @floatFromInt(i)) * 1.5, 0.0, 0.0)
            .rotate(0, rotation, 0).setScale(.{ 5, 5, 5 });
        const col = uph.Types.Vec4_f32{
            if (i < 3) 1 else 0,
            if (i >= 3 and i < 6) 1 else 0,
            if (i >= 6 and i < 9) 1 else 0,
            1.0,
        };
        try cube_manager.draw(trs, col);
    }
    try cube_manager.endDraw();
}

pub fn quit(ctx: uph.Context.Context) void {
    // your deinit code
    _ = &ctx;
    cube_manager.deinit();
    registry.deinit();
    ctx.allocator().free(ctx.cfg().uph_exe_dir);
}
