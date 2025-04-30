const Renderer = @import("../renderer.zig");
const EventSystem = @import("../event/imports.zig");
const Ecs = @import("ecs");

pub const GameState = enum {
    Running,
    Paused,
    // ...
};

pub const FpsLimit = union(enum) {
    none, // No limit, draw as fast as we can
    auto, // Enable vsync when hardware acceleration is available, default to 30 fps otherwise
    manual: u32, // Capped to given fps, fixed time step

    pub inline fn str(self: @This()) []const u8 {
        return switch (self) {
            .none => "none",
            .auto => "auto",
            .manual => "manual",
        };
    }
};

pub const MouseCursor = union(enum) {
    default,
    custom: []u8,
};

pub const GameConfig = struct {
    window_resizable: bool = true,
    windo_pos: [2]u32,
    window_size: [2]u32,
    window_min_size: ?[2]u32 = null,
    window_max_size: ?[2]u32 = null,

    mouse_grabbed: bool = false,
    mouse_relative: bool = false,
    mouse_cursor: MouseCursor = .default,

    fps_limit: FpsLimit = .{ .manual = 60 },
};

pub const GameContext = struct {
    init_fn: *const fn (*Game) void,
    deinit_fn: *const fn (*Game) void,
    draw_fn: *const fn (*Game) void,
    update_fn: *const fn (*Game) void,
    event_fn: *const fn (*Game) void,
};

pub const Game = struct {
    ctx: GameContext,

    // Renderer
    game_renderer: Renderer.Renderer,

    // GameState
    state: GameState,

    // InputSystem
    event_manager: EventSystem.manager.EventManager,
    input_system: EventSystem.input.InputSystem,

    // ECS & non Entities Registry
    ecs_manager: Ecs.Registry,

    // TODO:
    // Audio system, physics, io,
};
