const std = @import("std");
const c = @import("../imports.zig");

const zm = @import("zmath");

const T_ = @import("../types.zig");

pub const CameraData = struct {
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
};

pub fn init(position: [3]f32, target: [3]f32, aspect: f32) CameraData {
    const pos = T_.Vec4_f32{ position[0], position[1], position[2], 1.0 };
    const tar = T_.Vec4_f32{ target[0], target[1], target[2], 1.0 };
    const up = T_.Vec4_f32{ 0.0, 1.0, 0.0, 0.0 };

    var camera = CameraData{
        .position = pos,
        .up = up,
        .world_up = up,
        .yaw = 0,
        .pitch = 0,
        .roll = 0,
        .front = zm.normalize3(tar - pos),
        .right = zm.normalize3(zm.cross3(zm.normalize3(tar - pos), up)),
        .speed = 1,
        .aspect = aspect,
        .sensitivity = 0.5,
        .view_matrix = zm.lookAtRh(pos, tar, up),
        .projection_matrix = zm.perspectiveFovRh(
            std.math.degreesToRadians(45.0),
            aspect,
            0.1,
            100.0,
        ),
    };
    update(&camera);
    return camera;
}

// Include the rest of your Camera methods here...
pub fn update(camera: *CameraData) void {
    var front: T_.Vec4_f32 = T_.Vec4_f32{ 0, 0, 0, 0 };
    front[0] = @cos(std.math.degreesToRadians(camera.yaw)) * @cos(std.math.degreesToRadians(camera.pitch));
    front[1] = @sin(std.math.degreesToRadians(camera.pitch));
    front[2] = @sin(std.math.degreesToRadians(camera.yaw)) * @cos(std.math.degreesToRadians(camera.pitch));

    camera.front = zm.normalize4(front);
    camera.*.right = zm.normalize4(zm.cross3(camera.front, camera.world_up));
    camera.*.up = zm.normalize4(zm.cross3(camera.right, camera.front));

    camera.*.view_matrix = zm.lookAtRh(camera.position, camera.position + camera.front, camera.up);
}

pub fn updateResize(camera: *CameraData, aspect: f32) void {
    camera.*.projection_matrix = zm.perspectiveFovRh(
        std.math.degreesToRadians(45.0),
        aspect,
        0.1,
        100.0,
    );
    update(camera);
}

pub fn move(camera: *CameraData, vec_move_amount: T_.Vec3_f32) void {
    // Create movement vectors based on camera's local coordinate system
    const rightMovement = camera.right * zm.splat(T_.Vec4_f32, vec_move_amount[0]);
    const upMovement = camera.up * zm.splat(T_.Vec4_f32, vec_move_amount[1]);
    const frontMovement = camera.front * zm.splat(T_.Vec4_f32, vec_move_amount[2]);

    // Combine movements in all directions
    const movement = rightMovement + upMovement + frontMovement;

    // Update position
    camera.position = camera.position + movement;

    // Update view matrix
    update(camera);
}

pub fn rotate(camera: *CameraData, x: f32, y: f32, z: f32, constraint_picth: bool) void {
    const _x = camera.sensitivity * x;
    const _y = camera.sensitivity * y;
    const _z = camera.sensitivity * z;

    camera.*.yaw += _x;
    camera.*.pitch += _y;
    camera.*.roll += _z;

    if (constraint_picth) {
        if (camera.*.pitch > 89.0)
            camera.*.pitch = 89.0;
        if (camera.*.pitch < -89.0)
            camera.*.pitch = -89.0;
    }
    update(camera);
}

pub fn handleCameraInput(camera: *CameraData, delta_time: f32) void {
    const keyboard_state = c.sdl.SDL_GetKeyboardState(null);

    // Initialize movement vector to zero
    var movement = T_.Vec3_f32{ 0.0, 0.0, 0.0 };

    // Add movement components based on key presses
    if (keyboard_state[c.sdl.SDL_SCANCODE_W]) movement[2] += 1.0;
    if (keyboard_state[c.sdl.SDL_SCANCODE_S]) movement[2] -= 1.0;
    if (keyboard_state[c.sdl.SDL_SCANCODE_D]) movement[0] += 1.0;
    if (keyboard_state[c.sdl.SDL_SCANCODE_A]) movement[0] -= 1.0;
    if (keyboard_state[c.sdl.SDL_SCANCODE_SPACE]) movement[1] += 1.0;
    if (keyboard_state[c.sdl.SDL_SCANCODE_LSHIFT]) movement[1] -= 1.0;

    // Only proceed if there's any movement
    if (movement[0] != 0.0 or movement[1] != 0.0 or movement[2] != 0.0) {
        // Calculate length of the movement vector
        const length_squared = movement[0] * movement[0] +
            movement[1] * movement[1] +
            movement[2] * movement[2];
        // Normalize only if length is not 1 (diagonal movement)
        if (length_squared > 1.0001) {
            const length = @sqrt(length_squared);
            movement[0] /= length;
            movement[1] /= length;
            movement[2] /= length;
        }
        // Scale movement by delta time and speed
        const scaled_movement = T_.Vec3_f32{
            movement[0] * delta_time * camera.speed,
            movement[1] * delta_time * camera.speed,
            movement[2] * delta_time * camera.speed,
        };
        // Apply movement to camera
        move(camera, scaled_movement);
    }
}
