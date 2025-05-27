const uph = @import("../uph.zig");
const std = @import("std");

pub inline fn vecMagnetude(vec: anytype) f32 {
    var sqrsum: f32 = 0;
    const T = @TypeOf(vec);
    const com: u16 = switch (T) {
        uph.Types.Vec2_usize, uph.Types.Vec2_f32 => 2,
        uph.Types.Vec3_f32 => 3,
        uph.Types.Vec4_u8, uph.Types.Vec4_f32 => 4,
        else => @compileError("vecf32magnetude() not implemented for " ++ @typeName(T)),
    };

    for (0..com - 1) |i| {
        sqrsum += vec[i] * vec[i];
    }

    return @sqrt(sqrsum);
}

pub inline fn isVecZero(vec: anytype) bool {
    const T = @TypeOf(vec);
    var zero = false;
    const com: u16 = switch (T) {
        uph.Types.Vec2_f32 => 2,
        uph.Types.Vec3_f32 => 3,
        uph.Types.Vec4_f32 => 4,
        else => @compileError("vecf32magnetude() not implemented for " ++ @typeName(T)),
    };

    for (0..com - 1) |i| {
        zero = zero and (vec[i] == 0);
    }
    return zero;
}

pub inline fn dotVec3(v0: uph.Types.Vec3_f32, v1: uph.Types.Vec3_f32) uph.Types.Vec3_f32 {
    const dot = v0 * v1;
    return uph.zmath.splat(uph.Types.Vec3_f32, dot[0] + dot[1] + dot[2]);
}

pub inline fn normalizeVec3(v: uph.Types.Vec3_f32) uph.Types.Vec3_f32 {
    return v * uph.zmath.splat(uph.Types.Vec3_f32, 1.0) / uph.zmath.sqrt(dotVec3(v, v));
}

pub const F32x3Component = enum { x, y, z };

pub inline fn swizzle(
    v: uph.Types.Vec3_f32,
    comptime x: F32x3Component,
    comptime y: F32x3Component,
    comptime z: F32x3Component,
) uph.Types.Vec3_f32 {
    return @shuffle(f32, v, undefined, [3]i32{ @intFromEnum(x), @intFromEnum(y), @intFromEnum(z) });
}

const f32x3_mask: uph.Types.Vec3_f32 = uph.Types.Vec3_f32{
    @as(f32, @bitCast(@as(u32, 0xffff_ffff))),
    @as(f32, @bitCast(@as(u32, 0xffff_ffff))),
    @as(f32, @bitCast(@as(u32, 0xffff_ffff))),
};

pub inline fn crossVec3(v0: uph.Types.Vec3_f32, v1: uph.Types.Vec3_f32) uph.Types.Vec3_f32 {
    var xmm0 = swizzle(v0, .y, .z, .x);
    var xmm1 = swizzle(v1, .z, .x, .y);
    var result = xmm0 * xmm1;
    xmm0 = swizzle(xmm0, .y, .z, .x);
    xmm1 = swizzle(xmm1, .z, .x, .y);
    result = result - xmm0 * xmm1;
    return uph.zmath.andInt(result, f32x3_mask);
}

pub inline fn vec3toVec4(v: uph.Types.Vec3_f32) uph.Types.Vec4_f32 {
    return uph.zmath.f32x4(v[0], v[1], v[2], 1.0);
}

pub fn mulVec3Mat4(vertex: uph.Types.Vec3_f32, transform: uph.Types.Mat4_f32) uph.Types.Vec3_f32 {
    // Convert 3D vector to 4D homogeneous coordinates
    const vec4_D = uph.zmath.f32x4(vertex[0], vertex[1], vertex[2], 1.0);

    // Apply transformation
    const vec_mult = uph.zmath.mul(vec4_D, transform);

    // Convert back to 3D vector
    return uph.Types.Vec3_f32{ vec_mult[0], vec_mult[1], vec_mult[2] };
}
