const std = @import("std");
const c = @import("./imports.zig");

module: *c.sdl.SDL_GPUShader,

pub fn loadShader(
    device: *c.sdl.SDL_GPUDevice,
    filename: [*c]const u8,
    stage: c.sdl.SDL_GPUShaderStage,
    uniform_buffer_count: u32,
    storage_buffer_count: u32,
    storage_texture_count: u32,
    sampler_count: u32,
) !@This() {
    if (c.sdl.SDL_GetPathInfo(filename, null) == false) {
        std.log.err("File ({s}) does not exist.\n", .{filename});
        return error.FileNotFound;
    }

    var entrypoint: [*c]const u8 = undefined;
    const backend_formats = c.sdl.SDL_GetGPUShaderFormats(device);
    var format: c.sdl.SDL_GPUShaderFormat = c.sdl.SDL_GPU_SHADERFORMAT_INVALID;
    if (backend_formats & c.sdl.SDL_GPU_SHADERFORMAT_SPIRV != 0) {
        format = c.sdl.SDL_GPU_SHADERFORMAT_SPIRV;
        entrypoint = "main";
    }

    var code_size: usize = undefined;
    const code: [*c]const u8 = @ptrCast(c.sdl.SDL_LoadFile(filename, &code_size).?);

    defer c.sdl.SDL_free(@constCast(code));

    const shader_info = c.sdl.SDL_GPUShaderCreateInfo{
        .code = code,
        .code_size = code_size,
        .entrypoint = entrypoint,
        .format = format,
        .stage = stage,
        .num_samplers = sampler_count,
        .num_uniform_buffers = uniform_buffer_count,
        .num_storage_buffers = storage_buffer_count,
        .num_storage_textures = storage_texture_count,
    };

    const shader = c.sdl.SDL_CreateGPUShader(device, &shader_info) orelse {
        std.log.err("ERROR: SDL_CreateGPUShader failed: {s}\n", .{c.sdl.SDL_GetError()});
        return error.ShaderCreation;
    };
    return .{ .module = shader };
}
