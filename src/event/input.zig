const std = @import("std");
const zgui = @import("zgui");

const c = @import("../imports.zig");
const EventSystem = @import("./event.zig");
const EventTypes = @import("event_types.zig");
const KeyEvent = EventTypes.KeyEvent;
const EventMap = EventTypes.EventMap;
const MouseEvent = EventTypes.MouseEvent;
const SystemEvent = EventTypes.SystemEvent;
const EventData = EventTypes.EventData;
const Event = EventTypes.Event;
const Keys = @import("keys.zig").Keys;

// Re-export all the event types
pub const InputSystem = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    keyboard_state: std.AutoArrayHashMap(Keys, KeyEvent.Key), // Set of currently pressed keys
    mouse_button_state: std.AutoArrayHashMap(MouseEvent.Button, void),
    mouse_motion_state: ?MouseEvent.Motion,
    mouse_scroll_state: ?MouseEvent.Scroll,
    system_state: ?SystemEvent,

    event_manager: *EventSystem.EventManager,

    pub fn init(allocator: std.mem.Allocator, event_manager: *EventSystem.EventManager) Self {
        return Self{
            .allocator = allocator,
            .keyboard_state = std.AutoArrayHashMap(Keys, KeyEvent.Key).init(allocator),
            .mouse_button_state = std.AutoArrayHashMap(MouseEvent.Button, void).init(allocator),
            .mouse_motion_state = null,
            .mouse_scroll_state = null,
            .system_state = null,
            .event_manager = event_manager,
        };
    }

    pub fn deinit(self: *Self) void {
        self.keyboard_state.deinit();
    }

    pub fn pollEvents(self: *Self, sdl_window: *c.sdl.SDL_Window, zgui_event: bool) !bool {

        // Poll SDL events
        var event: c.sdl.SDL_Event = undefined;
        while (c.sdl.SDL_PollEvent(&event)) {
            if (zgui_event)
                _ = zgui.backend.processEvent(&event);

            switch (event.type) {
                c.sdl.SDL_EVENT_QUIT => return true,
                c.sdl.SDL_EVENT_KEY_DOWN, c.sdl.SDL_EVENT_KEY_UP => {
                    const key = Keys.fromSDL(event.key.key);
                    const is_down = event.type == c.sdl.SDL_EVENT_KEY_DOWN;

                    const key_event = KeyEvent.Key{
                        .code = key,
                        .pressed = is_down,
                    };

                    // Insert or update key state
                    if (self.keyboard_state.contains(key)) {
                        self.keyboard_state.putAssumeCapacity(key, key_event);
                    } else {
                        try self.keyboard_state.put(key, key_event);
                    }
                },
                c.sdl.SDL_EVENT_MOUSE_MOTION => {
                    self.mouse_motion_state = .{
                        .x = event.motion.x,
                        .x_rel = event.motion.xrel,
                        .y = event.motion.y,
                        .y_rel = event.motion.yrel,
                    };
                },
                else => {},
            }

            var event_map = try EventMap.init(
                self.*.event_manager.allocator,
                if (self.keyboard_state.capacity() > 0) self.keyboard_state.values() else null,
                if (self.mouse_button_state.capacity() > 0) self.mouse_button_state.keys() else null,
                self.mouse_scroll_state,
                self.mouse_motion_state,
                self.system_state,
            );

            event_map.grabbed = c.sdl.SDL_GetWindowMouseGrab(sdl_window);
            try self.event_manager.dispatch(&event_map);
        }

        return false;
    }
};
