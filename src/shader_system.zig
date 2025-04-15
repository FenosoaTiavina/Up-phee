const std = @import("std");

const c = @import("../imports.zig");

const ecs = @import("ecs");
const T_ = @import("./types.zig");

// Shader stage flags
pub const ShaderStageFlags = struct {
    pub const VERTEX: u32 = 1 << 0;
    pub const FRAGMENT: u32 = 1 << 1;
    pub const COMPUTE: u32 = 1 << 2;
    pub const RAYGEN: u32 = 1 << 3;
    pub const ANY_HIT: u32 = 1 << 4;
    pub const CLOSEST_HIT: u32 = 1 << 5;
    pub const MISS: u32 = 1 << 6;
    pub const INTERSECTION: u32 = 1 << 7;
};

// Shader resource binding description
pub const ShaderResourceBinding = struct {
    binding: u32,
    set: u32 = 0,
    resource_type: enum {
        UniformBuffer,
        StorageBuffer,
        Sampler,
        StorageImage,
        AccelerationStructure,
    },
    stage_flags: u32,
    count: u32 = 1,
};

// Shader source information
pub const ShaderSource = struct {
    allocator: std.mem.Allocator,
    path: ?[]const u8 = null,
    code: ?[]const u8 = null,
    entry_point: []const u8 = "main",
    stage: c.sdl.SDL_GPUShaderStage,

    pub fn init(allocator: std.mem.Allocator) ShaderSource {
        return .{
            .allocator = allocator,
            .path = null,
            .code = null,
            .entry_point = "main",
            .stage = c.sdl.SDL_GPU_SHADERSTAGE_VERTEX,
        };
    }

    pub fn deinit(self: *ShaderSource) void {
        if (self.path) |path| {
            self.allocator.free(path);
        }
        if (self.code) |code| {
            self.allocator.free(code);
        }
    }

    pub fn fromPath(allocator: std.mem.Allocator, path: []const u8, stage: c.sdl.SDL_GPUShaderStage) !ShaderSource {
        var source = ShaderSource.init(allocator);
        source.path = try allocator.dupe(u8, path);
        source.stage = stage;
        return source;
    }

    pub fn fromCode(allocator: std.mem.Allocator, code: []const u8, stage: c.sdl.SDL_GPUShaderStage) !ShaderSource {
        var source = ShaderSource.init(allocator);
        source.code = try allocator.dupe(u8, code);
        source.stage = stage;
        return source;
    }
};

// Shader component
pub const ShaderComponent = struct {
    allocator: std.mem.Allocator,
    sources: std.ArrayList(ShaderSource),
    resources: std.ArrayList(ShaderResourceBinding),
    compiled_shaders: std.StringHashMap(*c.sdl.SDL_GPUShader),
    shader_format: c.sdl.SDL_GPUShaderFormat,

    pub fn typeId() u32 {
        return 1005; // Unique ID for shader component
    }

    pub fn init(allocator: std.mem.Allocator) ShaderComponent {
        return .{
            .allocator = allocator,
            .sources = std.ArrayList(ShaderSource).init(allocator),
            .resources = std.ArrayList(ShaderResourceBinding).init(allocator),
            .compiled_shaders = std.StringHashMap(*c.sdl.SDL_GPUShader).init(allocator),
            .shader_format = c.sdl.SDL_GPU_SHADERFORMAT_SPIRV,
        };
    }

    pub fn deinit(self: *ShaderComponent) void {
        for (self.sources.items) |*source| {
            source.deinit();
        }
        self.sources.deinit();
        self.resources.deinit();

        var it = self.compiled_shaders.iterator();
        while (it.next()) |entry| {
            _ = entry; // autofix
            // Note: GPU shaders will be released by the renderer
        }
        self.compiled_shaders.deinit();
    }

    pub fn addSource(self: *ShaderComponent, source: ShaderSource) !void {
        try self.sources.append(source);
    }

    pub fn addResource(self: *ShaderComponent, binding: u32, resource_type: enum {
        UniformBuffer,
        StorageBuffer,
        Sampler,
        StorageImage,
        AccelerationStructure,
    }, stage_flags: u32) !void {
        try self.resources.append(.{
            .binding = binding,
            .set = 0,
            .resource_type = resource_type,
            .stage_flags = stage_flags,
            .count = 1,
        });
    }

    pub fn compileShaders(self: *ShaderComponent, device: *c.sdl.SDL_GPUDevice) !void {
        for (self.sources.items) |source| {
            var code_ptr: [*c]const u8 = undefined;
            var code_size: usize = 0;
            var code_needs_free = false;

            if (source.path) |path| {
                // Load from file
                const loaded_code = c.sdl.SDL_LoadFile(path.ptr, &code_size) orelse {
                    return error.ShaderFileLoadFailed;
                };
                code_ptr = @ptrCast(loaded_code);
                code_needs_free = true;
            } else if (source.code) |code| {
                // Use provided code
                code_ptr = code.ptr;
                code_size = code.len;
            } else {
                return error.NoShaderSourceProvided;
            }

            var uniform_count: u32 = 0;
            var storage_count: u32 = 0;
            var sampler_count: u32 = 0;
            var storage_texture_count: u32 = 0;

            // Count resources for this shader stage
            for (self.resources.items) |resource| {
                if (resource.stage_flags & getShaderStageFlagFromSDL(source.stage) == 0) {
                    continue;
                }

                switch (resource.resource_type) {
                    .UniformBuffer => uniform_count += 1,
                    .StorageBuffer => storage_count += 1,
                    .Sampler => sampler_count += 1,
                    .StorageImage => storage_texture_count += 1,
                    .AccelerationStructure => storage_count += 1, // Acceleration structures use storage buffers
                }
            }

            const shader_info = c.sdl.SDL_GPUShaderCreateInfo{
                .code = code_ptr,
                .code_size = code_size,
                .entrypoint = source.entry_point.ptr,
                .format = self.shader_format,
                .stage = source.stage,
                .num_samplers = sampler_count,
                .num_uniform_buffers = uniform_count,
                .num_storage_buffers = storage_count,
                .num_storage_textures = storage_texture_count,
            };

            const shader = c.sdl.SDL_CreateGPUShader(device, &shader_info) orelse {
                if (code_needs_free) {
                    c.sdl.SDL_free(@constCast(code_ptr));
                }
                std.log.err("SDL_CreateGPUShader failed: {s}\n", .{c.sdl.SDL_GetError()});
                return error.ShaderCompilationFailed;
            };

            // Store shader with stage info as key
            const stage_str = try std.fmt.allocPrint(self.allocator, "{d}", .{source.stage});
            defer self.allocator.free(stage_str);

            try self.compiled_shaders.put(stage_str, shader);

            if (code_needs_free) {
                c.sdl.SDL_free(@constCast(code_ptr));
            }
        }
    }

    fn getShaderStageFlagFromSDL(stage: c.sdl.SDL_GPUShaderStage) u32 {
        return switch (stage) {
            c.sdl.SDL_GPU_SHADERSTAGE_VERTEX => ShaderStageFlags.VERTEX,
            c.sdl.SDL_GPU_SHADERSTAGE_FRAGMENT => ShaderStageFlags.FRAGMENT,
            c.sdl.SDL_GPU_SHADERSTAGE_COMPUTE => ShaderStageFlags.COMPUTE,
            c.sdl.SDL_GPU_SHADERSTAGE_RAYGEN => ShaderStageFlags.RAYGEN,
            c.sdl.SDL_GPU_SHADERSTAGE_ANY_HIT => ShaderStageFlags.ANY_HIT,
            c.sdl.SDL_GPU_SHADERSTAGE_CLOSEST_HIT => ShaderStageFlags.CLOSEST_HIT,
            c.sdl.SDL_GPU_SHADERSTAGE_MISS => ShaderStageFlags.MISS,
            c.sdl.SDL_GPU_SHADERSTAGE_INTERSECTION => ShaderStageFlags.INTERSECTION,
            else => 0,
        };
    }
};

// Pipeline types
pub const PipelineType = enum {
    Graphics,
    Compute,
    RayTracing,
};

// Base pipeline component
pub const PipelineComponent = struct {
    allocator: std.mem.Allocator,
    pipeline_type: PipelineType,
    // We'll store the actual pipeline reference here when created
    pipeline: ?*c.sdl.SDL_GPUGraphicsPipeline = null,
    compute_pipeline: ?*c.sdl.SDL_GPUComputePipeline = null,
    ray_pipeline: ?*c.sdl.SDL_GPURaytracingPipeline = null,

    pub fn typeId() u32 {
        return 1006; // Unique ID for pipeline component
    }

    pub fn init(allocator: std.mem.Allocator, pipeline_type: PipelineType) PipelineComponent {
        return .{
            .allocator = allocator,
            .pipeline_type = pipeline_type,
            .pipeline = null,
            .compute_pipeline = null,
            .ray_pipeline = null,
        };
    }

    pub fn deinit(self: *PipelineComponent, device: *c.sdl.SDL_GPUDevice) void {
        if (self.pipeline) |pipeline| {
            c.sdl.SDL_ReleaseGPUGraphicsPipeline(device, pipeline);
        }

        if (self.compute_pipeline) |pipeline| {
            c.sdl.SDL_ReleaseGPUComputePipeline(device, pipeline);
        }

        if (self.ray_pipeline) |pipeline| {
            c.sdl.SDL_ReleaseGPURaytracingPipeline(device, pipeline);
        }
    }
};

// Graphics pipeline component
pub const GraphicsPipelineComponent = struct {
    base: PipelineComponent,
    vertex_layout: ?VertexLayout = null,
    rasterizer_state: c.sdl.SDL_GPURasterizerState = .{
        .fill_mode = c.sdl.SDL_GPU_FILLMODE_FILL,
        .cull_mode = c.sdl.SDL_GPU_CULLMODE_BACK,
        .front_face = c.sdl.SDL_GPU_FRONTFACE_CCW,
        .depth_bias = 0.0,
        .depth_bias_clamp = 0.0,
        .depth_bias_slope_factor = 0.0,
        .line_width = 1.0,
    },
    depth_stencil_state: c.sdl.SDL_GPUDepthStencilState = .{
        .depth_test_enabled = true,
        .depth_write_enabled = true,
        .depth_compare_op = c.sdl.SDL_GPU_COMPAREOP_LESS,
        .stencil_test_enabled = false,
        .stencil_front = .{
            .fail_op = c.sdl.SDL_GPU_STENCILOP_KEEP,
            .depth_fail_op = c.sdl.SDL_GPU_STENCILOP_KEEP,
            .pass_op = c.sdl.SDL_GPU_STENCILOP_KEEP,
            .compare_op = c.sdl.SDL_GPU_COMPAREOP_ALWAYS,
            .compare_mask = 0xFF,
            .write_mask = 0xFF,
            .reference = 0,
        },
        .stencil_back = .{
            .fail_op = c.sdl.SDL_GPU_STENCILOP_KEEP,
            .depth_fail_op = c.sdl.SDL_GPU_STENCILOP_KEEP,
            .pass_op = c.sdl.SDL_GPU_STENCILOP_KEEP,
            .compare_op = c.sdl.SDL_GPU_COMPAREOP_ALWAYS,
            .compare_mask = 0xFF,
            .write_mask = 0xFF,
            .reference = 0,
        },
    },
    blend_state: c.sdl.SDL_GPUBlendState = .{
        .enabled = false,
        .src_color_blend_factor = c.sdl.SDL_GPU_BLENDFACTOR_ONE,
        .dst_color_blend_factor = c.sdl.SDL_GPU_BLENDFACTOR_ZERO,
        .color_blend_op = c.sdl.SDL_GPU_BLENDOP_ADD,
        .src_alpha_blend_factor = c.sdl.SDL_GPU_BLENDFACTOR_ONE,
        .dst_alpha_blend_factor = c.sdl.SDL_GPU_BLENDFACTOR_ZERO,
        .alpha_blend_op = c.sdl.SDL_GPU_BLENDOP_ADD,
        .color_write_mask = c.sdl.SDL_GPU_COLORCOMPONENTFLAG_R | c.sdl.SDL_GPU_COLORCOMPONENTFLAG_G | c.sdl.SDL_GPU_COLORCOMPONENTFLAG_B | c.sdl.SDL_GPU_COLORCOMPONENTFLAG_A,
    },
    primitive_type: c.sdl.SDL_GPUPrimitiveType = c.sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
    shader_entity: ecs.EntityId = 0,
    shader_component: ?*ShaderComponent = null,

    pub fn typeId() u32 {
        return 1007; // Unique ID for graphics pipeline component
    }

    pub fn init(allocator: std.mem.Allocator) GraphicsPipelineComponent {
        return .{
            .base = PipelineComponent.init(allocator, PipelineType.Graphics),
        };
    }

    pub fn deinit(self: *GraphicsPipelineComponent, device: *c.sdl.SDL_GPUDevice) void {
        self.base.deinit(device);

        if (self.vertex_layout) |*layout| {
            layout.deinit();
        }
    }

    pub fn setBlending(self: *GraphicsPipelineComponent, enabled: bool) void {
        self.blend_state.enabled = enabled;

        if (enabled) {
            // Default alpha blending
            self.blend_state.src_color_blend_factor = c.sdl.SDL_GPU_BLENDFACTOR_SRC_ALPHA;
            self.blend_state.dst_color_blend_factor = c.sdl.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA;
            self.blend_state.src_alpha_blend_factor = c.sdl.SDL_GPU_BLENDFACTOR_ONE;
            self.blend_state.dst_alpha_blend_factor = c.sdl.SDL_GPU_BLENDFACTOR_ZERO;
        }
    }

    pub fn setDepthTest(self: *GraphicsPipelineComponent, enabled: bool) void {
        self.depth_stencil_state.depth_test_enabled = enabled;
        self.depth_stencil_state.depth_write_enabled = enabled;
    }

    pub fn setWireframe(self: *GraphicsPipelineComponent, enabled: bool) void {
        self.rasterizer_state.fill_mode = if (enabled) c.sdl.SDL_GPU_FILLMODE_LINE else c.sdl.SDL_GPU_FILLMODE_FILL;
    }

    pub fn setCullMode(self: *GraphicsPipelineComponent, cull_mode: c.sdl.SDL_GPUCullMode) void {
        self.rasterizer_state.cull_mode = cull_mode;
    }

    pub fn setPrimitiveType(self: *GraphicsPipelineComponent, primitive_type: c.sdl.SDL_GPUPrimitiveType) void {
        self.primitive_type = primitive_type;
    }

    pub fn createPipeline(self: *GraphicsPipelineComponent, device: *c.sdl.SDL_GPUDevice, window: *c.sdl.SDL_Window, registry: *ecs.Registry) !void {
        _ = registry; // autofix
        if (self.shader_entity == 0 or self.shader_component == null) {
            return error.NoShaderSpecified;
        }

        // Get shaders
        const shader_comp = self.shader_component.?;

        // Find vertex shader
        const vertex_shader = shader_comp.compiled_shaders.get(try std.fmt.allocPrint(shader_comp.allocator, "{d}", .{c.sdl.SDL_GPU_SHADERSTAGE_VERTEX})) orelse return error.VertexShaderNotFound;

        // Find fragment shader
        const fragment_shader = shader_comp.compiled_shaders.get(try std.fmt.allocPrint(shader_comp.allocator, "{d}", .{c.sdl.SDL_GPU_SHADERSTAGE_FRAGMENT})) orelse return error.FragmentShaderNotFound;

        var vertex_buffer_desc = c.sdl.SDL_GPUVertexBufferDescription{
            .slot = 0,
            .pitch = 0,
            .input_rate = c.sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
        };

        var vertex_attributes = std.ArrayList(c.sdl.SDL_GPUVertexAttribute).init(self.base.allocator);
        defer vertex_attributes.deinit();

        if (self.vertex_layout) |*layout| {
            vertex_buffer_desc.pitch = layout.stride;

            for (layout.attributes.items) |attr| {
                try vertex_attributes.append(.{
                    .location = attr.location,
                    .buffer_slot = 0,
                    .format = attr.format,
                    .offset = attr.offset,
                });
            }
        } else {
            // Default vertex layout (position, color, uv)
            vertex_buffer_desc.pitch = @sizeOf(T_.Vec3_f32) + @sizeOf(T_.Vec4_f32) + @sizeOf(T_.Vec2_f32);

            try vertex_attributes.append(.{
                .location = 0,
                .buffer_slot = 0,
                .format = c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                .offset = 0,
            });

            try vertex_attributes.append(.{
                .location = 1,
                .buffer_slot = 0,
                .format = c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
                .offset = @sizeOf(T_.Vec3_f32),
            });

            try vertex_attributes.append(.{
                .location = 2,
                .buffer_slot = 0,
                .format = c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                .offset = @sizeOf(T_.Vec3_f32) + @sizeOf(T_.Vec4_f32),
            });
        }

        // Get swapchain format
        const swapchain_format = c.sdl.SDL_GetGPUSwapchainTextureFormat(device, window);

        const color_target_descriptions = c.sdl.SDL_GPUColorTargetDescription{
            .format = swapchain_format,
        };

        const pipeline_info = c.sdl.SDL_GPUGraphicsPipelineCreateInfo{
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
            .vertex_input_state = .{
                .vertex_buffer_descriptions = &vertex_buffer_desc,
                .num_vertex_buffers = 1,
                .vertex_attributes = vertex_attributes.items.ptr,
                .num_vertex_attributes = @intCast(vertex_attributes.items.len),
            },
            .target_info = .{
                .num_color_targets = 1,
                .color_target_descriptions = &color_target_descriptions,
            },
            .primitive_type = self.primitive_type,
            .rasterizer_state = self.rasterizer_state,
            .depth_stencil_state = self.depth_stencil_state,
            .blend_state = self.blend_state,
        };

        const pipeline = c.sdl.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse {
            return error.PipelineCreationFailed;
        };

        self.base.pipeline = pipeline;
    }
};

// Vertex attribute definition
pub const VertexAttribute = struct {
    location: u32,
    format: c.sdl.SDL_GPUVertexElementFormat,
    offset: u32,
};

// Vertex layout definition
pub const VertexLayout = struct {
    allocator: std.mem.Allocator,
    attributes: std.ArrayList(VertexAttribute),
    stride: u32,

    pub fn init(allocator: std.mem.Allocator) VertexLayout {
        return .{
            .allocator = allocator,
            .attributes = std.ArrayList(VertexAttribute).init(allocator),
            .stride = 0,
        };
    }

    pub fn deinit(self: *VertexLayout) void {
        self.attributes.deinit();
    }

    pub fn addAttribute(self: *VertexLayout, location: u32, format: c.sdl.SDL_GPUVertexElementFormat, offset: u32) !void {
        try self.attributes.append(.{
            .location = location,
            .format = format,
            .offset = offset,
        });

        // Update stride based on the format
        const format_size = switch (format) {
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT => 4,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2 => 8,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3 => 12,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4 => 16,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_UINT => 4,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_UINT2 => 8,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_UINT3 => 12,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_UINT4 => 16,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_BYTE4 => 4,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_BYTE4N => 4,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4 => 4,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4N => 4,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_SHORT2 => 4,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_SHORT2N => 4,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_SHORT4 => 8,
            c.sdl.SDL_GPU_VERTEXELEMENTFORMAT_SHORT4N => 8,
            else => 0,
        };

        self.stride = std.math.max(self.stride, offset + format_size);
    }
};

// Compute pipeline component
pub const ComputePipelineComponent = struct {
    base: PipelineComponent,
    workgroup_size: [3]u32 = .{ 1, 1, 1 },
    shader_entity: ecs.EntityId = 0,
    shader_component: ?*ShaderComponent = null,

    pub fn typeId() u32 {
        return 1008; // Unique ID for compute pipeline component
    }

    pub fn init(allocator: std.mem.Allocator) ComputePipelineComponent {
        return .{
            .base = PipelineComponent.init(allocator, PipelineType.Compute),
        };
    }

    pub fn deinit(self: *ComputePipelineComponent, device: *c.sdl.SDL_GPUDevice) void {
        self.base.deinit(device);
    }

    pub fn setWorkgroupSize(self: *ComputePipelineComponent, x: u32, y: u32, z: u32) void {
        self.workgroup_size = .{ x, y, z };
    }

    pub fn createPipeline(self: *ComputePipelineComponent, device: *c.sdl.SDL_GPUDevice, registry: *ecs.Registry) !void {
        _ = registry; // autofix
        if (self.shader_entity == 0 or self.shader_component == null) {
            return error.NoShaderSpecified;
        }

        // Get shader
        const shader_comp = self.shader_component.?;

        // Find compute shader
        const compute_shader = shader_comp.compiled_shaders.get(try std.fmt.allocPrint(shader_comp.allocator, "{d}", .{c.sdl.SDL_GPU_SHADERSTAGE_COMPUTE})) orelse return error.ComputeShaderNotFound;

        const pipeline_info = c.sdl.SDL_GPUComputePipelineCreateInfo{
            .compute_shader = compute_shader,
        };

        const pipeline = c.sdl.SDL_CreateGPUComputePipeline(device, &pipeline_info) orelse {
            return error.PipelineCreationFailed;
        };

        self.base.compute_pipeline = pipeline;
    }

    pub fn dispatch(self: *ComputePipelineComponent, command_buffer: *c.sdl.SDL_GPUCommandBuffer, x: u32, y: u32, z: u32) !void {
        if (self.base.compute_pipeline == null) {
            return error.PipelineNotCreated;
        }

        const compute_pass = c.sdl.SDL_BeginGPUComputePass(command_buffer) orelse {
            return error.ComputePassCreationFailed;
        };

        c.sdl.SDL_BindGPUComputePipeline(compute_pass, self.base.compute_pipeline);
        c.sdl.SDL_DispatchGPUCompute(compute_pass, x, y, z);
        c.sdl.SDL_EndGPUComputePass(compute_pass);
    }
};

// Ray tracing pipeline component
pub const RayTracingPipelineComponent = struct {
    base: PipelineComponent,
    max_recursion_depth: u32 = 1,
    shader_entity: ecs.EntityId = 0,
    shader_component: ?*ShaderComponent = null,
    acceleration_structure: ?*c.sdl.SDL_GPUAccelerationStructure = null,

    pub fn typeId() u32 {
        return 1009; // Unique ID for ray tracing pipeline component
    }

    pub fn init(allocator: std.mem.Allocator) RayTracingPipelineComponent {
        return .{
            .base = PipelineComponent.init(allocator, PipelineType.RayTracing),
        };
    }

    pub fn deinit(self: *RayTracingPipelineComponent, device: *c.sdl.SDL_GPUDevice) void {
        self.base.deinit(device);

        if (self.acceleration_structure) |accel| {
            c.sdl.SDL_ReleaseGPUAccelerationStructure(device, accel);
        }
    }

    pub fn setMaxRecursionDepth(self: *RayTracingPipelineComponent, depth: u32) void {
        self.max_recursion_depth = depth;
    }

    pub fn createAccelerationStructure(
        self: *RayTracingPipelineComponent,
        device: *c.sdl.SDL_GPUDevice,
        // Add parameters for geometry data
    ) !void {
        _ = self; // autofix
        // TODO: Implement acceleration structure creation
        // This is a placeholder for now
        _ = device;
        return error.AccelerationStructureNotImplemented;
    }
};
