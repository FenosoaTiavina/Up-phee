const uph = @import("../uph.zig");

const c = uph.clib;

const GraphicsPipelineDesc = struct {
    vertex_shader: uph.Shader,
    fragment_shader: uph.Shader,
    vertex_input_state: c.sdl.SDL_GPUVertexInputState,
    cull_mode: c.sdl.SDL_GPUCullMode,
    front_face: c.sdl.SDL_GPUFrontFace,
    primitive_type: c.sdl.SDL_GPUPrimitiveType,
    wireframe: bool,
};

pub fn createGraphicsPipeline(renderer: *uph.Renderer, desc: GraphicsPipelineDesc) !u32 {
    const shader_vert = desc.vertex_shader.module;
    const shader_frag = desc.fragment_shader.module;

    const pipeline_info = c.sdl.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = shader_vert,
        .fragment_shader = shader_frag,
        .vertex_input_state = desc.vertex_input_state,
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &.{
                .format = c.sdl.SDL_GetGPUSwapchainTextureFormat(renderer.device, renderer.window.sdl_window),
            },
        },
        .primitive_type = desc.primitive_type,
        .rasterizer_state = .{
            .cull_mode = desc.cull_mode,
            .front_face = desc.front_face,
            .fill_mode = if (desc.wireframe) c.sdl.SDL_GPU_FILLMODE_LINE else c.sdl.SDL_GPU_FILLMODE_FILL,
        },
    };

    const pipeline = c.sdl.SDL_CreateGPUGraphicsPipeline(renderer.device, &pipeline_info) orelse return error.PipelineCreationFailed;
    const id: u32 = renderer.pipelines.count();
    try renderer.pipelines.put(@intCast(id), pipeline);

    desc.vertex_shader.release(renderer.device);
    desc.fragment_shader.release(renderer.device);
    return id;
}
