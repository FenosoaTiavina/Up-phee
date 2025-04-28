const std = @import("std");
const uph = @import("uph");
const config = uph.config;
const game = @import("game");
const compcheck = @import("compcheck.zig");

// Validate game object
comptime {
    compcheck.doAppCheck(game);
}

// uph configuration
const uph_config = config.init(game);

// Options for zig executable
pub const std_options: std.Options = .{
    .log_level = uph_config.uph_log_level,
};

pub fn main() !void {
    const log = std.log.scoped(.uph);

    // Init context
    var uph_ctx = try uph.uphContext(uph_config).create();
    defer uph_ctx.destroy();

    // Init game object
    const ctx = uph_ctx.context();
    game.init(ctx) catch |err| {
        log.err("Init game failed: {}", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
            std.process.abort();
        }
    };
    defer game.quit(ctx);

    // Start game loop
    while (uph_ctx._running) {
        uph_ctx.tick(game.event, game.update, game.draw);
    }
}
