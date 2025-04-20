const std = @import("std");
const keys = @import("keys.zig");

const input = @import("input.zig");

const Allocator = std.mem.Allocator;

pub const EventID = enum(u32) {
    Quit = 1,
    Resize,
    KeyEvent,
    MouseMotion,
    MouseButton,
    MouseScroll,
};

pub const PressData = struct {
    key_code: keys.Keys,
    duration: u32,
    timestamp: u64,
};

pub const KeyEvent = struct {
    key: std.StringHashMap(PressData),
};

pub const MouseEvent = struct {
    id_event: u32,
    MouseMotion: ?Motion = null,
    MouseButton: ?Button = null,
    MouseScroll: ?Scroll = null,

    pub const Motion = struct {
        x: u32,
        y: u32,
        x_rel: u32,
        y_rel: u32,
    };

    pub const Button = struct {
        button: std.StringHashMap(u32),
        x: f32,
        y: f32,
        x_rel: f32,
        y_rel: f32,
        duration: u32,
        repeat: u32 = 1,
        timestamp: u64,
    };

    pub const Scroll = struct {
        x_scroll: i32,
        y_scroll: i32,
        timestamp: u64,
    };
};

pub const SystemEvent = struct {
    id_event: u32,
    event: union(enum) {
        Quit,
        Resize: struct { width: u32, height: u32 },
    },
};

const EventContext = enum {
    Sent,
    Queued,
    Immediate,
};

pub const EventData = struct {
    System: ?SystemEvent = null,
    Keys: ?KeyEvent = null,
    Mouse: ?MouseEvent = null,
};

pub const Event = struct { name: []u8, data: EventData, ctx: EventContext };

pub fn createEvent(name: []u8, data: EventData, ctx: EventContext) Event {
    return .{
        .name = name,
        .data = data,
        .ctx = ctx,
    };
}

pub const EventCallback = struct {
    func: *const fn (*EventManager, *Event, *anyopaque) bool,
    context: *anyopaque,

    pub fn init(
        context: *anyopaque,
        func: *const fn (*EventManager, *Event, *anyopaque) bool,
    ) EventCallback {
        return .{
            .func = func,
            .context = context,
        };
    }

    pub fn invoke(self: *const EventCallback, event_manager: *EventManager, event: *Event) bool {
        return self.func(event_manager, event, self.context);
    }
};

pub const EventManager = struct {
    allocator: Allocator,
    handlers: std.StringHashMap(EventCallback),
    queue: std.StringHashMap(Event),

    pub fn init(allocator: Allocator) !EventManager {
        return .{
            .allocator = allocator,
            .handlers = std.StringHashMap(EventCallback).init(allocator),
            .queue = std.StringHashMap(Event).init(allocator),
        };
    }

    pub fn deinit(self: *EventManager) void {
        // Free all handler entries
        var handler_iter = self.handlers.iterator();
        while (handler_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.handlers.deinit();

        // Free all queue entries and their nested data
        var queue_iter = self.queue.iterator();
        while (queue_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);

            // Clean up nested event data
            if (entry.value_ptr.data.Keys) |*key_ev| {
                var key_iter = key_ev.key.iterator();
                while (key_iter.next()) |key_entry| {
                    self.allocator.free(key_entry.key_ptr.*);
                }
                key_ev.key.deinit();
            }
        }
        self.queue.deinit();
    }

    pub fn unsubscribe(self: *EventManager, event_name: []const u8) void {
        // Remove and free handler
        if (self.handlers.fetchRemove(event_name)) |handler_entry| {
            self.allocator.free(handler_entry.key);
        }

        // Remove and free queue entry with nested data
        if (self.queue.fetchRemove(event_name)) |queue_entry| {
            self.allocator.free(queue_entry.key);

            if (queue_entry.value.data.Keys) |key_ev| {
                var key_iter = key_ev.key.iterator();
                while (key_iter.next()) |key_entry| {
                    self.allocator.free(key_entry.key_ptr.*);
                }
                key_ev.key.deinit();
            }
        }
    }

    pub fn subscribe(self: *EventManager, keys_pressed: []const keys.Keys, processing: EventContext, callback: EventCallback) !void {
        var temp_hash = std.StringHashMap(PressData).init(self.allocator);
        defer {
            var iter = temp_hash.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            temp_hash.deinit();
        }

        // Create copies of all key names
        for (keys_pressed) |key| {
            const key_name = try self.allocator.dupe(u8, key.getName());
            try temp_hash.put(key_name, PressData{ .duration = 0, .key_code = key, .timestamp = 0 });
        }

        const event_name = try input.serializedKeyPress(self, input.KeyBitfield.fromHashMap(temp_hash));
        defer self.allocator.free(event_name);

        // Create owned copies for storage
        const queue_key = try self.allocator.dupe(u8, event_name);
        errdefer self.allocator.free(queue_key);

        const handlers_key = try self.allocator.dupe(u8, event_name);
        errdefer self.allocator.free(handlers_key);

        // Clone the temp_hash with new allocations
        var keys_copy = std.StringHashMap(PressData).init(self.allocator);
        errdefer {
            var iter = keys_copy.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            keys_copy.deinit();
        }

        var temp_iter = temp_hash.iterator();
        while (temp_iter.next()) |entry| {
            const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
            try keys_copy.put(key_copy, entry.value_ptr.*);
        }

        const event = createEvent(
            queue_key,
            .{
                .Keys = .{
                    .key = keys_copy,
                },
            },
            processing,
        );

        try self.queue.put(queue_key, event);
        try self.handlers.put(handlers_key, callback);
    }

    pub fn register(self: *EventManager, event: Event) void {

        // Only process Sent events immediately
        if (event.ctx != .Sent) {
            return;
        }

        // Get the stored event and handler
        const event_exist = self.queue.get(event.name) orelse {
            std.log.debug("Event not found in queue", .{});
            return;
        };

        const handler = self.handlers.get(event.name) orelse {
            std.log.debug("Handler not found for event", .{});
            return;
        };

        // For Immediate events, invoke the handler
        if (event_exist.ctx == .Immediate) {
            _ = handler.invoke(self, @constCast(&event_exist));
        }
    }
};
