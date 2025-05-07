const std = @import("std");
const builtin = @import("builtin");

const uph = @import("uph");
const zgui = uph.zgui;
const ecs = uph.ecs;

pub const uph_window_always_on_top = true;

// Initialize the ECS registry
var registry: ecs.Registry = undefined;

var camera_entity: ecs.Entity = undefined;

var cam_data: *uph.Components.Camera.CameraData = undefined;

const log = std.log.scoped(.GAME);

pub fn init(ctx: uph.Context.Context) !void {
    std.log.debug("Hello from entry pint", .{});

    registry = ecs.Registry.init(ctx.allocator());

    camera_entity = registry.create();
    const aspect = ctx.renderer().getAspectRatio();

    // Add camera component
    registry.add(camera_entity, uph.Components.Camera.init(.{ 0, 0, -5 }, .{ 0, 0, 0 }, aspect, false));

    // Create a quad entity
    const quad_entity = registry.create();

    // Create mesh component for quad
    const vertices = [_]uph.Components.Mesh.Vertex{
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
    const mesh = try uph.Components.Mesh.createMeshComponent(ctx.renderer(), &vertices, &indices);

    registry.add(quad_entity, mesh);

    // Create texture component
    const texture = try uph.Components.Mesh.createTextureComponent(ctx.renderer(), "assets/kenney_prototypeTextures/PNG/Purple/texture_10.png");
    registry.add(quad_entity, texture);

    try uph.Renderer.createGraphicsPipeline(ctx.renderer(), .{
        .vertex_shader = try uph.Shader.loadShader(ctx.renderer().device, "assets/shaders/compiled/PositionColor.vert.spv", uph.clib.sdl.SDL_GPU_SHADERSTAGE_VERTEX, 1, 0, 0, 0),

        .fragment_shader = try uph.Shader.loadShader(ctx.renderer().device, "assets/shaders/compiled/SolidColor.frag.spv", uph.clib.sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0, 0, 1),
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &uph.clib.sdl.SDL_GPUVertexBufferDescription{
                .slot = 0,
                .pitch = @sizeOf(uph.Components.Mesh.Vertex),
                .input_rate = uph.clib.sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
                .instance_step_rate = 0,
            },
            .num_vertex_buffers = 1,
            .vertex_attributes = &[_]uph.clib.sdl.SDL_GPUVertexAttribute{
                .{
                    .location = 0,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    .offset = @offsetOf(uph.Components.Mesh.Vertex, "position"),
                },
                .{
                    .location = 1,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
                    .offset = @offsetOf(uph.Components.Mesh.Vertex, "color"),
                },
                .{
                    .location = 2,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                    .offset = @offsetOf(uph.Components.Mesh.Vertex, "uv"),
                },
            },
            .num_vertex_attributes = 3,
        },
        .wireframe = false,
    });

    // Add transform component
    const transform = uph.Components.Transform.init();
    registry.add(quad_entity, transform);

    const vertex_shader = try uph.Shader.loadShader(ctx.renderer().device, "assets/shaders/compiled/PositionColor.vert.spv", uph.clib.sdl.SDL_GPU_SHADERSTAGE_VERTEX, 1, 0, 0, 0);
    const fragment_shader = try uph.Shader.loadShader(ctx.renderer().device, "assets/shaders/compiled/SolidColor.frag.spv", uph.clib.sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0, 0, 1);

    try uph.Renderer.createGraphicsPipeline(ctx.renderer(), .{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &uph.clib.sdl.SDL_GPUVertexBufferDescription{
                .slot = 0,
                .pitch = @sizeOf(uph.Components.Mesh.Vertex),
                .input_rate = uph.clib.sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
                .instance_step_rate = 0,
            },
            .num_vertex_buffers = 1,
            .vertex_attributes = &[_]uph.clib.sdl.SDL_GPUVertexAttribute{
                .{
                    .location = 0,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    .offset = @offsetOf(uph.Components.Mesh.Vertex, "position"),
                },
                .{
                    .location = 1,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
                    .offset = @offsetOf(uph.Components.Mesh.Vertex, "color"),
                },
                .{
                    .location = 2,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                    .offset = @offsetOf(uph.Components.Mesh.Vertex, "uv"),
                },
            },
            .num_vertex_attributes = 3,
        },
        .wireframe = false,
    });

    try uph.Renderer.createGraphicsPipeline(ctx.renderer(), .{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &uph.clib.sdl.SDL_GPUVertexBufferDescription{
                .slot = 0,
                .pitch = @sizeOf(uph.Components.Mesh.Vertex),
                .input_rate = uph.clib.sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
                .instance_step_rate = 0,
            },
            .num_vertex_buffers = 1,
            .vertex_attributes = &[_]uph.clib.sdl.SDL_GPUVertexAttribute{
                .{
                    .location = 0,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    .offset = @offsetOf(uph.Components.Mesh.Vertex, "position"),
                },
                .{
                    .location = 1,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
                    .offset = @offsetOf(uph.Components.Mesh.Vertex, "color"),
                },
                .{
                    .location = 2,
                    .buffer_slot = 0,
                    .format = uph.clib.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                    .offset = @offsetOf(uph.Components.Mesh.Vertex, "uv"),
                },
            },
            .num_vertex_attributes = 3,
        },
        .wireframe = true,
    });

    cam_data = registry.get(uph.Components.Camera.CameraData, camera_entity);
    // Game loop variables
}

pub fn event(ctx: uph.Context.Context, e: uph.Input.Event) !void {
    _ = &ctx; // autofix
    //
    if (e == .quit) {
        log.debug("Bye!", .{});
        ctx.kill(true);
    }

    if (e == .window and e.window.type == .resized) {
        log.debug("Resized", .{});
        uph.Components.Camera.updateResize(cam_data, ctx.renderer().getAspectRatio());
    }
}

pub fn update(ctx: uph.Context.Context) !void {
    _ = ctx; // autofix
}

pub fn draw(ctx: uph.Context.Context) !void {
    try ctx.renderer().render(&registry, camera_entity);
}

pub fn quit(ctx: uph.Context.Context) void {
    // your deinit code
    _ = ctx;
    registry.deinit();
}
