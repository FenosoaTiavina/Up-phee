const std = @import("std");
const builtin = @import("builtin");

const uph = @import("uph");
const zgui = uph.zgui;
const ecs = uph.ecs;

pub const uph_window_always_on_top = true;

// Initialize the ECS registry
var registry: ecs.Registry = undefined;

var batch1: uph.uph3d.Batch = undefined;

var camera_entity: ecs.Entity = undefined;

var cam_data: *uph.uph3d.Camera.Camera = undefined;

const log = std.log.scoped(.GAME);

pub fn init(ctx: uph.Context.Context) !void {
    std.log.debug("Hello from entry point", .{}); // Fixed typo

    registry = ecs.Registry.init(ctx.allocator());

    camera_entity = registry.create();
    const aspect = ctx.renderer().getAspectRatio();

    // Add camera component
    registry.add(camera_entity, uph.uph3d.Camera.init(.{ 0, 0, -5 }, .{ 0, 0, 0 }, aspect, false));
    cam_data = registry.get(uph.uph3d.Camera.Camera, camera_entity);

    const g_id1 = try uph.Renderer.createGraphicsPipeline(ctx.renderer(), .{
        .vertex_shader = try uph.Shader.loadShader(ctx.renderer().device, "assets/shaders/compiled/PositionColor.vert.spv", uph.clib.sdl.SDL_GPU_SHADERSTAGE_VERTEX, 1, 0, 0, 0),
        .fragment_shader = try uph.Shader.loadShader(ctx.renderer().device, "assets/shaders/compiled/SolidColor.frag.spv", uph.clib.sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0, 0, 1),
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &uph.clib.sdl.SDL_GPUVertexBufferDescription{
                .slot = 0,
                .pitch = @sizeOf(uph.uph3d.Mesh.Vertex),
                .input_rate = uph.clib.sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
                .instance_step_rate = 0,
            },
            .num_vertex_buffers = 1,
            .vertex_attributes = &[_]uph.clib.sdl.SDL_GPUVertexAttribute{
                .{
                    .location = 0,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    .offset = @offsetOf(uph.uph3d.Mesh.Vertex, "position"),
                },
                .{
                    .location = 1,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
                    .offset = @offsetOf(uph.uph3d.Mesh.Vertex, "color"),
                },
                .{
                    .location = 2,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                    .offset = @offsetOf(uph.uph3d.Mesh.Vertex, "uv"),
                },
            },
            .num_vertex_attributes = 3,
        },
        .wireframe = false,
    });

    batch1 = try uph.uph3d.Batch.init(ctx.allocator(), ctx.renderer(), g_id1, cam_data);

    const cube_entt = registry.create();
    registry.add(cube_entt, uph.uph3d.Shapes.Cube.cube());

    var cube = registry.get(uph.uph3d.Shapes.Cube, cube_entt);

    // Debug: Print the cube vertices to confirm they exist
    std.debug.print("Adding cube with {d} vertices and {d} indices\n", .{ cube.vertices.len, cube.indices.len });

    cube.addToBatch(&batch1);

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
        uph.uph3d.Camera.updateResize(cam_data, ctx.renderer().getAspectRatio());
    }
}

pub fn update(ctx: uph.Context.Context) !void {
    _ = &ctx; // autofix
}

pub fn draw(ctx: uph.Context.Context) !void {
    _ = &ctx; // autofix
    // Debug: Print batch content information before drawing
    std.debug.print("Batch contains {d} vertices and {d} indices\n", .{ batch1.vertices.items.len, batch1.indices.items.len });

    try batch1.draw();
}

pub fn quit(ctx: uph.Context.Context) void {
    // your deinit code
    _ = ctx;
    batch1.deinit();
    registry.deinit();
}
