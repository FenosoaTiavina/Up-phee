// src/uph/uph3d/objects.zig
const std = @import("std");

const uph = @import("../uph.zig");
const c = uph.clib;
const sdl = c.sdl;
const Types = uph.Types;

// Assuming uph.zig exposes Renderer and other top-level modules
// For SDL_gpu types and functions
// Alias for c.sdl
// For Vec3_f32, Mat4_f32 etc.

// Vertex structure as defined in objects.txt [cite: 9]
pub const Vertex = struct {
    position: Types.Vec3_f32,
    // uv: Types.Vec2_f32, // Uncomment if you add UVs to your vertex data
    // color: Types.Vec4_f32, // Example: Add color if needed
};

// Index type as defined in objects.txt [cite: 10]
pub const Index = u16;

// CPU-side Mesh structure as defined in objects.txt [cite: 10]
pub const Mesh = struct {
    vertices: []const Vertex, // Changed to []const for safety
    indices: []const Index, // Changed to []const for safety
};

// --- GPUObjectPart Struct ---
// Defines a specific sub-range within the main GPUObject's vertex and index buffers.
// Each Renderable will reference one of these parts. This is crucial for shared buffers.
pub const GPUObjectPart = struct {
    /// The number of indices for this mesh part. If 0, it implies a non-indexed draw.
    index_count: u32,
    /// The byte offset into the main GPU index buffer where this part's indices begin.
    index_offset_bytes: u32,
    /// The number of vertices for this mesh part. Used for non-indexed drawing or vertex count.
    vertex_count: u32,
    /// The byte offset into the main GPU vertex buffer where this part's vertices begin.
    vertex_offset_bytes: u32,
};

// --- GPUObject Struct (Corrected from GPUObjet) ---
// Manages the main shared vertex and index buffers for the entire scene (or a large section).
// It also tracks individual mesh parts (GPUObjectPart) within these buffers.
// This is the core of your batching: all geometry in one place.
pub const GPUObject = struct {
    allocator: std.mem.Allocator,
    device: *sdl.SDL_GPUDevice, // The GPU device, needed for creating/destroying buffers

    /// The main GPU buffer holding all vertex data for all meshes combined.
    gpu_vertex_buffer: *c.sdl.SDL_GPUBuffer, // [cite: 11]
    current_vertex_offset: u32, // Track current end offset for new meshes
    /// The main GPU buffer holding all index data for all meshes combined.
    gpu_index_buffer: *c.sdl.SDL_GPUBuffer, // [cite: 11]
    current_index_offset: u32, // Track current end offset for new meshes

    /// An ArrayList of GPUObjectPart definitions.
    /// Each entry describes a specific mesh (or part of a complex model)
    /// by its offsets and counts within the global vertex and index buffers.
    parts: std.ArrayList(GPUObjectPart),

    pub const Error = error{
        BufferCreationFailed,
        BufferUpdateFailed,
        EmptyMesh, // [cite: 18]
        CopyPassFailed, // [cite: 20]
        RogueCommandFailed, // For createRogueCommand and submitRogueCommand
    };

    /// Initializes a GPUObject, creating its main vertex and index buffers.
    /// These buffers are initially empty and will be populated by 'appendMesh'.
    ///
    /// Parameters:
    ///   allocator: The standard Zig allocator.
    ///   device: The SDL_GPUDevice to create buffers on.
    ///   max_vertices: Total capacity for vertices in the main buffer.
    ///   max_indices: Total capacity for indices in the main buffer.
    pub fn init(
        allocator: std.mem.Allocator,
        device: *sdl.SDL_GPUDevice,
        max_vertices: u32,
        max_indices: u32,
    ) !GPUObject {
        // --- Create Vertex Buffer ---
        var vertex_buffer_desc = sdl.SDL_GPUBufferCreateInfo{
            .usage = sdl.SDL_GPU_BUFFERUSAGE_VERTEX | sdl.SDL_GPU_BUFFERUSAGE_COPY_DST,
            .size = max_vertices * @sizeOf(Vertex),
        };
        const gpu_vertex_buffer = sdl.SDL_CreateGPUBuffer(device, &vertex_buffer_desc) orelse {
            std.log.err("Failed to create vertex buffer: {s}", .{sdl.SDL_GetError()});
            return Error.BufferCreationFailed;
        };

        // --- Create Index Buffer ---
        var index_buffer_desc = sdl.SDL_GPUBufferCreateInfo{
            .usage = sdl.SDL_GPU_BUFFERUSAGE_INDEX | sdl.SDL_GPU_BUFFERUSAGE_COPY_DST,
            .size = max_indices * @sizeOf(Index),
        };
        const gpu_index_buffer = sdl.SDL_CreateGPUBuffer(device, &index_buffer_desc) orelse {
            std.log.err("Failed to create index buffer: {s}", .{sdl.SDL_GetError()});
            sdl.SDL_ReleaseGPUBuffer(gpu_vertex_buffer); // Clean up previous buffer
            return Error.BufferCreationFailed;
        };

        return GPUObject{
            .allocator = allocator,
            .device = device,
            .gpu_vertex_buffer = gpu_vertex_buffer,
            .gpu_index_buffer = gpu_index_buffer,
            .current_vertex_offset = 0,
            .current_index_offset = 0,
            .parts = std.ArrayList(GPUObjectPart).init(allocator),
        };
    }

    /// Deinitializes the GPUObject, freeing its internal ArrayList and destroying GPU buffers.
    pub fn deinit(self: *GPUObject) void {
        self.parts.deinit();
        if (self.gpu_vertex_buffer) {
            sdl.SDL_ReleaseGPUBuffer(self.gpu_vertex_buffer); // [cite: 16]
            self.gpu_vertex_buffer = null;
        }
        if (self.gpu_index_buffer) {
            sdl.SDL_ReleaseGPUBuffer(self.gpu_index_buffer); // [cite: 17]
            self.gpu_index_buffer = null;
        }
    }

    /// Appends a new Mesh's data to the GPUObject's main buffers.
    /// This function uploads the mesh data and creates a new GPUObjectPart.
    ///
    /// Parameters:
    ///   renderer_ctx: Reference to your global Renderer.RenderManager for command buffer/transfer buffer.
    ///   mesh: The CPU-side Mesh data to upload.
    ///
    /// Returns: The index of the newly added GPUObjectPart. This index should be stored in a Renderable.
    pub fn appendMesh(
        self: *GPUObject,
        renderer_ctx: *uph.Renderer.RenderManager,
        mesh: Mesh,
    ) !u32 {
        if (mesh.vertices.len == 0 and mesh.indices.len == 0) {
            return Error.EmptyMesh; // [cite: 18]
        }

        // Get a rogue command buffer for immediate upload [cite: 19]
        const upload_cmd = try renderer_ctx.createRogueCommand(); // Assumes Renderer has createRogueCommand

        // Begin copy pass for uploading data to GPU [cite: 20]
        const copy_pass = sdl.SDL_BeginGPUCopyPass(upload_cmd.command_buffer) orelse {
            std.log.err("Failed to begin copy pass: {s}", .{sdl.SDL_GetError()});
            return Error.CopyPassFailed;
        };

        // Upload vertices
        if (mesh.vertices.len > 0) {
            // Assumes Renderer has uploadToGPU helper
            // This needs to be 'renderer_ctx.transfer_buffer' if it's a member of RenderManager
            // Or passed in. For now, let's assume `renderer_ctx` provides a temp transfer buffer
            const transfer_buffer = try renderer_ctx.getTransferBuffer(); // Assuming this exists
            defer renderer_ctx.releaseTransferBuffer(transfer_buffer); // Assuming this exists

            try uph.Renderer.uploadToGPU( // [cite: 24]
                self.device,
                copy_pass,
                transfer_buffer, // Needs to be a valid SDL_GPUTransferBuffer
                self.current_vertex_offset,
                Vertex, // Data type
                mesh.vertices,
                self.gpu_vertex_buffer,
            );
        }

        // Upload indices
        if (mesh.indices.len > 0) {
            // Assumes Renderer has uploadToGPU helper
            const transfer_buffer = try renderer_ctx.getTransferBuffer(); // Assuming this exists
            defer renderer_ctx.releaseTransferBuffer(transfer_buffer); // Assuming this exists

            try uph.Renderer.uploadToGPU( // [cite: 25]
                self.device,
                copy_pass,
                transfer_buffer, // Needs to be a valid SDL_GPUTransferBuffer
                self.current_index_offset,
                Index, // Data type
                mesh.indices,
                self.gpu_index_buffer,
            );
        }

        // End copy pass [cite: 26]
        sdl.SDL_EndGPUCopyPass(copy_pass);

        // Create and add a new GPUObjectPart
        const part = GPUObjectPart{
            .index_count = @intCast(mesh.indices.len),
            .index_offset_bytes = self.current_index_offset,
            .vertex_count = @intCast(mesh.vertices.len),
            .vertex_offset_bytes = self.current_vertex_offset,
        };
        const part_idx = self.parts.items.len;
        try self.parts.append(part);

        // Update offsets for the next mesh
        self.current_vertex_offset += @intCast(mesh.vertices.len * @sizeOf(Vertex)); // [cite: 26] (corrected)
        self.current_index_offset += @intCast(mesh.indices.len * @sizeOf(Index));

        renderer_ctx.submitRogueCommand(upload_cmd) catch |err| {
            std.log.err("Failed to submit rogue command for mesh upload: {s}", .{err});
            return err;
        };

        return @intCast(part_idx);
    }
};

// Helper for creating Mesh from slices (from objects.txt) [cite: 29]
pub fn createMesh(vertices: []const Vertex, indices: []const Index) Mesh { // [cite: 29]
    return Mesh{
        .vertices = vertices, // @constCast not needed if input is already const
        .indices = indices,
    };
}

// Example of a global UniformBufferObject [cite: 28]
pub const GlobalUniformData = struct {
    view_proj_matrix: Types.Mat4_f32,
    // Add other global shader data here, e.g.:
    // camera_position: Types.Vec3_f32,
    // light_direction: Types.Vec3_f32,
};

// The Renderable struct now refers to a GPUObjectPart index [cite: 27]
pub const Renderable = struct {
    /// Index into `GPUObject.parts` list. This specifies the mesh geometry.
    gpu_object_part_idx: u32,
    /// Flag indicating if this renderable typically uses transparency.
    is_transparent: bool, // Used for layer submission and sorting
    // NOTE: `trs: uph3d.Transform` is removed from Renderable [cite: 27]
    // because transform is per-instance and goes into LayerDrawCommand.
};
