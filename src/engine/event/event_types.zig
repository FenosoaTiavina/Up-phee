const std = @import("std");
const keys = @import("keys.zig");
const crypto = std.crypto;

// Defines how key subscriptions should be processed
pub const KeySubscriptionType = enum {
    Simultaneous, // All keys must be pressed (W+D)
    Parallel, // Any key can be pressed (W or D)
};

pub const EventPollingContext = enum {
    None,
    Parallel,
    Individual,
};

pub const KeyEvent = struct {
    key: std.StringHashMap(Key),
    polling: EventPollingContext = .None,
    pub const Key = struct {
        code: keys.Keys,
        duration: u32,
        timestamp: u64,
    };
};

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
    /// true listen for key combination
    /// false: listen for individual key in the array
    keys_combination: bool,
    mouse_button: ?[]MouseEvent.Button = null,
    mouse_scroll: ?MouseEvent.Scroll = null,
    mouse_motion: ?MouseEvent.Motion = null,
    system: ?SystemEvent = null,
    pub fn create(
        keys_listen: ?[]KeyEvent.Key,
        for_key_combination: bool,
        mouse_button_listen: ?[]MouseEvent.Button,
        mouse_scroll_listen: ?MouseEvent.Scroll,
        mouse_motion_listen: ?MouseEvent.Motion,
        system_listen: ?SystemEvent,
    ) EventMap {
        return .{
            .keys = keys_listen, // autofix
            .mouse_button = mouse_button_listen, // autofix
            .keys_combination = for_key_combination,
            .mouse_scroll = mouse_scroll_listen, // autofix
            .mouse_motion = mouse_motion_listen, // autofix
            .system = system_listen, // autofix
        };
    }
    pub fn hash(self: EventMap, allocator: std.mem.Allocator) ![]const u8 {
        var hasher = crypto.hash.sha2.Sha256.init(.{});

        // Hash keys
        if (self.keys) |keys_| {
            for (keys_) |key| {
                hasher.update(std.mem.asBytes(&key));
            }
        }

        if (self.mouse_button) |buttons| {
            for (buttons) |button| {
                hasher.update(std.mem.asBytes(&button));
            }
        }

        if (self.mouse_scroll) |scroll| {
            hasher.update(std.mem.asBytes(&scroll));
        }

        // Hash mouse motion
        if (self.mouse_motion) |motion| {
            hasher.update(std.mem.asBytes(&motion));
        }

        // Hash system event
        if (self.system) |sys| {
            hasher.update(std.mem.asBytes(&sys));
        }

        // Finalize hash and convert to hex string
        var hash_result: [32]u8 = undefined;
        hasher.final(&hash_result);

        const hex_hash = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&hash_result)});
        defer allocator.free(hex_hash);
        return hex_hash[0..hex_hash.len];
    }
};

pub fn createEvent(name: []u8, data: EventData) Event {
    return .{
        .name = name,
        .data = data,
    };
}
