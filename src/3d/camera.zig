const std = @import("std");

const uph = @import("../uph.zig");

const zmath = uph.zmath;
const c = uph.clib;
const Types = uph.Types;

pub const ProjectionPrespective = struct {
    fov: f32,
    w: u32,
    h: u32,
    near: f32,
    far: f32,
    projection_matrix: Types.Mat4_f32 = undefined,
};

pub const ProjectionOrthographic = struct {
    w: u32,
    h: u32,
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

    pub fn create(projection_type: ProjectionTag, w: u32, h: u32, near: f32, far: f32, fov: ?f32) Projection {
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
                            .fov = if (fov != null) std.math.degreesToRadians(fov.?) else std.math.degreesToRadians(70),
                        },
                    },
                };
            },
        }
    }

    pub fn getProjection(self: *Projection) Types.Mat4_f32 {
        switch (self.procjetion) {
            .ortho => |*o| {
                return zmath.orthographicRhGl(@floatFromInt(o.w), @floatFromInt(o.h), o.near, o.far);
            },
            .prespective => |*p| {
                const aspect: f32 = @as(f32, @floatFromInt(p.w)) / @as(f32, @floatFromInt(p.h));
                return zmath.perspectiveFovRhGl(p.fov, aspect, p.near, p.far);
            },
        }
    }

    pub fn update(self: *Projection, w: u32, h: u32) void {
        switch (self.procjetion) {
            .ortho => |*o| {
                o.h = h;
                o.w = w;
            },
            .prespective => |*p| {
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
    position: Types.Vec3_f32 = Types.Vec3_f32{ 0, 0, -5 },

    rotation: Types.Vec3_f32 = Types.Vec3_f32{ 0, 0, 0 }, // Euler angles in radians: pitch, yaw, roll

    forward: Types.Vec3_f32 = Types.Vec3_f32{ 0, 0, 1 },

    projection: Projection,
    view_matrix: Types.Mat4_f32 = zmath.identity(),

    invert_mouse: bool = false,

    /// Movement speed in units per second
    move_speed: f32 = 100.0,
    /// Rotation speed in radians per second
    rotate_speed: f32 = 1.0,
};

pub fn init(projection: ProjectionTag, w: u32, h: u32, near: f32, far: f32, fov: ?f32) Camera {
    var cam = Camera{
        .projection = Projection.create(projection, w, h, near, far, fov),
    };
    updateViewMatrix(&cam);
    return cam;
}

pub fn getViewProjection(self: *Camera) Types.Mat4_f32 {
    return zmath.mul(self.projection.getProjection(), self.view_matrix);
}

pub fn updateViewMatrix(self: *Camera) void {
    const pitch = self.rotation[0];
    const yaw = self.rotation[1];

    const forward = zmath.normalize3(zmath.f32x4(
        @sin(yaw) * @cos(pitch),
        -@sin(pitch),
        @cos(yaw) * @cos(pitch),
        0.0,
    ));

    const target = uph.Utils.Vec3.vec3toVec4Zero(self.position) + forward;
    const up = zmath.f32x4(0, 1, 0, 0);

    self.view_matrix = zmath.lookAtRh(uph.Utils.Vec3.vec3toVec4(self.position), target, up);
}

pub fn move(camera: *Camera, direction: Types.Vec3_f32, dt: f32) void {
    const speed = zmath.f32x4s(camera.move_speed);
    const delta_time = zmath.f32x4s(dt);

    const pitch = camera.rotation[0];
    const yaw = camera.rotation[1];

    // Compute forward vector from yaw and pitch
    var forward = zmath.normalize3(zmath.f32x4(
        @sin(yaw) * @cos(pitch),
        -@sin(pitch),
        @cos(yaw) * @cos(pitch),
        0.0,
    ));

    zmath.storeArr3(&camera.forward, forward);

    const right = zmath.normalize3(zmath.cross3(forward, zmath.f32x4(0.0, 1.0, 0.0, 0.0)));

    forward = forward * speed * delta_time;
    const strafe = right * speed * delta_time;

    var cam_pos = zmath.loadArr3(camera.position);

    if (direction[2] > 0) {
        cam_pos += forward;
    } else if (direction[2] < 0) {
        cam_pos -= forward;
    }
    if (direction[0] > 0) {
        cam_pos -= strafe;
    } else if (direction[0] < 0) {
        cam_pos += strafe;
    }

    zmath.storeArr3(&camera.position, cam_pos);
}

pub fn rotate(camera: *Camera, delta_yaw: f32, delta_pitch: f32, dt: f32) void {
    camera.rotation[0] += camera.rotate_speed * delta_pitch * dt; // pitch
    camera.rotation[1] -= camera.rotate_speed * delta_yaw * dt; // yaw

    // Clamp pitch
    camera.rotation[0] = @min(camera.rotation[0], 0.48 * std.math.pi);
    camera.rotation[0] = @max(camera.rotation[0], -0.48 * std.math.pi);

    // Normalize yaw to [0, 2π)
    camera.rotation[1] = zmath.modAngle(camera.rotation[1]);
}

pub fn update(camera: *Camera, dt: f32) void {
    _ = dt; // autofix
    updateViewMatrix(camera);
}
