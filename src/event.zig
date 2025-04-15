const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
});

// Define callback function types for all the events we want to handle
pub const QuitCallbackFn = *const fn () void;

pub const KeyCallbackFn = *const fn (key: sdl.SDL_Keycode, pressed: bool) void;

pub const MouseMotionCallbackFn = *const fn (x: i32, y: i32, xrel: i32, yrel: i32) void;
pub const MouseButtonCallbackFn = *const fn (button: u8, pressed: bool, x: i32, y: i32) void;
pub const MouseWheelCallbackFn = *const fn (scroll_x: i32, scroll_y: i32) void;

pub const WindowCallbackFn = *const fn (event: sdl.SDL_WindowEvent) void;

pub const TextInputCallbackFn = *const fn (text: []const u8) void;
