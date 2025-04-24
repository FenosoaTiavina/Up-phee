const std = @import("std");
const keys = @import("keys.zig");
const crypto = std.crypto;
const sort = @import("../../utils/quicksort.zig");

const APPROX_TOLERANCE = 2;
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

fn keys_less_than(lhs: KeyEvent.Key, rhs: KeyEvent.Key) bool {
    if (lhs.pressed == false) return false;
    return @intFromEnum(lhs.code) < @intFromEnum(rhs.code);
}

fn sortButtons(buttons: []MouseEvent.Button) void {
    if (buttons.len <= 1) return;

    var swapped = true;
    while (swapped) {
        swapped = false;
        for (0..buttons.len - 1) |i| {
            if (buttons[i].button > buttons[i + 1].button) {
                // Simple swap without dereferencing
                const temp = buttons[i];
                buttons[i] = buttons[i + 1];
                buttons[i + 1] = temp;
                swapped = true;
            }
        }
    }
}

pub const MouseEvent = struct {
    id_event: u32,
    MouseMotion: ?Motion = null,
    MouseButton: std.StringHashMap(Button),
    MouseScroll: ?Scroll = null,
    pollig: EventPollingContext = .None,

    pub const Motion = struct {
        x: u32,
        y: u32,
        x_rel: u32,
        y_rel: u32,
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
        x_scroll: i32,
        y_scroll: i32,
        timestamp: u64,
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
    keys: ?[]KeyEvent.Key = null,
    mouse_button: ?[]MouseEvent.Button = null,
    mouse_scroll: ?MouseEvent.Scroll = null,
    mouse_motion: ?MouseEvent.Motion = null,
    system: ?SystemEvent = null,

    pub fn listener(
        keys_listen: ?[]const KeyEvent.Key,
        mouse_button_listen: ?[]const MouseEvent.Button,
        mouse_scroll_listen: ?MouseEvent.Scroll,
        mouse_motion_listen: ?MouseEvent.Motion,
        system_listen: ?SystemEvent,
    ) !EventMap {
        if (keys_listen == null and
            mouse_button_listen == null and
            mouse_scroll_listen == null and
            mouse_motion_listen == null and
            system_listen == null)
        {
            return error.NeedEventToListen;
        }
        return .{
            .keys = @constCast(keys_listen), // autofix
            .mouse_button = @constCast(mouse_button_listen), // autofix
            .mouse_scroll = mouse_scroll_listen, // autofix
            .mouse_motion = mouse_motion_listen, // autofix
            .system = system_listen, // autofix
        };
    }
    pub fn create(
        keys_listen: ?[]const KeyEvent.Key,
        mouse_button_listen: ?[]const MouseEvent.Button,
        mouse_scroll_listen: ?MouseEvent.Scroll,
        mouse_motion_listen: ?MouseEvent.Motion,
        system_listen: ?SystemEvent,
    ) EventMap {
        return .{
            .keys = @constCast(keys_listen), // autofix
            .mouse_button = @constCast(mouse_button_listen), // autofix
            .mouse_scroll = mouse_scroll_listen, // autofix
            .mouse_motion = mouse_motion_listen, // autofix
            .system = system_listen, // autofix
        };
    }

    pub fn serialize(self: EventMap, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        const writer = buffer.writer();

        // Serialize keys
        if (self.keys) |keys_| {
            try writer.writeAll("keys:");
            for (keys_, 0..) |key, i| {
                if (i > 0) try writer.writeByte(',');
                try std.fmt.format(writer, "{}", .{@intFromEnum(key.code)});
            }
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

    pub fn check_seq(lhs: EventMap, rhs: EventMap, allocator: std.mem.Allocator) !bool {
        if (lhs.keys == null or rhs.keys == null) {
            return false;
        }

        // 0. get only pressed lhs
        var pressed_keys: std.ArrayList(KeyEvent.Key) = std.ArrayList(KeyEvent.Key).init(allocator);
        defer pressed_keys.deinit();

        for (rhs.keys.?) |value| {
            if (value.pressed) {
                try pressed_keys.append(value);
            }
        }

        // 1. Check length
        if (pressed_keys.items.len != lhs.keys.?.len) {
            return false;
        }
        // 2. sort
        sort.quicksort(KeyEvent.Key, pressed_keys.items, pressed_keys.items.len, pressed_keys.items.len - 1, keys_less_than);
        sort.quicksort(KeyEvent.Key, lhs.keys.?, lhs.keys.?.len, lhs.keys.?.len - 1, keys_less_than);

        std.log.debug("pressed        {any}", .{pressed_keys.items});
        std.log.debug("subscribed     {any}", .{lhs.keys.?});

        // 3. check
        //
        return true;
    }

    pub fn check(lhs: EventMap, rhs: EventMap, individual_keys: bool, allocator: std.mem.Allocator) !bool {
        if (!individual_keys) {
            return try check_seq(lhs, rhs, allocator);
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
