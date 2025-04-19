const std = @import("std");

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
    key_code: u32,
    duration: u32,
    timestamp: u64,
};

pub const KeyEvent = struct {
    id_event: u32,
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

const EventExecutionMode = enum {
    Queued,
    Immediate,
};

pub const EventData = struct {
    System: ?SystemEvent = null,
    Keys: ?KeyEvent = null,
    Mouse: ?MouseEvent = null,
};

pub const Event = struct {
    name: []const u8,
    data: EventData,
};

pub fn createEvent(name: []const u8, data: EventData) Event {
    return .{
        .name = name,
        .data = data,
    };
}

pub const EventCallback = struct {
    func: *const fn (*anyopaque, *const anyopaque) bool,
    args: *anyopaque,
};

pub const EventManager = struct {
    allocator: Allocator,
    handlers: std.AutoHashMap(u32, EventCallback),
    queue: std.AutoHashMap(u32, Event),

    pub fn init(allocator: Allocator) !EventManager {
        return .{
            .allocator = allocator,
            .handlers = std.AutoHashMap(u32, EventCallback).init(allocator),
            .queue = std.AutoHashMap(u32, Event).init(allocator),
        };
    }

    pub fn deinit(self: *EventManager) void {
        self.handlers.deinit();
        self.queue.deinit();
    }
};
