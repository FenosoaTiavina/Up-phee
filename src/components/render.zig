const std = @import("std");
const T_ = @import("../types.zig");

pub const UniformBufferObject = struct {
    model: T_.Mat4_f32,
    view: T_.Mat4_f32,
    projection: T_.Mat4_f32,
};
