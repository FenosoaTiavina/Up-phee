const std = @import("std");
pub inline fn minAndMax(_x: anytype, _y: anytype, _z: anytype) std.meta.Tuple(&[_]type{
    @TypeOf(_x, _y, _z),
    @TypeOf(_x, _y, _z),
}) {
    var x = _x;
    var y = _y;
    var z = _z;
    if (x > y) std.mem.swap(@TypeOf(_x, _y, _z), &x, &y);
    if (x > z) std.mem.swap(@TypeOf(_x, _y, _z), &x, &z);
    if (y > z) std.mem.swap(@TypeOf(_x, _y, _z), &y, &z);
    return .{ x, z };
}
