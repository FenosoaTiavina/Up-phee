const std = @import("std");
const keys = @import("keys.zig");
const input = @import("input.zig");
const EventTypes = @import("event_types.zig");

// Re-export all the event types
pub const KeyEvent = EventTypes.KeyEvent;
pub const EventMap = EventTypes.EventMap;
pub const MouseEvent = EventTypes.MouseEvent;
pub const SystemEvent = EventTypes.SystemEvent;
pub const EventData = EventTypes.EventData;
pub const Event = EventTypes.Event;
pub const KeySubscriptionType = EventTypes.KeySubscriptionType;

pub fn createEvent(name: []u8, data: EventData) Event {
    return EventTypes.createEvent(name, data);
}

pub const EventCallback = struct {
    func: *const fn (*EventManager, *EventMap, *f32, *anyopaque) bool,
    context: *anyopaque,

    pub fn init(
        context: *anyopaque,
        func: *const fn (*EventManager, *EventMap, *f32, *anyopaque) bool,
    ) EventCallback {
        return .{
            .func = func,
            .context = context,
        };
    }

    pub fn invoke(self: *const EventCallback, event_manager: *EventManager, delta_time: *f32, event: *EventMap) bool {
        return self.func(event_manager, event, delta_time, self.context);
    }
};

pub const EventManager = struct {
    allocator: std.mem.Allocator,
    handlers: std.StringHashMap(EventCallback),
    delta_time: *f32,

    pub fn init(allocator: std.mem.Allocator, delta_t: *f32) !EventManager {
        return .{
            .allocator = allocator,
            .handlers = std.StringHashMap(EventCallback).init(allocator),
            .delta_time = delta_t,
        };
    }

    pub fn deinit(self: *EventManager) void {
        // Free all handler entries
        var handler_iter = self.handlers.iterator();
        while (handler_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.handlers.deinit();
    }

    pub fn subscribe(self: *EventManager, listen_for: EventMap, callback: EventCallback) void {
        const hash = try listen_for.hash(self.allocator);
        if (!self.handlers.contains(hash)) {
            self.handlers.put(hash, callback);
        }
    }

    pub fn register(self: *EventManager, event_map: EventMap) !void {
        const hash = try event_map.hash(self.allocator);
        if (!self.handlers.contains(hash)) {
            if (self.handlers.get(hash)) |callback| {
                _ = callback.invoke(self, self.delta_time, @constCast(&event_map));
            }
        }
    }
};
