const std = @import("std");

const c = @import("../../imports.zig");
const EventSystem = @import("./event.zig");
const EventTypes = @import("event_types.zig");
pub const KeyEvent = EventTypes.KeyEvent;
pub const EventMap = EventTypes.EventMap;
pub const MouseEvent = EventTypes.MouseEvent;
pub const SystemEvent = EventTypes.SystemEvent;
pub const EventData = EventTypes.EventData;
pub const Event = EventTypes.Event;
pub const KeySubscriptionType = EventTypes.KeySubscriptionType;

const Keys = @import("keys.zig").Keys;

// Re-export all the event types
pub const InputSystem = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    current_keys: std.AutoArrayHashMap(KeyEvent.Key, void), // Set of currently pressed keys
    last_keys: std.AutoArrayHashMap(KeyEvent.Key, void), // Set of keys pressed last frame
    //
    mouse_button_state: std.AutoArrayHashMap(MouseEvent.Button, void),
    mouse_motion_state: ?MouseEvent.Motion,
    mouse_scroll_state: ?MouseEvent.Scroll,
    system_state: ?SystemEvent,

    event_manager: *EventSystem.EventManager,

    pub fn init(allocator: std.mem.Allocator, event_manager: *EventSystem.EventManager) Self {
        return Self{
            .allocator = allocator,
            .current_keys = std.AutoArrayHashMap(KeyEvent.Key, void).init(allocator),
            .last_keys = std.AutoArrayHashMap(KeyEvent.Key, void).init(allocator),
            .mouse_button_state = std.AutoArrayHashMap(MouseEvent.Button, void).init(allocator),
            .mouse_motion_state = null,
            .mouse_scroll_state = null,
            .system_state = null,
            .event_manager = event_manager,
        };
    }

    pub fn deinit(self: *Self) void {
        self.current_keys.deinit();
        self.last_keys.deinit();
    }

    pub fn pollEvents(self: *Self) !bool {
        // Move current keys to last keys
        self.last_keys.clearRetainingCapacity();
        for (self.current_keys.keys()) |key| {
            try self.last_keys.put(key, {});
        }
        self.current_keys.clearRetainingCapacity();

        // Poll SDL events
        var event: c.sdl.SDL_Event = undefined;
        while (c.sdl.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.sdl.SDL_EVENT_QUIT => return true,
                c.sdl.SDL_EVENT_KEY_DOWN => {
                    const key = Keys.fromSDL(event.key.key);
                    std.log.debug("key down {s}", .{key.getName()});
                    try self.current_keys.put(KeyEvent.Key{ .code = key, .duration = 0, .timestamp = event.key.timestamp / 1000000 }, {});
                },
                c.sdl.SDL_EVENT_KEY_UP => {
                    const key = Keys.fromSDL(event.key.key);
                    _ = self.current_keys.orderedRemove(KeyEvent.Key{ .code = key, .duration = 0, .timestamp = event.key.timestamp / 1000000 });
                },
                else => {},
            }

            const event_map = EventMap.create(
                if (self.current_keys.capacity() > 0) self.current_keys.keys() else null,
                false,
                if (self.mouse_button_state.capacity() > 0) self.mouse_button_state.keys() else null,
                self.mouse_scroll_state,
                self.mouse_motion_state,
                self.system_state,
            );

            try self.event_manager.register(event_map);
        }

        return false;
    }
};
