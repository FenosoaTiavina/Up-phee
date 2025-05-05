const std = @import("std");
const builtin = @import("builtin");
const uph = @import("uph");
const zgui = uph.zgui;

pub const uph_window_always_on_top = true;

pub fn init(ctx: uph.Context.Context) !void {
    std.log.debug("Hello from entry pint", .{});
    _ = ctx; // autofix
}

pub fn event(ctx: uph.Context.Context, e: uph.Events.EventManager) !void {
    _ = ctx; // autofix
    _ = e; // autofix
}

pub fn update(ctx: uph.Context.Context) !void {
    _ = ctx; // autofix
}

pub fn draw(ctx: uph.Context.Context) !void {
    try ctx.renderer().zgui_render();
}

pub fn quit(ctx: uph.Context.Context) void {
    // your deinit code
    _ = ctx;
}
