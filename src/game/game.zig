const Renderer = @import("../engine/renderer.zig");
const EventSystem = @import("../engine/event/imports.zig");
const Ecs = @import("ecs");

pub const GameState = enum {
    Running,
    Paused,
    // ...
};

pub const Game = struct {
    // Renderer

    game_renderer: Renderer.Renderer,

    // GameState
    // InputSystem
    event_manager: EventSystem.manager.EventManager,
    input_system: EventSystem.input.InputSystem,

    // ECS & non Entities Registry
    ecs_manager: Ecs.Registry,

    // TODO: Audio system
};
