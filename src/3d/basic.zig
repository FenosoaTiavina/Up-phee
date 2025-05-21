const uph = @import("../uph.zig");
const zmath = uph.zmath;
const uph3d = uph.uph3d;
const c = uph.clib;
const Types = uph.Types;

const Tri = struct {
    mesh: uph3d.Objects.Mesh,

    pub fn init() Tri {
        return Tri{
            .mesh = uph3d.Objects.createMesh(
                &.{
                    .{ .position = .{ -0.5, 0.5, -0.5 } },
                    .{ .position = .{ -0.5, -0.5, -0.5 } },
                    .{ .position = .{ 0.5, 0.5, -0.5 } },
                },
                &.{ 0, 1, 2 },
            ),
        };
    }
};
