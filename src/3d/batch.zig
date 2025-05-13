const std = @import("std");

const zmath = @import("zmath");

const c = @import("../imports.zig");
const Renderer = @import("../renderer.zig");
const T_ = @import("../types.zig");
const Camera = @import("camera.zig");
const Vertex = @import("mesh.zig").Vertex;
const Index = @import("mesh.zig").Index;

const Self = @This();

const MAX_VERTICES = 65536;
const MAX_INDICES = 65536;

allocator: std.mem.Allocator,
renderer: *Renderer.Renderer,
camera: *Camera.Camera,

vbo: *c.sdl.SDL_GPUBuffer,
ibo: *c.sdl.SDL_GPUBuffer,

pipeline_handle: u32,
vertices: std.ArrayList(Vertex),
indices: std.ArrayList(Index),

pub fn init(
    allocator: std.mem.Allocator,
    renderer: *Renderer.Renderer,
    pipeline_id: u32,
    camera: *Camera.Camera,
) !Self {
    const vbo = Renderer.createBuffer(renderer.device, c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX, MAX_VERTICES * @sizeOf(Vertex)) orelse return error.VBOCreateFailed;
    const ibo = Renderer.createBuffer(renderer.device, c.sdl.SDL_GPU_BUFFERUSAGE_INDEX, MAX_INDICES * @sizeOf(u32)) orelse return error.IBOCreateFailed;

    return Self{
        .allocator = allocator,
        .renderer = renderer,
        .camera = camera,
        .vbo = vbo,
        .ibo = ibo,
        .pipeline_handle = pipeline_id,
        .vertices = std.ArrayList(Vertex).init(allocator),
        .indices = std.ArrayList(Index).init(allocator),
    };
}

pub fn addMesh(self: *Self, verts: []const Vertex, inds: []const Index) void {
    const base_index: u16 = @intCast(self.vertices.items.len);
    self.vertices.appendSlice(verts) catch return;
    for (inds) |i| self.indices.append(base_index + i) catch return;
}

pub fn draw(self: *Self) !void {
    // Skip drawing if there's nothing to draw
    if (self.vertices.items.len == 0 or self.indices.items.len == 0) {
        return;
    }

    const command_buffer = self.renderer.command_buffers.items[self.renderer.command_buffers.items.len - 1];
    const g_pipeline = try self.renderer.getPipeline(self.pipeline_handle);

    // First, perform GPU uploads in a copy pass
    const copy_pass = c.sdl.SDL_BeginGPUCopyPass(command_buffer) orelse {
        return error.CopyPassCreationFailed;
    };

    try Renderer.uploadToGPU(
        self.renderer.device,
        copy_pass,
        self.renderer.transfer_buffer,
        0,
        Vertex,
        self.vertices.items,
        self.vbo,
    );
    try Renderer.uploadToGPU(
        self.renderer.device,
        copy_pass,
        self.renderer.transfer_buffer,
        0,
        Index,
        self.indices.items,
        self.ibo,
    );

    c.sdl.SDL_EndGPUCopyPass(copy_pass);

    // Then, after the copy pass is complete, start a render pass
    const render_pass = c.sdl.SDL_BeginGPURenderPass(command_buffer, &self.renderer.target_info, 1, null) orelse {
        return error.RenderPassCreationFailed;
    };

    // Bind the pipeline
    c.sdl.SDL_BindGPUGraphicsPipeline(render_pass, g_pipeline);

    // Bind and draw only if we have vertices and indices
    const vertex_buffer = c.sdl.SDL_GPUBufferBinding{
        .buffer = self.vbo,
        .offset = 0,
    };
    const index_buffer = c.sdl.SDL_GPUBufferBinding{
        .buffer = self.ibo,
        .offset = 0,
    };

    c.sdl.SDL_BindGPUVertexBuffers(render_pass, 0, &vertex_buffer, 1);

    c.sdl.SDL_BindGPUIndexBuffer(render_pass, &index_buffer, c.sdl.SDL_GPU_INDEXELEMENTSIZE_32BIT);

    // Add debug output
    std.debug.print("Drawing {d} indices with {d} vertices\n", .{ self.indices.items.len, self.vertices.items.len });

    // Draw the primitives
    c.sdl.SDL_DrawGPUIndexedPrimitives(
        render_pass,
        @intCast(self.indices.items.len), // total indices to draw
        1, // instance count (1 for now)
        0, // first index
        0, // vertex offset
        0, // first instance
    );

    c.sdl.SDL_EndGPURenderPass(render_pass);

    // Clear for next frame
    self.vertices.clearRetainingCapacity();
    self.indices.clearRetainingCapacity();
}

pub fn deinit(self: *Self) void {
    self.vertices.deinit();
    self.indices.deinit();
    c.sdl.SDL_ReleaseGPUBuffer(self.renderer.device, self.vbo);
    c.sdl.SDL_ReleaseGPUBuffer(self.renderer.device, self.ibo);
}
