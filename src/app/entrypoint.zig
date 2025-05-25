const std = @import("std");
const builtin = @import("builtin");
const uph = @import("uph");
const config = uph.Config;
const game = @import("game");

const compcheck = @import("./app_check.zig");

comptime {
    compcheck.doAppCheck(game);
}

// Validate game object
const uph_config: uph.Config.Config = config.init(game);

pub fn main() !void {
    const log = std.log.scoped(.UPH);

    var uph_ctx = try uph.Context.uphContext(uph_config).create();
    defer uph_ctx.destroy();

    const ctx = uph_ctx.context();

    uph_ctx.ctx_config(try game.config(ctx));

    log.debug("CFG.exe_dir : {s}", .{uph_ctx._cfg.uph_exe_dir});

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
}
