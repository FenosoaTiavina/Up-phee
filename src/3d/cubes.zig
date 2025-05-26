const std = @import("std");

const uph = @import("../uph.zig");
const c = uph.clib;
const Objects = uph.uph_3d.Objects;
const Transform = uph.uph_3d.Transform;
const Types = uph.Types;

const cube_verts = [_]Objects.Vertex{
    .{
        // f-tl
        .position = .{ -0.5, 0.5, 0.5 },
        // .uv = .{ 0, 0 },
    },
    .{
        // f-tr
        .position = .{ 0.5, 0.5, 0.5 },
        // .uv = .{ 0, 1 },
    },
    .{
        // f-bl
        .position = .{ -0.5, -0.5, 0.5 },
        // .uv = .{ 1, 0 },
    },
    .{
        // f-br
        .position = .{ 0.5, -0.5, 0.5 },
        // .uv = .{ 1, 1 },
    },
    .{
        // b-tl
        .position = .{ -0.5, 0.5, -0.5 },
        // .uv = .{ 1, 1 },
    },
    .{
        // b-tr
        .position = .{ 0.5, 0.5, -0.5 },
        // .uv = .{ 0, 1 },
    },
    .{
        // b-bl
        .position = .{ -0.5, -0.5, -0.5 },
        // .uv = .{ 1, 0 },
    },
    .{
        // b-br
        .position = .{ 0.5, -0.5, -0.5 },
        // .uv = .{ 0, 0 },
    },
};
const cube_indices = [_]Objects.Index{
    //Top
    2, 6, 7,
    2, 3, 7,
    //Bottom
    0, 4, 5,
    0, 1, 5,
    //Left
    0, 2, 6,
    0, 4, 6,
    //Right
    1, 3, 7,
    1, 5, 7,
    //Front
    0, 2, 3,
    0, 1, 3,
    //Back
    4, 6, 7,
    4, 5, 7,
};

pub const Cube = struct {
    object: *Objects.ObjectInstanceManager,
    ctx: uph.Context.Context,
    mesh: Objects.Mesh,

    pub fn init(ctx: uph.Context.Context, pipeline: u32, camera: *uph.uph_3d.Camera.Camera, max_cube_objects: u32) !*Cube {
        const _cube = try ctx.allocator().create(Cube);
        _cube.*.ctx = ctx;
        _cube.*.mesh = Objects.createMesh(&cube_verts, &cube_indices);
        _cube.*.object = try Objects.ObjectInstanceManager.init(ctx, _cube.*.mesh, max_cube_objects, pipeline, camera);
        return _cube;
    }

    pub fn beginDraw(self: *Cube) !void {
        try self.object.beginDraw();
    }

    pub fn draw(
        self: *Cube,
        transform: Transform.Transform,
        color: Types.Vec4_f32,
    ) !void {
        _ = &transform; // autofix
        _ = &color; // autofix

        try self.object.draw(transform.model_matrix, color);
    }

    pub fn endDraw(self: *Cube) !void {
        try self.object.endDraw();
    }

    pub fn deinit(self: *Cube) void {
        self.object.deinit();
        self.ctx.allocator().destroy(self);
    }
};
