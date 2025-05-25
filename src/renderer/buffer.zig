const std = @import("std");

const uph = @import("../uph.zig");
const c = uph.clib;
const Types = uph.Types;

pub fn createBuffer(
    device: *c.sdl.SDL_GPUDevice,
    usage: c.sdl.SDL_GPUBufferUsageFlags,
    size: u32,
) ?*c.sdl.SDL_GPUBuffer {
    const buffer_create_info = c.sdl.SDL_GPUBufferCreateInfo{
        .usage = usage,
        .size = size,
    };
    return c.sdl.SDL_CreateGPUBuffer(device, &buffer_create_info);
}

pub fn uploadToGPU(
    device: *c.sdl.SDL_GPUDevice,
    copy_pass: *c.sdl.SDL_GPUCopyPass,
    transfer_buffer: *c.sdl.SDL_GPUTransferBuffer,
    buffer_offset: u32,
    comptime T: type,
    data: []const T,
    buffer: *c.sdl.SDL_GPUBuffer,
) !void {
    const total_size: u32 = @intCast(@sizeOf(T) * data.len);

    // Map the buffer memory
    const transfer_data = c.sdl.SDL_MapGPUTransferBuffer(device, transfer_buffer, false) orelse {
        std.log.err("SDL_MapGPUTransferBuffer Failed (upload_cmdbuf)", .{});
        return error.MapFailed;
    };

    // Cast the pointer to bytes and copy the data at the specified offset
    const transfer_bytes = @as([*]u8, @ptrCast(transfer_data));
    @memcpy(transfer_bytes[buffer_offset .. buffer_offset + total_size], @as([*]const u8, @ptrCast(data.ptr)));

    c.sdl.SDL_UnmapGPUTransferBuffer(device, transfer_buffer);

    const transfer_buffer_location = c.sdl.SDL_GPUTransferBufferLocation{
        .transfer_buffer = transfer_buffer,
        .offset = buffer_offset,
    };

    const buffer_region = c.sdl.SDL_GPUBufferRegion{
        .buffer = buffer,
        .offset = 0,
        .size = total_size,
    };

    c.sdl.SDL_UploadToGPUBuffer(copy_pass, &transfer_buffer_location, &buffer_region, false);
}
