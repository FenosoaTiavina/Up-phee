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

    pub fn serializedPressed(self: *InputSystem, bitfield: KeyBitfield) ![]u8 {
        // First pass: collect modifier keys
        var has_modifiers = false;
        var out = std.ArrayList(u8).init(self.event_manager.allocator);
        defer out.deinit();

        // Process modifiers in specific order
        // This ensures modifiers always appear in the same order regardless of key enum order
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

        // Process modifiers first
        for (modifiers) |mod_key| {
            if (bitfield.isBitSet(mod_key)) {
                if (has_modifiers) {
                    _ = try out.writer().write(" + ");
                }

                const key_name = mod_key.getName();
                _ = try out.writer().write(key_name);
                has_modifiers = true;
            }
        }

        // Second pass: collect regular keys
        var reg_key_count: u8 = 0;
        var key_value: usize = 0;

        // Maximum number of keys to check (adjust based on your enum)
        const max_keys = 256;

        while (key_value < max_keys) : (key_value += 1) {
            // Skip the key if it's a modifier
            const key = @as(Keys, @enumFromInt(key_value));

            // Skip the key if it's a modifier (already processed)
            var is_modifier = false;
            for (modifiers) |mod_key| {
                if (key == mod_key) {
                    is_modifier = true;
                    break;
                }
            }

            if (is_modifier) continue;

            // Check if key is pressed
            if (bitfield.isBitSet(key)) {
                if (has_modifiers or reg_key_count > 0) {
                    _ = try out.writer().write(" + ");
                }

                const key_name = key.getName();
                _ = try out.writer().write(key_name);
                has_modifiers = true;
                reg_key_count += 1;
            }
        }
        return out.items;
    }

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
                    const ev = EventSystem.createEvent("quit", .{
                        .System = .{
                            .id_event = @intFromEnum(EventSystem.EventID.Quit),
                            .event = .Quit,
                        },
                    });
                    _ = ev; // autofix
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
                        const bitfield = KeyBitfield.fromHashMap(self.pressed);
                        const keydebug = try self.serializedPressed(bitfield);
                        std.log.debug("{s}", .{keydebug});
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
