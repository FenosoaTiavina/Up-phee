const std = @import("std");
const c = @import("../../imports.zig");
const EventSystem = @import("./event.zig");
const Keys = @import("keys.zig").Keys;

// Bitfield representation of pressed keys
pub const KeyBitfield = struct {
    // Assuming we have around 256 keys, we need 32 bytes to represent them all
    bits: [32]u8 = [_]u8{0} ** 32,

    // Set a bit for a specific key
    pub fn setBit(self: *KeyBitfield, key: Keys) void {
        const key_value = @intFromEnum(key);
        const byte_index = key_value >> 3; // Divide by 8 to get byte index
        const bit_index = @as(u3, @truncate(key_value & 7)); // Modulo 8 to get bit position, as u3
        self.bits[byte_index] |= @as(u8, 1) << bit_index;
    }

    // Check if a bit is set for a specific key
    pub fn isBitSet(self: KeyBitfield, key: Keys) bool {
        const key_value = @intFromEnum(key);
        const byte_index = key_value >> 3; // Divide by 8 to get byte index
        const bit_index = @as(u3, @truncate(key_value & 7)); // Modulo 8 to get bit position, as u3
        return (self.bits[byte_index] & (@as(u8, 1) << bit_index)) != 0;
    }

    // Convert from HashMap to KeyBitfield
    pub fn fromHashMap(key_map: std.StringHashMap(EventSystem.PressData)) KeyBitfield {
        var bitfield = KeyBitfield{};
        var key_iter = key_map.valueIterator();
        while (key_iter.next()) |key| {
            bitfield.setBit(key.*.key_code);
        }
        return bitfield;
    }

    // Clear all bits
    pub fn clear(self: *KeyBitfield) void {
        for (0..self.bits.len) |i| {
            self.bits[i] = 0;
        }
    }
};

pub const InputSystem = struct {
    event_manager: *EventSystem.EventManager,
    pressed: std.StringHashMap(EventSystem.PressData),

    pub fn init(event_manager: *EventSystem.EventManager) !InputSystem {
        return InputSystem{
            .event_manager = event_manager,
            .pressed = std.StringHashMap(EventSystem.PressData).init(std.heap.page_allocator),
        };
    }

    pub fn deinit(self: *InputSystem) void {
        self.pressed.deinit();
    }

    pub fn pollSDL(self: *InputSystem) !bool {
        var sdl_event: c.sdl.SDL_Event = undefined;
        while (c.sdl.SDL_PollEvent(&sdl_event)) {
            switch (sdl_event.type) {
                c.sdl.SDL_EVENT_QUIT => {
                    return true;
                },
                c.sdl.SDL_EVENT_KEY_DOWN, c.sdl.SDL_EVENT_KEY_UP => {
                    const key = Keys.fromSDL(sdl_event.key.key);
                    const key_name = key.getName();
                    const is_key_pressed = self.pressed.contains(key_name);
                    if (sdl_event.type == c.sdl.SDL_EVENT_KEY_DOWN) {
                        if (is_key_pressed) {
                            const press = self.*.pressed.getPtr(key_name).?;
                            const tmp_dur = (sdl_event.key.timestamp / 1000000) - press.timestamp;
                            press.*.duration = if (tmp_dur > std.math.maxInt(u32))
                                std.math.maxInt(u32)
                            else
                                @intCast(tmp_dur);
                        } else {
                            const tmp_dur = sdl_event.key.timestamp / 1000000;
                            try self.pressed.put(key_name, .{
                                .key_code = key,
                                .timestamp = if (tmp_dur > std.math.maxInt(u32))
                                    std.math.maxInt(u32)
                                else
                                    @intCast(tmp_dur), // Convert to milliseconds
                                .duration = 0,
                            });
                        }
                    }
                    if (sdl_event.type == c.sdl.SDL_EVENT_KEY_UP and is_key_pressed) {
                        const event_name = try serializedKeyPress(self.event_manager, KeyBitfield.fromHashMap(self.pressed));
                        defer self.event_manager.allocator.free(event_name);

                        std.log.debug("{s}", .{event_name});
                        const event = EventSystem.createEvent(event_name, .{ .Keys = .{
                            .key = try self.pressed.clone(),
                        } }, .Sent);
                        self.*.event_manager.register(event);
                        _ = self.pressed.remove(key_name);
                    }
                },
                c.sdl.SDL_EVENT_MOUSE_BUTTON_DOWN, c.sdl.SDL_EVENT_MOUSE_BUTTON_UP => {},
                else => {},
            }
        }
        return false;
    }
};

pub fn serializedKeyPress(allocator: *EventSystem.EventManager, bitfield: KeyBitfield) ![]u8 {
    const modifiers = [_]Keys{
        .Key_LCTRL,             .Key_RCTRL,
        .Key_LSHIFT,            .Key_RSHIFT,
        .Key_LALT,              .Key_RALT,
        .Key_LGUI,              .Key_RGUI,
        .Key_LMETA,             .Key_RMETA,
        .Key_LHYPER,            .Key_RHYPER,
        .Key_CAPSLOCK,          .Key_NUMLOCKCLEAR,
        .Key_SCROLLLOCK,        .Key_LEVEL5_SHIFT,
        .Key_MULTI_KEY_COMPOSE,
    };

    var out = std.ArrayList(u8).init(allocator.allocator);
    defer out.deinit(); // Will clean up the list automatically
    var needs_separator = false;

    // Process modifiers first
    for (modifiers) |key| {
        if (bitfield.isBitSet(key)) {
            if (needs_separator) try out.appendSlice(" + ");
            try out.appendSlice(key.getName());
            needs_separator = true;
        }
    }

    // Process regular keys
    var key_value: u8 = 0;
    while (key_value < 255) : (key_value += 1) {
        const key = @as(Keys, @enumFromInt(key_value));

        // Skip modifiers
        const is_modifier = for (modifiers) |mod| {
            if (key == mod) break true;
        } else false;
        if (is_modifier) continue;

        if (bitfield.isBitSet(key)) {
            if (needs_separator) try out.appendSlice(" + ");
            try out.appendSlice(key.getName());
            needs_separator = true;
        }
    }

    // Copy the contents to a new owned slice
    return try allocator.allocator.dupe(u8, out.items);
}
