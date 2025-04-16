const std = @import("std");

const T_ = @import("../types.zig");

const c = @import("../imports.zig");
const rd = @import("../renderer.zig");

const components = @import("../components.zig");

pub const Vertex = struct {
    position: T_.Vec3_f32,
    color: T_.Vec4_f32,
    uv: T_.Vec2_f32,
};

pub const MeshData = struct {
    vertex_buffer: *c.sdl.SDL_GPUBuffer,
    index_buffer: *c.sdl.SDL_GPUBuffer,
    num_indices: u32,
};

pub fn createMeshComponent(renderer: *rd.Renderer, vertices: []const Vertex, indices: []const u16) !MeshData {
    const vertex_buffer = rd.createBuffer(renderer.device.?, c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX, @intCast(@sizeOf(Vertex) * vertices.len)) orelse {
        return error.VertexBufferCreationFailed;
    };

    const index_buffer = rd.createBuffer(renderer.device.?, c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX, @intCast(@sizeOf(u16) * indices.len)) orelse {
        return error.IndexBufferCreationFailed;
    };

    // Upload data
    const command_buffer = c.sdl.SDL_AcquireGPUCommandBuffer(renderer.device) orelse {
        return error.CommandBufferAcquisitionFailed;
    };

    const copy_pass = c.sdl.SDL_BeginGPUCopyPass(command_buffer) orelse {
        return error.CopyPassCreationFailed;
    };

    try rd.uploadToGPU(renderer.device.?, copy_pass, renderer.transfer_buffer.?, 0, Vertex, vertices, vertex_buffer);
    try rd.uploadToGPU(renderer.device.?, copy_pass, renderer.transfer_buffer.?, @intCast(@sizeOf(Vertex) * vertices.len), u16, indices, index_buffer);

    c.sdl.SDL_EndGPUCopyPass(copy_pass);
    _ = c.sdl.SDL_SubmitGPUCommandBuffer(command_buffer);

    return MeshData{
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .num_indices = @intCast(indices.len),
    };
}

pub const TextureData = struct {
    texture: ?*c.sdl.SDL_GPUTexture,
    sampler: ?*c.sdl.SDL_GPUSampler,
};

pub fn createTextureComponent(renderer: *rd.Renderer, texture_path: []const u8) !TextureData {
    var texture_size = [2]usize{ 0, 0 };
    var image_data: [*c]u8 = c.stb.stbi_load(texture_path.ptr, @ptrCast(&texture_size[0]), @ptrCast(&texture_size[1]), null, 4);

    if (image_data == null) {
        return error.TextureLoadFailed;
    }
    defer c.stb.stbi_image_free(image_data);

    const texture_byte_size: u32 = @intCast(texture_size[0] * texture_size[1] * 4);

    // Create texture
    const texture = c.sdl.SDL_CreateGPUTexture(renderer.device, &c.sdl.SDL_GPUTextureCreateInfo{
        .type = c.sdl.SDL_GPU_TEXTURETYPE_2D,
        .format = c.sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .width = @intCast(texture_size[0]),
        .height = @intCast(texture_size[1]),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .usage = c.sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
    }) orelse {
        return error.TextureCreationFailed;
    };

    // Create transfer buffer for texture
    const texture_transfer_buffer = c.sdl.SDL_CreateGPUTransferBuffer(renderer.device, &c.sdl.SDL_GPUTransferBufferCreateInfo{
        .usage = c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = texture_byte_size,
    }) orelse {
        return error.TextureTransferBufferCreationFailed;
    };
    defer c.sdl.SDL_ReleaseGPUTransferBuffer(renderer.device, texture_transfer_buffer);

    // Upload texture data
    const command_buffer = c.sdl.SDL_AcquireGPUCommandBuffer(renderer.device) orelse {
        return error.CommandBufferAcquisitionFailed;
    };

    const copy_pass = c.sdl.SDL_BeginGPUCopyPass(command_buffer) orelse {
        return error.CopyPassCreationFailed;
    };

    var pixels = image_data[0..texture_byte_size];
    try rd.uploadTextureGPU(renderer.device.?, copy_pass, texture_transfer_buffer, texture, 0, u8, &pixels, texture_size, texture_byte_size);

    c.sdl.SDL_EndGPUCopyPass(copy_pass);
    _ = c.sdl.SDL_SubmitGPUCommandBuffer(command_buffer);

    return TextureData{
        .texture = texture,
        .sampler = renderer.default_sampler,
    };
}

pub fn update(transform: *components.transform.Transform) void {
    components.transform.updateModelMatrix(transform);
}

pub fn updateAndRender(
    command_buffer: *c.sdl.SDL_GPUCommandBuffer,
    render_pass: *c.sdl.SDL_GPURenderPass,
    transform: *components.transform.Transform,
    mesh: *MeshData,
    camera_component: *components.camera.CameraData,
) void {
    update(transform);
    // Bind vertex and index buffers
    const vert_buffer_binding = c.sdl.SDL_GPUBufferBinding{
        .buffer = mesh.vertex_buffer,
        .offset = 0,
    };
    c.sdl.SDL_BindGPUVertexBuffers(render_pass, 0, &vert_buffer_binding, 1);
    c.sdl.SDL_BindGPUIndexBuffer(render_pass, &.{ .buffer = mesh.index_buffer, .offset = 0 }, c.sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT);

    // Push uniform data (model-view-projection)
    const ubo = components.render.UniformBufferObject{
        .model = transform.model_matrix,
        .view = camera_component.view_matrix,
        .projection = camera_component.projection_matrix,
    };

    c.sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, &ubo, @sizeOf(components.render.UniformBufferObject));

    c.sdl.SDL_DrawGPUIndexedPrimitives(render_pass, mesh.num_indices, 1, 0, 0, 0);
}
