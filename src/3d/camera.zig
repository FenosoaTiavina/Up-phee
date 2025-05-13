const std = @import("std");
const c = @import("../imports.zig");

const zm = @import("zmath");

const T_ = @import("../types.zig");

pub const Camera = struct {
    position: T_.Vec4_f32,
    front: T_.Vec4_f32,
    up: T_.Vec4_f32,
    world_up: T_.Vec4_f32,
    right: T_.Vec4_f32,
    yaw: f32,
    pitch: f32,
    roll: f32,
    speed: f32,
    sensitivity: f32,
    aspect: f32,

    view_matrix: T_.Mat4_f32,

    projection_matrix: T_.Mat4_f32,

    // Field to choose movement system
    use_quaternion: bool,
    // Quaternion for rotation representation
    rotation_quat: zm.Quat,
};

pub fn init(
    position: [3]f32,
    target: [3]f32,
    aspect: f32,
    use_quaternion: bool,
) Camera {
    const pos = T_.Vec4_f32{ position[0], position[1], position[2], 1.0 };
    const tar = T_.Vec4_f32{ target[0], target[1], target[2], 1.0 };
    _ = tar; // autofix

    const world_up = T_.Vec4_f32{ 0.0, 1.0, 0.0, 0.0 };

    // Default front direction is -Z (OpenGL-style)
    const default_front = T_.Vec4_f32{ 0.0, 0.0, 1.0, 0.0 };

    // Calculate initial right vector
    const right = zm.normalize3(zm.cross3(default_front, world_up));

    // Calculate initial up vector
    const up = zm.normalize3(zm.cross3(right, default_front));

    var camera = Camera{
        .position = pos,
        .front = default_front,
        .up = up,
        .world_up = world_up,
        .right = right,
        .yaw = 0.0,
        .pitch = 0.0,
        .roll = 0.0,
        .speed = 0.5,
        .aspect = aspect,
        .sensitivity = 0.1,
        .view_matrix = zm.lookAtRh(pos, (pos + default_front), up),
        .projection_matrix = zm.perspectiveFovRh(
            std.math.degreesToRadians(45.0),
            aspect,
            0.1,
            100.0,
        ),
        .use_quaternion = use_quaternion,
        .rotation_quat = zm.qidentity(),
    };

    // Initialize based on target position
    if (use_quaternion) {
        updateQuaternion(&camera);
    } else {
        updateEuler(&camera);
    }

    return camera;
}

pub fn updateResize(camera: *Camera, aspect: f32) void {
    camera.aspect = aspect;
    camera.projection_matrix = zm.perspectiveFovRh(
        std.math.degreesToRadians(45.0),
        aspect,
        0.1,
        100.0,
    );

    // Update view matrix
    if (camera.use_quaternion) {
        updateQuaternion(
            camera,
        );
    } else {
        updateEuler(camera);
    }
}

pub fn move(camera: *Camera, vec_move_amount: T_.Vec3_f32) void {
    // Constrain movement to horizontal plane and vertical axes
    // Right vector (X axis in camera space)
    const rightMovement = (T_.Vec4_f32{ camera.right[0], 0.0, camera.right[2], 0.0 } * zm.f32x4(vec_move_amount[0], vec_move_amount[0], vec_move_amount[0], 0.0));

    // Up is world up (Y axis in world space)
    const upMovement = (T_.Vec4_f32{ 0.0, 1.0, 0.0, 0.0 } * zm.f32x4(vec_move_amount[1], vec_move_amount[1], vec_move_amount[1], 0.0));

    // Front vector (Z axis in camera space) projected to horizontal plane
    const frontMovement = (T_.Vec4_f32{ camera.front[0], 0.0, camera.front[2], 0.0 } * zm.f32x4(vec_move_amount[2], vec_move_amount[2], vec_move_amount[2], 0.0));

    // Normalize the horizontal front vector if not zero
    const frontLength = @sqrt(frontMovement[0] * frontMovement[0] + frontMovement[2] * frontMovement[2]);
    const normalizedFrontMovement = if (frontLength > 0.001)
        (frontMovement * zm.splat(T_.Vec4_f32, 1.0 / frontLength))
    else
        frontMovement;

    // Combine all movements
    const movement = ((rightMovement + upMovement) + normalizedFrontMovement);

    // Update position - ensure W component remains 1.0
    camera.position = zm.f32x4(camera.position[0] + movement[0], camera.position[1] + movement[1], camera.position[2] + movement[2], 1.0);
    update(camera);
}

// Unified rotate function that delegates to the appropriate implementation
pub fn rotate(camera: *Camera, x: f32, y: f32, z: f32, constraint_pitch: bool) void {
    // Ignore roll (z) as per requirements
    _ = z;

    const _x = -x;
    const _y = -y;

    if (camera.use_quaternion) {
        rotateQuaternion(camera, _x, _y, constraint_pitch);
    } else {
        rotateEuler(camera, _x, _y, constraint_pitch);
    }
}

pub fn update(camera: *Camera) void {
    if (camera.use_quaternion) {
        updateQuaternion(camera);
    } else {
        updateEuler(camera);
    }
}

// ========== EULER ANGLES IMPLEMENTATION ==========

pub fn updateEuler(camera: *Camera) void {
    // Calculate front vector from yaw only (horizontal rotation)
    var front: T_.Vec4_f32 = T_.Vec4_f32{ 0, 0, 0, 0 };
    front[0] = @sin(std.math.degreesToRadians(camera.yaw));
    front[1] = 0.0; // No vertical component from yaw/pitch for movement
    front[2] = @cos(std.math.degreesToRadians(camera.yaw));
    front[3] = 0.0;

    // Normalize front vector
    camera.front = zm.normalize3(front);

    // Calculate right vector as cross product of front and world_up
    camera.right = zm.normalize3(zm.cross3(camera.front, camera.world_up));
    camera.right[3] = 0.0;

    // Calculate up vector as cross product of right and front
    camera.up = zm.normalize3(zm.cross3(camera.right, camera.front));
    camera.up[3] = 0.0;

    // For the view matrix, we need the actual direction including pitch
    var view_front: T_.Vec4_f32 = T_.Vec4_f32{ 0, 0, 0, 0 };
    view_front[0] = @sin(std.math.degreesToRadians(camera.yaw)) * @cos(std.math.degreesToRadians(camera.pitch));
    view_front[1] = @sin(std.math.degreesToRadians(camera.pitch));
    view_front[2] = @cos(std.math.degreesToRadians(camera.yaw)) * @cos(std.math.degreesToRadians(camera.pitch));
    view_front[3] = 0.0;

    view_front = zm.normalize3(view_front);

    // Update view matrix using the view_front vector that includes pitch
    const target = (camera.position + view_front);
    camera.view_matrix = zm.lookAtRh(camera.position, target, camera.world_up);
}

pub fn rotateEuler(camera: *Camera, x: f32, y: f32, constraint_pitch: bool) void {
    const _x = camera.sensitivity * x;
    const _y = camera.sensitivity * y;

    camera.yaw += _x;
    camera.pitch += _y;

    // Normalize yaw to [0, 360]
    camera.yaw = @mod(camera.yaw, 360.0);

    // Constrain pitch if requested
    if (constraint_pitch) {
        if (camera.pitch > 89.0)
            camera.pitch = 89.0;
        if (camera.pitch < -89.0)
            camera.pitch = -89.0;
    }

    update(camera);
}

// ========== QUATERNION IMPLEMENTATION ==========

pub fn updateQuaternion(camera: *Camera) void {
    // Convert quaternion to rotation matrix
    const rotation_matrix = zm.matFromQuat(camera.rotation_quat);

    // Extract basis vectors from rotation matrix
    // Forward is negative Z in standard coordinate system
    const forward = zm.f32x4(rotation_matrix[2][0], rotation_matrix[2][1], rotation_matrix[2][2], 0.0);
    const right = zm.f32x4(rotation_matrix[0][0], rotation_matrix[0][1], rotation_matrix[0][2], 0.0);
    const up = zm.f32x4(rotation_matrix[1][0], rotation_matrix[1][1], rotation_matrix[1][2], 0.0);

    // Store the vectors in camera data
    camera.front = forward;
    camera.right = right;
    camera.up = up;

    // For movement, we want horizontal vectors
    const horizontal_front = zm.f32x4(forward[0], 0.0, forward[2], 0.0);
    camera.front = zm.normalize3(horizontal_front);

    // Update view matrix
    const target = (camera.position + forward);
    camera.view_matrix = zm.lookAtRh(camera.position, target, camera.world_up);
}

pub fn rotateQuaternion(camera: *Camera, x: f32, y: f32, constraint_pitch: bool) void {
    const _x = camera.sensitivity * x;
    const _y = camera.sensitivity * y;

    // Create quaternions for yaw (around Y axis) and pitch (around X axis)
    const yaw_quat = zm.quatFromAxisAngle(zm.f32x4(0.0, 1.0, 0.0, 0.0), std.math.degreesToRadians(_x));
    const pitch_quat = zm.quatFromAxisAngle(zm.f32x4(1.0, 0.0, 0.0, 0.0), std.math.degreesToRadians(-_y));

    // Apply rotations to the current quaternion
    // Order matters: first apply pitch around local X, then yaw around world Y
    var new_quat = zm.qmul(pitch_quat, camera.rotation_quat);
    new_quat = zm.qmul(yaw_quat, new_quat);

    // Normalize quaternion to prevent drift
    camera.rotation_quat = new_quat;

    // Handle pitch constraint if needed
    if (constraint_pitch) {
        // Extract the pitch angle from the quaternion
        const forward = zm.rotate(camera.rotation_quat, zm.f32x4(0.0, 0.0, 1.0, 0.0));
        const pitch = std.math.asin(forward[1]) * (180.0 / std.math.pi);

        // If pitch exceeds limits, constrain it
        if (pitch > 89.0 or pitch < -89.0) {
            // Convert back to Euler angles
            var euler = quatToEuler(camera.rotation_quat);

            // Constrain pitch
            if (euler[1] > 89.0) euler[1] = 89.0;
            if (euler[1] < -89.0) euler[1] = -89.0;

            // Convert back to quaternion
            camera.rotation_quat = eulerToQuat(euler[0], euler[1], euler[2]);
        }
    }

    update(camera);
}

fn quatToEuler(q: zm.Quat) [3]f32 {
    // Convert quaternion to Euler angles (yaw, pitch, roll) in degrees
    const yaw = std.math.atan2(2.0 * (q[0] * q[1] + q[2] * q[3]), 1.0 - 2.0 * (q[1] * q[1] + q[2] * q[2])) * (180.0 / std.math.pi);

    const pitch = std.math.asin(std.math.clamp(2.0 * (q[0] * q[2] - q[3] * q[1]), -1.0, 1.0)) * (180.0 / std.math.pi);

    const roll = std.math.atan2(2.0 * (q[0] * q[3] + q[1] * q[2]), 1.0 - 2.0 * (q[2] * q[2] + q[3] * q[3])) * (180.0 / std.math.pi);

    return [3]f32{ yaw, pitch, roll };
}

fn eulerToQuat(yaw: f32, pitch: f32, roll: f32) zm.Quat {
    // Convert Euler angles in degrees to quaternion
    const cy = @cos(std.math.degreesToRadians(yaw * 0.5));
    const sy = @sin(std.math.degreesToRadians(yaw * 0.5));
    const cp = @cos(std.math.degreesToRadians(pitch * 0.5));
    const sp = @sin(std.math.degreesToRadians(pitch * 0.5));
    const cr = @cos(std.math.degreesToRadians(roll * 0.5));
    const sr = @sin(std.math.degreesToRadians(roll * 0.5));

    return zm.f32x4(cy * cp * cr + sy * sp * sr, cy * cp * sr - sy * sp * cr, cy * sp * cr + sy * cp * sr, sy * cp * cr - cy * sp * sr);
}
