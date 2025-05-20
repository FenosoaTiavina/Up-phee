const std = @import("std");
const builtin = @import("builtin");
const uph = @import("uph.zig");

pub const Config = struct {
    /// Logging level
    uph_log_level: std.log.Level = std.log.default_level,

    /// Headless mode
    uph_headless: bool = false,

    /// Window attributes
    uph_window_title: [:0]const u8 = "UPH-Game",
    uph_window_size: WindowSize = .{ .custom = .{ .width = 800, .height = 600 } },
    uph_window_min_size: ?uph.Types.Size = null,
    uph_window_max_size: ?uph.Types.Size = null,
    uph_window_resizable: bool = false,
    uph_window_borderless: bool = false,

    /// Whether detect memory-leak on shutdown
    uph_check_memory_leak: bool = builtin.mode == .Debug,

    uph_exe_dir: []u8 = "",
};

/// Initial size of window
pub const WindowSize = union(enum) {
    maximized,
    fullscreen,
    custom: struct { width: u32, height: u32 },
};

/// Validate and init setup configurations
pub fn init(comptime game: anytype) Config {
    @setEvalBranchQuota(10000);

    var cfg = Config{};
    const options = [_]struct { name: []const u8, desc: []const u8 }{
        .{ .name = "uph_log_level", .desc = "logging level" },
        .{ .name = "uph_headless", .desc = "headless mode" },
        .{ .name = "uph_window_title", .desc = "title of window" },
        .{ .name = "uph_window_size", .desc = "size of window" },
        .{ .name = "uph_window_min_size", .desc = "minimum size of window" },
        .{ .name = "uph_window_max_size", .desc = "maximum size of window" },
        .{ .name = "uph_window_resizable", .desc = "whether window is resizable" },
        .{ .name = "uph_window_borderless", .desc = "whether window is borderless" },
        .{ .name = "uph_check_memory_leak", .desc = "whether detect memory-leak on shutdown" },
        .{ .name = "uph_exe_dir", .desc = "the executable directory" },
    };
    const game_struct = @typeInfo(game).@"struct";
    for (game_struct.decls) |f| {
        if (!std.mem.startsWith(u8, f.name, "uph_")) {
            continue;
        }
        for (options) |o| {
            if (std.meta.fieldIndex(Config, f.name) == null) continue;

            const CfgFieldType = @TypeOf(@field(cfg, f.name));
            const GameFieldType = @TypeOf(@field(game, f.name));
            const cfg_type = @typeInfo(CfgFieldType);
            const game_type = @typeInfo(GameFieldType);
            if (std.mem.eql(u8, o.name, f.name)) {
                if (CfgFieldType == GameFieldType or
                    (cfg_type == .int and game_type == .comptime_int) or
                    (cfg_type == .optional and cfg_type.optional.child == GameFieldType) or
                    (cfg_type == .@"union" and cfg_type.@"union".tag_type == GameFieldType))
                {
                    @field(cfg, f.name) = @field(game, o.name);
                } else {
                    @compileError("Validation of setup options failed, invalid type for option `" ++
                        f.name ++ "`, expecting " ++ @typeName(CfgFieldType) ++ ", get " ++ @typeName(GameFieldType));
                }
                break;
            }
        } else {
            var buf: [2048]u8 = undefined;
            var off: usize = 0;
            var bs = std.fmt.bufPrint(&buf, "Validation of setup options failed, invalid option name: `" ++ f.name ++ "`", .{}) catch unreachable;
            off += bs.len;
            bs = std.fmt.bufPrint(buf[off..], "\nSupported options:", .{}) catch unreachable;
            off += bs.len;
            inline for (options) |o| {
                bs = std.fmt.bufPrint(buf[off..], "\n\t" ++ o.name ++
                    " (" ++ @typeName(@TypeOf(@field(cfg, o.name))) ++ "): " ++ o.desc ++ ".", .{}) catch unreachable;
                off += bs.len;
            }
            @compileError(buf[0..off]);
        }
    }

    return cfg;
}
