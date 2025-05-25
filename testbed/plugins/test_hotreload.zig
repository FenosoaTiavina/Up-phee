const std = @import("std");
const builtin = @import("builtin");

const uph = @import("uph");
const imgui = uph.imgui;

pub const uph_window_always_on_top = true;

pub fn init(ctx: uph.Context.Context) !void {
    _ = &ctx; // autofix
}

pub fn event(ctx: uph.Context.Context, e: uph.Input.Event) !void {
    // your event processing code
    _ = ctx;
    _ = e;
}

pub fn update(ctx: uph.Context.Context) !void {
    // your game state updating code
    _ = ctx;
}

pub fn draw(ctx: uph.Context.Context) !void {
    _ = ctx; // autofix
}

pub fn quit(ctx: uph.Context.Context) void {
    // your deinit code
    _ = ctx;
}

pub fn getMemory() ?*const anyopaque {
    return &{};
}

pub fn reloadMemory(mem: ?*const anyopaque) void {
    _ = mem; // autofix
}
