const std = @import("std");

const uph = @import("../uph.zig");
const Renderer = uph.Renderer;
const Types = uph.Types;
const uph3d = uph.uph3d;
const c = uph.clib;

pub const TextureData = struct {
    texture: ?*c.sdl.SDL_GPUTexture,
    sampler: ?*c.sdl.SDL_GPUSampler,
};

pub fn createTextureComponent(ctx: uph.Context.Context, texture_path: []const u8) !TextureData {
    var texture_size = [2]usize{ 0, 0 };

    var image_data: [*c]u8 = c.stb.stbi_load(texture_path.ptr, @ptrCast(&texture_size[0]), @ptrCast(&texture_size[1]), null, 4);

    if (image_data == null) {
        return error.TextureLoadFailed;
    }
    defer c.stb.stbi_image_free(image_data);

    const texture_byte_size: u32 = @intCast(texture_size[0] * texture_size[1] * 4);

    // Create texture
    const texture = c.sdl.SDL_CreateGPUTexture(ctx.renderer().device, &c.sdl.SDL_GPUTextureCreateInfo{
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
    const texture_transfer_buffer = c.sdl.SDL_CreateGPUTransferBuffer(ctx.renderer().device, &c.sdl.SDL_GPUTransferBufferCreateInfo{
        .usage = c.sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = texture_byte_size,
    }) orelse {
        return error.TextureTransferBufferCreationFailed;
    };
    defer c.sdl.SDL_ReleaseGPUTransferBuffer(ctx.renderer().device, texture_transfer_buffer);

    const cmd = try ctx.renderer().createRogueCommand();

    const copy_pass = c.sdl.SDL_BeginGPUCopyPass(cmd.command_buffer) orelse {
        return error.CopyPassCreationFailed;
    };

    var pixels = image_data[0..texture_byte_size];
    try uph.Renderer.uploadTextureGPU(ctx.renderer().device, copy_pass, texture_transfer_buffer, texture, 0, u8, &pixels, texture_size, texture_byte_size);

    c.sdl.SDL_EndGPUCopyPass(copy_pass);

    ctx.renderer().submitRogueCommand(cmd);

    return TextureData{
        .texture = texture,
        .sampler = ctx.renderer().default_sampler,
    };
}
