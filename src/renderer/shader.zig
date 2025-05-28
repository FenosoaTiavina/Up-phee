const std = @import("std");
const uph = @import("../uph.zig");
const c = uph.clib;

const Shader = @This();

module: *c.sdl.SDL_GPUShader,

pub fn loadShader(
    ctx: uph.Context.Context,
    filename: [*c]const u8,
    stage: c.sdl.SDL_GPUShaderStage,
    uniform_buffer_count: u32,
    storage_buffer_count: u32,
    storage_texture_count: u32,
    sampler_count: u32,
) !Shader {
    const abs_path = try std.fmt.allocPrint(ctx.allocator(), "{s}/{s}", .{ ctx.cfg().uph_exe_dir, filename });
    defer ctx.allocator().free(abs_path);
    if (c.sdl.SDL_GetPathInfo(@ptrCast(abs_path), null) == false) {
        std.log.err("File ({s}) does not exist.\n", .{abs_path});
        return error.FileNotFound;
    } else {
        std.log.debug("File {s} found!", .{abs_path});
    }

    var entrypoint: [*c]const u8 = undefined;
    const backend_formats = c.sdl.SDL_GetGPUShaderFormats(ctx.renderer().device);
    var format: c.sdl.SDL_GPUShaderFormat = c.sdl.SDL_GPU_SHADERFORMAT_INVALID;
    if (backend_formats & c.sdl.SDL_GPU_SHADERFORMAT_SPIRV != 0) {
        format = c.sdl.SDL_GPU_SHADERFORMAT_SPIRV;
        entrypoint = "main";
    }

    var code_size: usize = undefined;
    const code: [*c]const u8 = @ptrCast(c.sdl.SDL_LoadFile(@ptrCast(abs_path), &code_size).?);

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

    const shader = c.sdl.SDL_CreateGPUShader(ctx.renderer().device, &shader_info) orelse {
        std.log.err("ERROR: SDL_CreateGPUShader failed: {s}\n", .{c.sdl.SDL_GetError()});
        return error.ShaderCreation;
    };
    return .{ .module = shader };
}

pub fn release(
    self: *const Shader,
    ctx: uph.Context.Context,
) void {
    c.sdl.SDL_ReleaseGPUShader(ctx.renderer().device, self.module);
}
