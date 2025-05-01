const std = @import("std");
const uph = @import("uph.zig");
const config = uph.Config;
const game = @import("game");

// Validate game object

pub fn main() !void {
    const uph_config = config.init(game);
    // Options for zig executable
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
