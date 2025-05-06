const std = @import("std");
const builtin = @import("builtin");

const uph = @import("uph");
const zgui = uph.zgui;

pub const uph_window_always_on_top = true;

pub fn init(ctx: uph.Context.Context) !void {
    std.log.debug("Hello from entry pint", .{});

    const vertex_shader = try uph.Shader.Shader.loadShader(ctx.renderer().device, "assets/shaders/compiled/PositionColor.vert.spv", uph.clib.sdl.SDL_GPU_SHADERSTAGE_VERTEX, 1, 0, 0, 0);
    const fragment_shader = try uph.Shader.Shader.loadShader(ctx.renderer().device, "assets/shaders/compiled/SolidColor.frag.spv", uph.clib.sdl.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0, 0, 1);
    try uph.Renderer.createGraphicsPipeline(ctx.renderer(), .{
        .pipeline_name = "Graphics",
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
        .pipeline_name = "Wireframe",
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
}

pub fn event(ctx: uph.Context.Context, e: uph.Input.Event) !void {
    _ = &ctx; // autofix
    //
    if (e == .quit) {
        std.log.debug("bye!!", .{});
        ctx.kill(true);
    }
}

pub fn update(ctx: uph.Context.Context) !void {
    _ = ctx; // autofix
}

pub fn draw(ctx: uph.Context.Context) !void {
    try ctx.renderer().zgui_render();
}

pub fn quit(ctx: uph.Context.Context) void {
    // your deinit code
    _ = ctx;
}
