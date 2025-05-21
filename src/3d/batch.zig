const std = @import("std");
const uph = @import("../uph.zig");
const Objects = uph.uph3d.Objects;
const Assets = uph.uph3d.Assets;
const Transform = uph.uph3d.Transform;
const c = uph.clib;

// Debug mode - set to false for production
const DEBUG = false;

// Maximum vertex count - adjust based on your needs

pub const BatchError = error{
    NullRenderPass,
    EmptyBatch,
    BufferUploadFailed,
    InvalidIndexCount,
    RenderingFailed,
};

pub const Batch = struct {
    gpu: Objects.GPUObject,

    meshes: std.ArrayList(*Objects.Mesh),

    base_index: u16 = 0,
    pipeline_handle: u32,
    camera: *uph.uph3d.Camera.Camera = undefined,
    transfer_buffer: *c.sdl.SDL_GPUTransferBuffer,
    draw_cmd_buf: u32,
    upload_cmd_buf: u32,
    ctx: uph.Context.Context,
    primitive_type: c.sdl.SDL_GPUPrimitiveType = c.sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,

    pub fn init(ctx: uph.Context.Context, pipeline_handle: u32, camera: *uph.uph3d.Camera.Camera, max_objects: u32) !*Batch {
        _ = ctx; // autofix
        _ = pipeline_handle; // autofix
        _ = camera; // autofix
        _ = max_objects; // autofix
    }

    pub fn deinit(self: *Batch) void {
        _ = self; // autofix
    }

    pub fn draw(self: *Batch, delta_t: f32) !void {
        _ = self; // autofix
        _ = delta_t; // autofix
    }
    pub fn add(self: *Batch, mesh: Objects.Mesh) !void {
        _ = self; // autofix
        _ = mesh; // autofix
    }

    pub fn clear(self: *Batch) void {
        _ = self; // autofix
    }
};
