// src/uph/renderer/layer.zig
const std = @import("std");
const c = @import("../imports.zig");
const sdl = c.sdl;

const uph = @import("../uph.zig");
const Types = uph.Types;
const uph3d = uph.uph3d;
const Objects = uph3d.Objects; // To access GPUObject, GPUObjectPart, Renderable
const Renderable = Objects.Renderable;
pub const Layer = struct {
    allocator: std.mem.Allocator,
    device: *sdl.SDL_GPUDevice,
    pipeline: *sdl.SDL_GPUGraphicsPipeline, // Graphics pipeline specific to this layer
    is_transparent: bool, // Flag to determine depth sorting order

    // This object typically holds all combined vertex/index buffer data for the scene.
    gpu_buffer: *Objects.GPUObject,

    // Global Uniform Buffer (e.g., for View/Projection matrices).
    // This buffer is owned and updated by a higher-level renderer (e.g., RenderManager),
    // and Layer holds a reference to it to bind it.
    global_ubo: *sdl.SDL_GPUBuffer,
    global_ubo_binding_slot: u32,

    // Instance Uniform Buffer (e.g., for Model matrices, colors per object).
    // This buffer is owned by a higher-level renderer, and Layer updates it
    // and binds it per-draw call.
    instance_ubo: *sdl.SDL_GPUBuffer,
    instance_ubo_binding_slot: u32,

    // The list of drawing instructions collected for this frame.
    draw_commands: std.ArrayList(LayerDrawCommand),

    // This struct holds the data for a single draw call within this layer.
    pub const LayerDrawCommand = struct {
        /// Index into the global `App.all_renderables` array.
        renderable_index: u32,

        /// The final model matrix for this specific instance.
        model_matrix: Types.Mat4_f32,

        /// Color tint for this instance.
        color_tint: Types.Vec4_f32 = .{ 1.0, 1.0, 1.0, 1.0 },

        /// A pointer to the texture used for this draw command.
        texture_ptr: ?*c.sdl.SDL_GPUTexture,

        /// Z-depth for sorting.
        depth: f32,

        // Define the structure of the instance data that goes into the instance_ubo.
        // This must match the layout expected by your shader.
        pub const InstanceData = struct {
            model_matrix: Types.Mat4_f32,
            color_tint: Types.Vec4_f32,
        };

        // --- Context for Sorting ---
        pub const SortContext = struct {
            all_renderables: []const Renderable, // Reference the updated Renderable
            main_gpu_object_parts: []const Objects.GPUObjectPart, // Access parts directly for sorting
            is_transparent_layer: bool,
        };

        /// Comparison function for sorting LayerDrawCommand instances.
        pub fn compare(comptime T: type, context: SortContext, a: T, b: T) std.sort.Order {
            const a_texture_addr = if (a.texture_ptr) |t| @as(usize, @ptrFromInt(t)) else 0;
            const b_texture_addr = if (b.texture_ptr) |t| @as(usize, @ptrFromInt(t)) else 0;

            if (a_texture_addr < b_texture_addr) return std.sort.Order.Ascending;
            if (a_texture_addr > b_texture_addr) return std.sort.Order.Descending;

            const renderable_a = &context.all_renderables[a.renderable_index];
            const renderable_b = &context.all_renderables[b.renderable_index];

            if (renderable_a.gpu_object_part_idx < renderable_b.gpu_object_part_idx) return std.sort.Order.Ascending;
            if (renderable_a.gpu_object_part_idx > renderable_b.gpu_object_part_idx) return std.sort.Order.Descending;

            if (context.is_transparent_layer) {
                if (a.depth < b.depth) return std.sort.Order.Descending;
                if (a.depth > b.depth) return std.sort.Order.Ascending;
            } else {
                if (a.depth < b.depth) return std.sort.Order.Ascending;
                if (a.depth > b.depth) return std.sort.Order.Descending;
            }
            return std.sort.Order.Equal;
        }
    };

    // --- Layer Initialization ---
    // Corrected `init` signature to match usage and new members
    pub fn init(
        allocator: std.mem.Allocator,
        device: *sdl.SDL_GPUDevice,
        pipeline: *sdl.SDL_GPUGraphicsPipeline,
        shared_gpu_object: *Objects.GPUObject,
        global_ubo: *sdl.SDL_GPUBuffer,
        global_ubo_binding_slot: u32,
        instance_ubo: *sdl.SDL_GPUBuffer,
        instance_ubo_binding_slot: u32,
        is_transparent: bool,
    ) !Layer {
        return Layer{
            .allocator = allocator,
            .device = device,
            .pipeline = pipeline,
            .gpu_buffer = shared_gpu_object,
            .global_ubo = global_ubo,
            .global_ubo_binding_slot = global_ubo_binding_slot,
            .instance_ubo = instance_ubo,
            .instance_ubo_binding_slot = instance_ubo_binding_slot,
            .is_transparent = is_transparent,
            .draw_commands = std.ArrayList(LayerDrawCommand).init(allocator),
        };
    }

    // --- Layer Deinitialization ---
    pub fn deinit(self: *Layer) void {
        self.draw_commands.deinit();
    }

    // --- Add a Drawing Command ---
    // The `LayerDrawCommand` is the primary way to submit render requests.
    pub fn add_command(self: *Layer, command: LayerDrawCommand) !void {
        try self.draw_commands.append(command);
    }

    // --- Draw Function (Core Rendering Logic for the Layer) ---
    // The `draw` function now takes `all_renderables` as a slice,
    // to look up `Renderable` data (like `gpu_object_part_idx`).
    pub fn draw() void {}
};
