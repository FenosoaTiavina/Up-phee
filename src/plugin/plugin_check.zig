const std = @import("std");
const uph = @import("uph");

pub fn doPluginCheck(plugin: type) void {
    if (!@hasDecl(plugin, "init") or
        !@hasDecl(plugin, "event") or
        !@hasDecl(plugin, "update") or
        !@hasDecl(plugin, "draw") or
        !@hasDecl(plugin, "quit") or
        !@hasDecl(plugin, "getMemory") or
        !@hasDecl(plugin, "reloadMemory"))
    {
        @compileError(
            \\You must provide following 7 public api in your plugin code:
            \\    pub fn init(ctx: uph.Context.Context) !void
            \\    pub fn event(ctx: uph.Context.Context, e: sdl.Input.Event) !void
            \\    pub fn update(ctx: uph.Context.Context) !void
            \\    pub fn draw(ctx: uph.Context.Context) !void
            \\    pub fn quit(ctx: uph.Context.Context) void
            \\    pub fn getMemory() ?*anyopaque
            \\    pub fn reloadMemory(mem: ?*anyopaque) void
        );
    }
    switch (@typeInfo(@typeInfo(@TypeOf(plugin.init)).@"fn".return_type.?)) {
        .error_union => |info| if (info.payload != void) {
            @compileError("`init` must return !void");
        },
        else => @compileError("`init` must return !void"),
    }
    switch (@typeInfo(@typeInfo(@TypeOf(plugin.event)).@"fn".return_type.?)) {
        .error_union => |info| if (info.payload != void) {
            @compileError("`event` must return !void");
        },
        else => @compileError("`init` must return !void"),
    }
    switch (@typeInfo(@typeInfo(@TypeOf(plugin.update)).@"fn".return_type.?)) {
        .error_union => |info| if (info.payload != void) {
            @compileError("`update` must return !void");
        },
        else => @compileError("`update` must return !void"),
    }
    switch (@typeInfo(@typeInfo(@TypeOf(plugin.draw)).@"fn".return_type.?)) {
        .error_union => |info| if (info.payload != void) {
            @compileError("`draw` must return !void");
        },
        else => @compileError("`draw` must return !void"),
    }
    switch (@typeInfo(@typeInfo(@TypeOf(plugin.quit)).@"fn".return_type.?)) {
        .void => {},
        else => @compileError("`quit` must return void"),
    }
    switch (@typeInfo(@typeInfo(@TypeOf(plugin.getMemory)).@"fn".return_type.?)) {
        .optional => |info| if (info.child != *const anyopaque) {
            @compileError("`getMemory` must return ?*anyopaque");
        },
        else => @compileError("`getMemory` must return ?*anyopaque"),
    }
    switch (@typeInfo(@typeInfo(@TypeOf(plugin.reloadMemory)).@"fn".return_type.?)) {
        .void => {},
        else => @compileError("`reloadMemory` must return void"),
    }
}
