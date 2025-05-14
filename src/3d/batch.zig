// create a batch:
//  VertexB
//  IndexB
//  index nums
//  pipeline handle

// Draw,
// Add to batch
// Batch pool

const std = @import("std");

const uph = @import("uph");

const c = @import("../imports.zig");
const Assets = @import("assets.zig");
const Objects = @import("objects.zig");

const MAX_VERTEX = 3 * 1024 * 1024;
pub const Batch = struct {
    gpu: Objects.MeshGPU,
    meshs: std.ArrayList(Objects.Mesh),
    base_index: u32 = 0,
    atlas: ?Assets.TextureData,
    pipeline_handle: u32,

    _ctx: uph.Context.Context,

    pub fn create(_ctx: *uph.Context.Context, pipeline_handle: u32) Batch {
        return .{
            .ctx = _ctx,
            .gpu = Objects.MeshGPU{
                .vbo = c.sdl.SDL_CreateGPUBuffer(
                    _ctx.renderer().device,
                    &c.sdl.SDL_GPUBufferCreateInfo{
                        .usage = c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
                        .size = MAX_VERTEX * @sizeOf(Objects.Vertex),
                    },
                ),
                .ibo = c.sdl.SDL_CreateGPUBuffer(
                    _ctx.renderer().device,
                    &c.sdl.SDL_GPUBufferCreateInfo{
                        .usage = c.sdl.SDL_GPU_BUFFERUSAGE_INDEX,
                        .size = MAX_VERTEX * @sizeOf(Objects.Index),
                    },
                ),
            },
            .pipeline_handle = pipeline_handle,
            .atlas = null,
            .meshs = std.ArrayList(Batch).init(_ctx.allocator()),
        };
    }

    pub fn add(self: *Batch, mesh: Objects.Mesh) !void {
        if (self.meshs.items.len == 0) {
            try self.meshs.append(mesh);
            self.base_index = mesh.num_indices - 1;
            return;
        }
        var tmp_idx = std.ArrayList(u32).init(self._ctx.allocator());
        for (mesh.indices, 0..mesh.indices.len) |idx, _| {
            try tmp_idx.append(idx + self.base_index);
        }

        try self.meshs.append(Objects.Mesh{
            .indices = tmp_idx.items,
            .num_indices = tmp_idx.items.len,
            .vertices = mesh.vertices,
        });
        self.base_index += mesh.vertices.len;
        tmp_idx.deinit();
    }
};
