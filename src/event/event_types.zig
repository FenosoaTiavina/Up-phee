const std = @import("std");
const crypto = std.crypto;

// const sort = @import("../../utils/quicksort.zig");
const keys = @import("keys.zig");

// Defines how key subscriptions should be processed
pub const EventPollingContext = enum {
    None,
    Parallel,
    Individual,
};

pub const KeyEvent = struct {
    key: std.StringHashMap(Key),
    pub const Key = struct {
        code: keys.Keys,
        pressed: bool = true,
    };
};

pub const MouseEvent = struct {
    id_event: u32,
    MouseMotion: ?Motion = null,
    MouseButton: std.StringHashMap(Button),
    MouseScroll: ?Scroll = null,

    pub const Motion = struct {
        x: f32 = 0,
        y: f32 = 0,
        x_rel: f32 = 0,
        y_rel: f32 = 0,
    };

    pub const Button = struct {
        button: u8,
        x: f32,
        y: f32,
        x_rel: f32,
        y_rel: f32,
        duration: u32,
        repeat: u32 = 1,
        timestamp: u64,
    };

    pub const Scroll = struct {
        x_scroll: i32 = 0,
        y_scroll: i32 = 0,
        timestamp: u64 = 0,
    };
};

pub fn comp_button_less_than(_: void, lhs: MouseEvent.Button, rhs: MouseEvent.Button) bool {
    return lhs.button < rhs.button;
}

pub const SystemEvent = struct {
    id_event: u32,
    event: union(enum) {
        Quit,
        Resize: struct { width: u32, height: u32 },
    },
};

// Extended to support KeyBitfield events
pub const EventData = struct {
    System: ?SystemEvent = null,
    Keys: ?KeyEvent = null,
    Mouse: ?MouseEvent = null,
};

pub const Event = struct { name: []u8, data: EventData };

pub const EventMap = struct {
    keys: std.ArrayList(KeyEvent.Key),
    mouse_button: ?[]MouseEvent.Button = null,
    mouse_scroll: ?MouseEvent.Scroll = null,
    mouse_motion: ?MouseEvent.Motion = null,
    system: ?SystemEvent = null,
    grabbed: ?bool = null,

    pub fn init(
        allocator: std.mem.Allocator,
        keys_listen: ?[]const KeyEvent.Key,
        mouse_button_listen: ?[]MouseEvent.Button,
        mouse_scroll_listen: ?MouseEvent.Scroll,
        mouse_motion_listen: ?MouseEvent.Motion,
        system_listen: ?SystemEvent,
    ) !EventMap {
        var key_map = std.ArrayList(KeyEvent.Key).init(allocator);

        if (keys_listen) |list| {
            try key_map.insertSlice(key_map.items.len, list);
        }

        return EventMap{
            .keys = key_map,
            .mouse_button = mouse_button_listen,
            .mouse_scroll = mouse_scroll_listen,
            .mouse_motion = mouse_motion_listen,
            .system = system_listen,
        };
    }

    pub fn deinit(self: *EventMap) void {
        self.keys.deinit();
        // Other fields are optional references — no ownership → no deinit
    }

    pub fn serialize(self: EventMap, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        const writer = buffer.writer();

        // Serialize keys
        for (self.keys.items, 0..) |keys_, i| {
            try writer.writeAll("keys:");
            if (i > 0) try writer.writeByte(',');
            try std.fmt.format(writer, "{}", .{@intFromEnum(keys_.code)});
            try writer.writeByte(':');
        }

        // Serialize mouse buttons
        if (self.mouse_button) |buttons| {
            try writer.writeAll("mouse_btn:");
            for (buttons, 0..) |button, i| {
                if (i > 0) try writer.writeByte(',');
                try std.fmt.format(writer, "{}", .{button.button});
            }
            try writer.writeByte(':');
        }

        // Serialize mouse scroll
        if (self.mouse_scroll) |scroll| {
            try std.fmt.format(writer, "scroll:{}:{}:", .{
                scroll.x_scroll,
                scroll.y_scroll, // Fixed: was using x_scroll twice
            });
        }

        // Serialize mouse motion
        if (self.mouse_motion) |motion| {
            try std.fmt.format(writer, "motion:{}:{}:", .{ motion.x, motion.y });
        }

        // Serialize system event
        if (self.system) |sys| {
            try std.fmt.format(writer, "system:{}:", .{@intFromEnum(sys.event)});
        }

        return buffer.toOwnedSlice();
    }

    /// lhs: subscribed
    /// rhs: received
    pub fn check_any(lhs: EventMap, rhs: EventMap, allocator: std.mem.Allocator) !bool {
        if (lhs.keys.items.len == 0 or rhs.keys.items.len == 0) {
            return false;
        }

        // 0. get only pressed lhs
        var pressed_keys: std.ArrayList(KeyEvent.Key) = std.ArrayList(KeyEvent.Key).init(allocator);
        defer pressed_keys.deinit();
        for (rhs.keys.items, 0..rhs.keys.items.len) |r_entry, _| {
            if (r_entry.pressed) {
                try pressed_keys.append(r_entry);
            }
        }

        // 3. check
        var ok: bool = false;
        for (rhs.keys.items) |r_entry| {
            for (lhs.keys.items) |l_entry| {
                if (r_entry.code == l_entry.code)
                    ok = true;
            }
        }

        return ok;
    }

    /// lhs: subscribed
    /// rhs: received
    pub fn check_combo(lhs: EventMap, rhs: EventMap, allocator: std.mem.Allocator) !bool {
        if (lhs.keys.items.len == 0 or rhs.keys.items.len == 0) {
            return false;
        }

        // 0. get only pressed lhs
        var pressed_keys: std.ArrayList(KeyEvent.Key) = std.ArrayList(KeyEvent.Key).init(allocator);
        defer pressed_keys.deinit();
        for (rhs.keys.items, 0..rhs.keys.items.len) |r_entry, _| {
            if (r_entry.pressed) {
                try pressed_keys.append(r_entry);
            }
        }

        // 1. Check length
        if (pressed_keys.items.len != lhs.keys.items.len) {
            return false;
        }

        // 3. check

        return true;
    }

    /// lhs: subscribed
    /// rhs: received
    pub fn check_keys(lhs: EventMap, rhs: EventMap, individual_keys: bool, allocator: std.mem.Allocator) !bool {
        if (!individual_keys) {
            return try check_combo(lhs, rhs, allocator);
        }
        return try check_any(lhs, rhs, allocator);
    }

    pub fn check_motion(lhs: EventMap, rhs: EventMap, _: std.mem.Allocator) !bool {
        if (lhs.mouse_motion != null and rhs.mouse_motion != null) {
            return true;
        }
        return false;
    }
};

pub fn createEvent(name: []u8, data: EventData) Event {
    return .{
        .name = name,
        .data = data,
    };
}
