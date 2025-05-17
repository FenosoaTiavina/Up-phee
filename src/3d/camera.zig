const std = @import("std");

const uph = @import("../uph.zig");

const zmath = uph.zmath;
const c = uph.clib;
const Types = uph.Types;

pub const ProjectionPrespective = struct {
    fov: f32,
    w: f32,
    h: f32,
    near: f32,
    far: f32,
    projection_matrix: Types.Mat4_f32 = undefined,
};

pub const ProjectionOrthographic = struct {
    w: f32,
    h: f32,
    near: f32,
    far: f32,
    projection_matrix: Types.Mat4_f32 = undefined,
};

const ProjectionTag = enum { ortho, prespective };

pub const MIN_FOV = 30;

pub const Projection = struct {
    procjetion: union(ProjectionTag) {
        ortho: ProjectionOrthographic,
        prespective: ProjectionPrespective,
    },

    pub fn create(projection_type: ProjectionTag, w: f32, h: f32, near: f32, far: f32, fov: ?f32) Projection {
        switch (projection_type) {
            .ortho => {
                return Projection{
                    .procjetion = .{
                        .ortho = ProjectionOrthographic{
                            .w = w,
                            .h = h,
                            .near = near,
                            .far = far,
                        },
                    },
                };
            },
            .prespective => {
                return Projection{
                    .procjetion = .{
                        .prespective = ProjectionPrespective{
                            .w = w,
                            .h = h,
                            .near = near,
                            .far = far,
                            .fov = if (fov != null and fov.? > MIN_FOV) std.math.degreesToRadians(fov.?) else std.math.degreesToRadians(70),
                        },
                    },
                };
            },
        }
    }

    pub fn getProjection(self: *Projection) Types.Mat4_f32 {
        switch (self.procjetion) {
            .ortho => |*o| {
                return zmath.orthographicRhGl(o.w, o.h, o.near, o.far);
            },
            .prespective => |*p| {
                return zmath.perspectiveFovRhGl(p.fov, p.w / p.h, p.near, p.far);
            },
        }
    }

    pub fn update(self: *Projection, w: f32, h: f32) void {
        switch (self.procjetion) {
            .ortho => |*o| {
                o.h = h;
                o.w = w;
            },
            .perspective => |*p| {
                p.h = h;
                p.w = w;
            },
        }
    }

    pub fn updateNearFar(self: *Projection, near: ?f32, far: ?f32) void {
        switch (self.procjetion) {
            .ortho => |*o| {
                o.near = if (near) near else o.near;
                o.far = if (far) far else o.far;
            },
            .perspective => |*p| {
                p.near = if (near) near else p.near;
                p.far = if (far) far else p.far;
            },
        }
    }

    pub fn updateFov(self: *Projection, fov: ?f32) void {
        switch (self.procjetion) {
            .prespective => |*p| {
                p.fov = if (fov != null and fov.? > MIN_FOV) std.math.degreesToRadians(fov.?) else std.math.degreesToRadians(70);
            },
            .ortho => {
                @compileError("orthogonal camera does not have fov");
            },
        }
    }
};

pub const Camera = struct {
    position: Types.Vec3_f32,
    front: Types.Vec3_f32,
    up: Types.Vec3_f32,
    world_up: Types.Vec3_f32,
    right: Types.Vec3_f32,
    yaw: f32,
    pitch: f32,
    roll: f32,

    // Movement properties
    max_speed: f32,
    acceleration: f32,
    deceleration: f32,
    current_velocity: Types.Vec3_f32, // Current velocity vector for smooth movement

    sensitivity: f32,
    aspect: f32,

    view_matrix: Types.Mat4_f32,
    projection: Projection,
};

pub fn init(
    position: Types.Vec3_f32,
    target: Types.Vec3_f32,
    viewport_size: Types.Size,
    camera_type: ProjectionTag,
    near: f32,
    far: f32,
    fov: ?f32,
) Camera {
    const world_up = Types.Vec3_f32{ 0.0, 1.0, 0.0 };

    // Default front direction is -Z (OpenGL-style)

    // Calculate initial right vector
    const right = uph.Utils.Vec3.normalizeVec3(uph.Utils.Vec3.crossVec3(target, world_up));

    // Calculate initial up vector
    const up = uph.Utils.Vec3.normalizeVec3(uph.Utils.Vec3.crossVec3(right, target));

    var camera = Camera{
        .position = position,
        .front = target,
        .up = up,
        .world_up = world_up,
        .right = right,
        .yaw = 0.0,
        .pitch = 0.0,
        .roll = 0.0,
        .max_speed = 100.0,
        .acceleration = 100, // Units per second^2
        .deceleration = 80.0, // Faster deceleration for responsive stops
        .current_velocity = uph.Types.Vec3_f32{ 0.0, 0.0, 0.0 },
        .aspect = @as(f32, @floatFromInt(viewport_size.width)) / @as(f32, @floatFromInt(viewport_size.height)),
        .sensitivity = 0.1,
        .view_matrix = zmath.lookAtRh(uph.Utils.Vec3.vec3toVec4(position), uph.Utils.Vec3.vec3toVec4(position + target), uph.Utils.Vec3.vec3toVec4(up)),
        .projection = Projection.create(camera_type, @floatFromInt(viewport_size.width), @floatFromInt(viewport_size.height), near, far, fov),
    };

    // Initialize based on target position
    updateEuler(&camera);
    return camera;
}

pub fn move(camera: *Camera, direction: Types.Vec3_f32, dt: f32) void {
    // Calculate movement direction in camera space
    // Right vector (X axis in camera space)
    const rightMovement = camera.right * zmath.splat(Types.Vec3_f32, direction[0]);

    // Up vector - use camera's up vector for proper orientation
    const upMovement = camera.up * zmath.splat(Types.Vec3_f32, direction[1]);

    // Forward vector - use camera's front vector that includes both yaw and pitch
    // Get the current view front vector that includes pitch
    var view_front: Types.Vec3_f32 = Types.Vec3_f32{ 0, 0, 0 };
    view_front[0] = @sin(std.math.degreesToRadians(camera.yaw)) * @cos(std.math.degreesToRadians(camera.pitch));
    view_front[1] = @sin(std.math.degreesToRadians(camera.pitch));
    view_front[2] = @cos(std.math.degreesToRadians(camera.yaw)) * @cos(std.math.degreesToRadians(camera.pitch));
    view_front = uph.Utils.Vec3.normalizeVec3(view_front);

    const frontMovement = view_front * zmath.splat(Types.Vec3_f32, direction[2]);

    // Combine all movements to get the desired direction in world space
    const targetDirection = rightMovement + upMovement + frontMovement;

    // Calculate movement input magnitude (non-zero means user wants to move)
    const inputMagnitude = @abs(direction[0]) + @abs(direction[1]) + @abs(direction[2]);

    // Handle movement - simpler direct approach to reduce stuttering
    if (inputMagnitude > 0.001) {
        // User is providing input, accelerate toward target direction
        const targetLength = @sqrt(targetDirection[0] * targetDirection[0] +
            targetDirection[1] * targetDirection[1] +
            targetDirection[2] * targetDirection[2]);

        if (targetLength > 0.001) {
            // Normalize target direction
            const normalizedDir = targetDirection * zmath.splat(Types.Vec3_f32, 1.0 / targetLength);

            // Scale current speed - gradually approach max_speed
            var currentSpeed: f32 = 0.0;
            {
                const velocityLength = @sqrt(camera.current_velocity[0] * camera.current_velocity[0] +
                    camera.current_velocity[1] * camera.current_velocity[1] +
                    camera.current_velocity[2] * camera.current_velocity[2]);
                currentSpeed = velocityLength;
            }

            // Calculate target speed
            const targetSpeed = camera.max_speed;

            // Smoothly accelerate toward target speed
            if (currentSpeed < targetSpeed) {
                currentSpeed += camera.acceleration * dt;
                if (currentSpeed > targetSpeed) currentSpeed = targetSpeed;
            }

            // Apply the speed to the normalized direction
            camera.current_velocity = normalizedDir * zmath.splat(Types.Vec3_f32, currentSpeed);
        }
    } else {
        // No input, decelerate to zero
        const velocityLength = @sqrt(camera.current_velocity[0] * camera.current_velocity[0] +
            camera.current_velocity[1] * camera.current_velocity[1] +
            camera.current_velocity[2] * camera.current_velocity[2]);

        if (velocityLength > 0.001) {
            // Calculate deceleration
            const decelAmount = camera.deceleration * dt;

            if (decelAmount >= velocityLength) {
                // We would decelerate past zero, so just stop
                camera.current_velocity = Types.Vec3_f32{ 0, 0, 0 };
            } else {
                // Apply deceleration while maintaining direction
                const normalizedVel = camera.current_velocity * zmath.splat(Types.Vec3_f32, 1.0 / velocityLength);
                const newSpeed = velocityLength - decelAmount;
                camera.current_velocity = normalizedVel * zmath.splat(Types.Vec3_f32, newSpeed);
            }
        }
    }

    // Update position based on current velocity
    camera.position = camera.position + (camera.current_velocity * zmath.splat(Types.Vec3_f32, dt));

    update(camera);
}

pub inline fn updateResize(camera: *Camera, w: u32, h: u32) void {
    camera.aspect = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
    // Update view matrix
    updateEuler(camera);
}

// roation system
pub inline fn rotate(camera: *Camera, x: f32, y: f32, z: f32, constraint_pitch: bool) void {
    _ = z;
    const _x = -x;
    const _y = -y;

    rotateEuler(camera, _x, _y, constraint_pitch);
}

pub fn update(camera: *Camera) void {
    updateEuler(camera);
}

// ========== EULER ANGLES IMPLEMENTATION ==========

pub inline fn updateEuler(camera: *Camera) void {
    // Calculate front vector from yaw only (horizontal rotation)
    var front: Types.Vec3_f32 = Types.Vec3_f32{ 0, 0, 0 };
    front[0] = @sin(std.math.degreesToRadians(camera.yaw));
    front[1] = 0.0; // No vertical component from yaw/pitch for movement
    front[2] = @cos(std.math.degreesToRadians(camera.yaw));

    // Normalize front vector
    camera.front = uph.Utils.Vec3.normalizeVec3(front);

    // Calculate right vector as cross product of front and world_up
    camera.right = uph.Utils.Vec3.normalizeVec3(uph.Utils.Vec3.crossVec3(camera.front, camera.world_up));

    // Calculate up vector as cross product of right and front
    camera.up = uph.Utils.Vec3.normalizeVec3(uph.Utils.Vec3.crossVec3(camera.right, camera.front));

    // For the view matrix, we need the actual direction including pitch
    var view_front: Types.Vec3_f32 = Types.Vec3_f32{ 0, 0, 0 };
    view_front[0] = @sin(std.math.degreesToRadians(camera.yaw)) * @cos(std.math.degreesToRadians(camera.pitch));
    view_front[1] = @sin(std.math.degreesToRadians(camera.pitch));
    view_front[2] = @cos(std.math.degreesToRadians(camera.yaw)) * @cos(std.math.degreesToRadians(camera.pitch));

    view_front = uph.Utils.Vec3.normalizeVec3(view_front);

    // Update view matrix using the view_front vector that includes pitch
    const target = (camera.position + view_front);
    camera.view_matrix = zmath.lookAtRh(uph.Utils.Vec3.vec3toVec4(camera.position), uph.Utils.Vec3.vec3toVec4(target), uph.Utils.Vec3.vec3toVec4(camera.world_up));
}

pub inline fn rotateEuler(camera: *Camera, x: f32, y: f32, constraint_pitch: bool) void {
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
