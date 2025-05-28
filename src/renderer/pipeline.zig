const uph = @import("../uph.zig");

const DEPTH_TEX_FORMAT = c.sdl.SDL_GPU_TEXTUREFORMAT_D24_UNORM;

const c = uph.clib;

const GraphicsPipelineDesc = struct {
    vertex_shader: uph.Shader,
    fragment_shader: uph.Shader,
    vertex_input_state: c.sdl.SDL_GPUVertexInputState,
    cull_mode: c.sdl.SDL_GPUCullMode,
    front_face: c.sdl.SDL_GPUFrontFace,
    primitive_type: c.sdl.SDL_GPUPrimitiveType,
    wireframe: bool,
    width: u32,
    height: u32,
};

pub fn createGraphicsPipeline(renderer: *uph.Renderer, desc: GraphicsPipelineDesc) !u32 {
    const shader_vert = desc.vertex_shader.module;
    const shader_frag = desc.fragment_shader.module;
    const depth_texture = c.sdl.SDL_CreateGPUTexture(renderer.device, &c.sdl.SDL_GPUTextureCreateInfo{
        .type = c.sdl.SDL_GPU_TEXTURETYPE_2D,
        .format = DEPTH_TEX_FORMAT,
        .width = desc.width,
        .height = desc.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .usage = c.sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    }) orelse {
        return error.TextureCreationFailed;
    };

    renderer.setDepthStencil(depth_texture);

    const pipeline_info = c.sdl.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = shader_vert,
        .fragment_shader = shader_frag,
        .vertex_input_state = desc.vertex_input_state,
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &.{
                .format = c.sdl.SDL_GetGPUSwapchainTextureFormat(renderer.device, renderer.window.sdl_window),
            },
            .has_depth_stencil_target = true,
            .depth_stencil_format = DEPTH_TEX_FORMAT,
        },
        .primitive_type = desc.primitive_type,
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .compare_op = c.sdl.SDL_GPU_COMPAREOP_LESS,
        },
        .rasterizer_state = .{
            .cull_mode = desc.cull_mode,
            .front_face = desc.front_face,
            .fill_mode = if (desc.wireframe) c.sdl.SDL_GPU_FILLMODE_LINE else c.sdl.SDL_GPU_FILLMODE_FILL,
        },
    };

    const pipeline = c.sdl.SDL_CreateGPUGraphicsPipeline(renderer.device, &pipeline_info) orelse return error.PipelineCreationFailed;
    const id: u32 = renderer.pipelines.count();
    try renderer.pipelines.put(@intCast(id), pipeline);

    // desc.vertex_shader.release(renderer.device);
    // desc.fragment_shader.release(renderer.device);
    return id;
}

pub fn recreateDepthStencil(
    renderer: *uph.Renderer,
    width: u32,
    height: u32,
) !void {
    const depth_texture = c.sdl.SDL_CreateGPUTexture(renderer.device, &c.sdl.SDL_GPUTextureCreateInfo{
        .type = c.sdl.SDL_GPU_TEXTURETYPE_2D,
        .format = DEPTH_TEX_FORMAT,
        .width = width,
        .height = height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .usage = c.sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    }) orelse {
        return error.TextureCreationFailed;
    };

    renderer.setDepthStencil(depth_texture);
}
