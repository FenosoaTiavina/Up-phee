const std = @import("std");

const zm = @import("zmath");

const Types = @import("../types.zig");

pub const Transform = struct {
    position: Types.Vec3_f32 = .{ 0, 0, 0 },
    rotation: Types.Vec3_f32 = .{ 0, 0, 0 },
    scale: Types.Vec3_f32 = .{ 1, 1, 1 },
    model_matrix: Types.Mat4_f32 = undefined,

    pub fn init() Transform {
        var transform = Transform{};
        transform.model_matrix = zm.identity();
        return transform;
    }

    pub fn setPosition(self: *Transform, position: Types.Vec3_f32) void {
        self.position = position;
        self.updateModelMatrix();
    }

    pub fn setRotation(self: *Transform, rotation: Types.Vec3_f32) void {
        self.rotation = rotation;
        self.updateModelMatrix();
    }

    pub fn setScale(self: *Transform, scale: Types.Vec3_f32) void {
        self.scale = scale;
        self.updateModelMatrix();
    }

    pub fn rotate(self: *Transform, x: f32, y: f32, z: f32) void {
        self.rotation[0] += x;
        self.rotation[1] += y;
        self.rotation[2] += z;

        // Normalize rotations
        self.rotation[0] = @mod(self.rotation[0], 360.0);
        self.rotation[1] = @mod(self.rotation[1], 360.0);
        self.rotation[2] = @mod(self.rotation[2], 360.0);

        self.updateModelMatrix();
    }

    pub fn translate(self: *Transform, x: f32, y: f32, z: f32) void {
        self.position[0] += x;
        self.position[1] += y;
        self.position[2] += z;
        self.updateModelMatrix();
    }

    pub fn updateModelMatrix(self: *Transform) void {
        // Create rotation matrices from Euler angles (convert to radians)
        const rot_x = zm.rotationX(self.rotation[0] * (std.math.pi / 180.0));
        const rot_y = zm.rotationY(self.rotation[1] * (std.math.pi / 180.0));
        const rot_z = zm.rotationZ(self.rotation[2] * (std.math.pi / 180.0));

        // Combine rotations
        const rotation = zm.mul(zm.mul(rot_x, rot_y), rot_z);

        // Create scale matrix
        const scale = zm.scaling(self.scale[0], self.scale[1], self.scale[2]);

        // Create translation matrix
        const translation = zm.translation(self.position[0], self.position[1], self.position[2]);

        // Combine transformations: Model = Scale * Rotation * Translation
        // First scale, then rotate, then translate
        self.model_matrix = zm.mul(zm.mul(scale, rotation), translation);
    }
};
