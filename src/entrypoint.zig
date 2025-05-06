const std = @import("std");
const uph = @import("uph");
const config = uph.Config;
const game = @import("game");

const compcheck = @import("./app_check.zig");

comptime {
    compcheck.doAppCheck(game);
}

// Validate game object

const uph_config = config.init(game);

pub fn main() !void {
    const log = std.log.scoped(.UPH);

    var uph_ctx = try uph.Context.uphContext(uph_config).create();
    defer uph_ctx.destroy();
    const ctx = uph_ctx.context();

    game.init(ctx) catch |err| {
        log.err("Init game failed: {}", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
            std.process.abort();
        }
    };

    // Start game loop
    while (uph_ctx._running) {
        uph_ctx.tick(game.event, game.update, game.draw);
    }
    game.quit(ctx);
    uph_ctx.destroy();
}
