const zm = @import("zmath");

const ecs = @import("ecs");
const T_ = @import("uph").Types;

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
