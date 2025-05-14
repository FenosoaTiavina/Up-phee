const std = @import("std");

const c = @import("../imports.zig");
const Renderer = @import("../renderer.zig");
const Types = @import("../types.zig");
const uph3d = @import("./3d.zig");

pub const TextureData = struct {
    texture: ?*c.sdl.SDL_GPUTexture,
    sampler: ?*c.sdl.SDL_GPUSampler,
};

pub fn createTextureComponent(renderer: *Renderer.Renderer, texture_path: []const u8) !TextureData {
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
    try Renderer.uploadTextureGPU(renderer.device, copy_pass, texture_transfer_buffer, texture, 0, u8, &pixels, texture_size, texture_byte_size);

    c.sdl.SDL_EndGPUCopyPass(copy_pass);
    _ = c.sdl.SDL_SubmitGPUCommandBuffer(command_buffer);

    return TextureData{
        .texture = texture,
        .sampler = renderer.default_sampler,
    };
}
