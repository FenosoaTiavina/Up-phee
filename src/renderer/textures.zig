const uph = @import("../uph.zig");
const c = uph.clib;
const Types = uph.Types;
const Renderer = uph.Renderer;

const std = @import("std");

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
    const command = try renderer.createRogueCommand();

    const copy_pass = c.sdl.SDL_BeginGPUCopyPass(command.command_buffer) orelse {
        return error.CopyPassCreationFailed;
    };

    var pixels = image_data[0..texture_byte_size];
    try Renderer.uploadTextureGPU(renderer.device, copy_pass, texture_transfer_buffer, texture, 0, u8, &pixels, texture_size, texture_byte_size);

    c.sdl.SDL_EndGPUCopyPass(copy_pass);
    try renderer.submitRogueCommand(command);

    return TextureData{
        .texture = texture,
        .sampler = renderer.default_sampler,
    };
}

pub fn uploadTextureGPU(
    device: *c.sdl.SDL_GPUDevice,
    copy_pass: *c.sdl.SDL_GPUCopyPass,
    transfer_buffer: *c.sdl.SDL_GPUTransferBuffer,
    texture: *c.sdl.SDL_GPUTexture,
    buffer_offset: u32,
    comptime T: type,
    images_data: *[]u8,
    image_size: Types.Vec2_usize,
    image_byte_size: usize,
) !void {
    // Map the buffer memory
    const transfer_data = c.sdl.SDL_MapGPUTransferBuffer(device, transfer_buffer, false) orelse {
        std.log.err("SDL_MapGPUTransferBuffer Failed (upload_cmdbuf)", .{});
        return error.MapFailed;
    };

    // Cast the pointer to bytes and copy the data at the specified offset
    const transfer_bytes: [*]T = @ptrCast(transfer_data);
    @memcpy(transfer_bytes[buffer_offset .. buffer_offset + image_byte_size], images_data.ptr);
    c.sdl.SDL_UnmapGPUTransferBuffer(device, transfer_buffer);

    const texture_transfer_info = c.sdl.struct_SDL_GPUTextureTransferInfo{
        .transfer_buffer = transfer_buffer,
        .offset = buffer_offset,
    };

    const texture_region = c.sdl.SDL_GPUTextureRegion{
        .texture = texture,
        .w = @intCast(image_size[0]),
        .h = @intCast(image_size[1]), // FIXed: was using 'y' property instead of 'h'
        .d = 1,
    };

    c.sdl.SDL_UploadToGPUTexture(copy_pass, &texture_transfer_info, &texture_region, false);
}
