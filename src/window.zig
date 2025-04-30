const std = @import("std");
const T_ = @import("types.zig");
const c = @import("imports.zig");

pub const Window = struct {
    sdl_window: *c.sdl.SDL_Window,
    window_dimension: T_.Size,
    window_title: [*c]const u8,

    pub fn init(window_width: u32, window_height: u32, window_title: [*c]const u8) !Window {
        if (!c.sdl.SDL_Init(c.sdl.SDL_INIT_VIDEO)) {
            return error.SDLInitFailed;
        }

        const window = c.sdl.SDL_CreateWindow(window_title, @intCast(window_width), @intCast(window_height), c.sdl.SDL_WINDOW_VULKAN | c.sdl.SDL_WINDOW_RESIZABLE) orelse {
            return error.WindowCreationFailed;
        };

        return Window{
            .sdl_window = window,
            .window_dimension = T_.Vec2_usize{ @intCast(window_width), @intCast(window_height) },
            .window_title = window_title,
        };
    }

    pub fn set_size(self: *Window, size: T_.Size) void {
        _ = c.sdl.SDL_GetWindowSize(self.*.sdl_window, @intCast(size.width), @intCast(size.height));
    }

    pub fn getAspectRatio(self: *Window) f32 {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.sdl.SDL_GetWindowSize(self.*.sdl_window, &w, &h);
        return @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
    }

    pub fn deinit(self: *Window) void {
        c.sdl.SDL_DestroyWindow(self.sdl_window);
        c.sdl.SDL_Quit();
    }
};
