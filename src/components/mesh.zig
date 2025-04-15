const std = @import("std");

const T_ = @import("../types.zig");

const c = @import("../imports.zig");

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

pub const TextureData = struct {
    texture: ?*c.sdl.SDL_GPUTexture,
    sampler: ?*c.sdl.SDL_GPUSampler,
};
