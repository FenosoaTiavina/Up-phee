const std = @import("std");

const c = @import("../imports.zig");
const uph = @import("../uph.zig");
const Renderer = uph.Renderer;
const Types = uph.Types;
const uph3d = uph.uph3d;
const Transform = uph3d.Transform;

pub const Layer = struct {
    ctx: *Renderer.RenderManager = undefined,

    gpu_buffer: uph3d.Objects.GPUObject = undefined,

    pipeline_handle: u32 = undefined,

    objects_handle: *anyopaque = undefined,
    objects_type: type = undefined,

    pub fn init(ctx: *Renderer.RenderManager, T: type) Layer {
        return .{ .ctx = ctx, .objects_type = T, .gpu_buffer = uph3d.Objects.c };
    }

    pub fn bind_objects_array(self: *Layer, objs_ptr: *anyopaque) void {
        const objects: *@typeInfo(self.objects_type).type = @ptrCast(@alignCast(objs_ptr));
        self.objects_handle = objects;
    }

    pub fn add_object() !void {}

    pub fn draw() void {}

    // NOTE:
    // - actual objects
    //  -? handle?array i don't know ,
    //      handle -> Global Object Array from game state?
    //      array -> local array for each Layer so multiple instance of the same
    //        object for same obejct & diff pipeline
    // - pipeline handle
    // - ..

    // TODO:
    // - Init , Deinit
    // - draw function
    // - bind objects/mesh to Layer
    // - ?Layer inter-dependecies
    // INFO:
    // Objects can bind to many layer -> multiple redraw:
    // wireframe layer?
    //

};
