const std = @import("std");

const uph = @import("../uph.zig");
const c = uph.clib;
const Objects = uph.uph_3d.Objects;
const Transform = uph.uph_3d.Transform;
const Types = uph.Types;

const cube_verts = [_]Objects.Vertex{
    .{ // f-bl
        .position = .{ -0.5, -0.5, -0.5 },
    },
    .{ // f-br
        .position = .{ 0.5, -0.5, -0.5 },
    },
    .{ // f-tl
        .position = .{ -0.5, 0.5, -0.5 },
    },
    .{ // f-tr
        .position = .{ 0.5, 0.5, -0.5 },
    },
    .{ // b-bl
        .position = .{ -0.5, -0.5, 0.5 },
    },
    .{ // b-br
        .position = .{ 0.5, -0.5, 0.5 },
    },
    .{ // b-tl
        .position = .{ -0.5, 0.5, 0.5 },
    },
    .{ // b-tr
        .position = .{ 0.5, 0.5, 0.5 },
    },
};
const cube_indices = [_]Objects.Index{
    //Top
    6, 7, 3,
    3, 2, 6,
    //Bottom
    1, 5, 4,
    4, 0, 1,
    //Right
    2, 0, 4,
    4, 6, 2,
    //Left
    5, 1, 3,
    3, 7, 5,
    //Back
    6, 4, 5,
    5, 7, 6,
    //Front
    1, 0, 2,
    1, 2, 3,
};

pub const Cube = struct {
    object: *Objects.ObjectInstanceManager,
    // object: *Objects.ObjectManager,
    ctx: uph.Context.Context,
    mesh: Objects.Mesh,

    pub fn init(ctx: uph.Context.Context, pipeline: u32, camera: *uph.uph_3d.Camera.Camera, max_cube_objects: u32) !*Cube {
        const _cube = try ctx.allocator().create(Cube);
        _cube.*.ctx = ctx;
        _cube.*.mesh = Objects.createMesh(&cube_verts, &cube_indices);
        // _cube.*.object = try Objects.ObjectManager.init(ctx, pipeline, camera, @intCast(cube_verts.len * max_cube_objects), @intCast(cube_indices.len * max_cube_objects));
        _cube.*.object = try Objects.ObjectInstanceManager.init(ctx, _cube.mesh, max_cube_objects, pipeline, camera);
        return _cube;
    }

    pub fn beginDraw(self: *Cube) !void {
        try self.object.beginDraw();
    }

    // pub fn draw(
    //     self: *Cube,
    // ) !void {
    //     try self.object.draw(self.mesh);
    // }

    pub fn draw(
        self: *Cube,
        trs: Transform.Transform,
        color: Types.Vec4_f32,
    ) !void {
        try self.object.draw(trs.model_matrix, color);
    }

    pub fn endDraw(self: *Cube) !void {
        try self.object.endDraw();
    }

    pub fn deinit(self: *Cube) void {
        self.object.deinit();
        self.ctx.allocator().destroy(self);
    }
};
