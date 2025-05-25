const std = @import("std");
const uph = @import("../uph.zig");
const c = uph.clib;
const Renderer = uph.Renderer;
const Types = uph.Types;
const uph_3d = uph.uph_3d;

pub const Vertex = struct {
    position: Types.Vec3_f32,
    // uv: Types.Vec2_f32,
};

pub const Index = u16;

pub const Mesh = struct {
    vertices: []Vertex,
    indices: []Index,
};

pub const MeshGPU = struct {
    vbo: *c.sdl.SDL_GPUBuffer,
    ibo: *c.sdl.SDL_GPUBuffer,
};

pub fn createMeshGPU(device: *c.sdl.SDL_GPUDevice, vertex_max: u32, index_max: u32) MeshGPU {
    _ = &vertex_max; // autofix
    _ = &index_max; // autofix
    return MeshGPU{
        .vbo = uph.Buffer.createBuffer(
            device,
            c.sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
            @intCast(@sizeOf(Vertex) * vertex_max),
        ).?,
        .ibo = uph.Buffer.createBuffer(
            device,
            c.sdl.SDL_GPU_BUFFERUSAGE_INDEX,
            @intCast(@sizeOf(Vertex) * vertex_max),
        ).?,
    };
}

pub const UniformBufferObject = struct {
    model: Types.Mat4_f32,
    view: Types.Mat4_f32,
    projection: Types.Mat4_f32,
};

pub fn createMesh(vertices: []const Vertex, indices: []const u16) Mesh {
    return Mesh{
        .vertices = @constCast(vertices),
        .indices = @constCast(indices),
    };
}

pub const ObjectInstanceManager = struct {
    allocator: std.mem.Allocator,
    ctx: uph.Context.Context,

    mesh: Mesh,
    gpu_buffer: MeshGPU,

    max_object_number: u32,
    objects_count: u32,

    transforms: std.ArrayList(uph_3d.Transform),
    colors: std.ArrayList(Types.Vec4_f32),

    pipeline: u32,

    // textures: std.ArrayList(u64); array to handle of a bindless texture?

    pub fn init(ctx: uph.Context.Context, mesh: Mesh, allocaltor: std.mem.Allocator, max_objects_number: u32, pipeline: u32) !*ObjectInstanceManager {
        const obj_man = try allocaltor.create(ObjectInstanceManager);
        obj_man.*.ctx = ctx;
        obj_man.*.mesh = mesh;
        obj_man.*.gpu_buffer = createMeshGPU(ctx.renderer().device, @intCast(mesh.vertices.len), @intCast(mesh.indices.len));
        obj_man.*.max_object_number = max_objects_number;
        obj_man.*.allocator = allocaltor;
        obj_man.*.objects_count = 0;
        obj_man.*.transforms = std.ArrayList(Types.Mat4_f32).init(allocaltor);
        obj_man.*.colors = std.ArrayList(Types.Vec4_f32).init(allocaltor);
        obj_man.*.pipeline = pipeline;

        return obj_man;
    }

    fn beginBraw(self: *ObjectInstanceManager) void {
        _ = &self; // autofix
        // Bind Pipeline

    }

    fn Draw(
        self: *ObjectInstanceManager,
        transform: Types.Mat4_f32,
        color: Types.Vec4_f32,
    ) !void {
        if (self.max_object_number == self.max_object_number) {
            self.endDraw();
            self.beginBraw();
        }

        try self.transforms.append(transform);
        try self.colors.append(color);

        self.objects_count += 1;
    }

    fn endDraw(self: *ObjectInstanceManager) !void {
        _ = &self; // autofix

        // copy values to GPU buffer
        {
            const upload_cmd = try self.ctx.renderer().createRogueCommand();
            defer self.ctx.renderer().submitRogueCommand(upload_cmd);

            // bind color buffer?

        }

        // submit draw call
        {}

        // clear buffer & reset counter
        {
            self.transforms.clearRetainingCapacity;
            self.colors.clearRetainingCapacity();
            self.objects_count = 0;
        }
    }
};
