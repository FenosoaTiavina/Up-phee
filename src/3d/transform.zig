const zm = @import("zmath");

const T_ = @import("../types.zig");

pub const Transform = struct {
    position: T_.Vec4_f32,
    rotation: T_.Vec4_f32,
    scale: T_.Vec4_f32,
    model_matrix: T_.Mat4_f32,
};

pub fn init() Transform {
    return .{
        .position = .{ 0, 0, 0, 1 },
        .rotation = .{ 0, 0, 0, 1 },
        .scale = .{ 1, 1, 1, 1 },
        .model_matrix = zm.identity(),
    };
}

pub fn setPosition(self: *Transform, position: T_.Vec3_f32) void {
    self.position = position;
    updateModelMatrix(self);
}

pub fn setRotation(self: *Transform, rotation: T_.Vec3_f32) void {
    self.rotation = rotation;
    updateModelMatrix(self);
}

pub fn setScale(self: *Transform, scale: T_.Vec3_f32) void {
    self.scale = scale;
    updateModelMatrix(self);
}

pub fn rotate(self: *Transform, x: f32, y: f32, z: f32) void {
    self.rotation[0] += x;
    self.rotation[1] += y;
    self.rotation[2] += z;

    // Normalize rotations
    self.rotation[0] = @mod(self.rotation[0], 360.0);
    self.rotation[1] = @mod(self.rotation[1], 360.0);
    self.rotation[2] = @mod(self.rotation[2], 360.0);

    updateModelMatrix(self);
}

pub fn translate(self: *Transform, x: f32, y: f32, z: f32) void {
    self.position[0] += x;
    self.position[1] += y;
    self.position[2] += z;
    updateModelMatrix(self);
}

pub fn updateModelMatrix(transform: *Transform) void {
    // Create rotation matrix from Euler angles
    const rot_x = zm.rotationX(transform.rotation[0]);
    const rot_y = zm.rotationY(transform.rotation[1]);
    const rot_z = zm.rotationZ(transform.rotation[2]);

    // Combine rotations
    const rotation = zm.mul(zm.mul(rot_x, rot_y), rot_z);

    // Create scale matrix
    const scale = zm.scaling(transform.scale[0], transform.scale[1], transform.scale[2]);

    // Create translation matrix
    const translation = zm.translation(transform.position[0], transform.position[1], transform.position[2]);

    // Combine transformations: scale -> rotate -> translate
    transform.model_matrix = zm.mul(zm.mul(scale, rotation), translation);
}
