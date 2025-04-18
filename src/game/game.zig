const renderer = @import("../engine/renderer.zig");
const ecs = @import("ecs");

pub const GameState = enum {
    Running,
    Paused,
    // ...
};

pub const Game = struct {
    // Renderer

    game_renderer: renderer.Renderer,
    ecs_manager: ecs,

    // GameState
    // InputSystem
    // ECS & non Entities Registry
    // TODO: Audio system
};
