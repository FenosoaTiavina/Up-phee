const std = @import("std");
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

    // Clear a bit for a specific key
    pub fn clearBit(self: *KeyBitfield, key: Keys) void {
        const key_value = @intFromEnum(key);
        const byte_index = key_value >> 3; // Divide by 8 to get byte index
        const bit_index = @as(u3, @truncate(key_value & 7)); // Modulo 8 to get bit position, as u3
        self.bits[byte_index] &= ~(@as(u8, 1) << bit_index);
    }

    // Check if a bit is set for a specific key
    pub fn isBitSet(self: KeyBitfield, key: Keys) bool {
        const key_value = @intFromEnum(key);
        const byte_index = key_value >> 3; // Divide by 8 to get byte index
        const bit_index = @as(u3, @truncate(key_value & 7)); // Modulo 8 to get bit position, as u3
        return (self.bits[byte_index] & (@as(u8, 1) << bit_index)) != 0;
    }

    // Convert from HashMap to KeyBitfield
    pub fn fromHashMap(key_map: std.StringHashMap(PressData)) KeyBitfield {
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

    // Get a unique hash for the bitfield
    pub fn getHash(self: KeyBitfield) u64 {
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, self.bits);
        return hasher.final();
    }

    // Check if two bitfields are equal
    pub fn equals(self: KeyBitfield, other: KeyBitfield) bool {
        return std.mem.eql(u8, &self.bits, &other.bits);
    }

    // Check if self contains all bits from other
    pub fn containsAll(self: KeyBitfield, other: KeyBitfield) bool {
        for (0..self.bits.len) |i| {
            // If any bit in other is not set in self, return false
            if ((other.bits[i] & self.bits[i]) != other.bits[i]) {
                return false;
            }
        }
        return true;
    }

    // Check if self contains any bit from other
    pub fn containsAny(self: KeyBitfield, other: KeyBitfield) bool {
        for (0..self.bits.len) |i| {
            // If any bit is common between self and other, return true
            if ((other.bits[i] & self.bits[i]) != 0) {
                return true;
            }
        }
        return false;
    }
};

// Import this to fix cross-dependencies
const PressData = @import("event.zig").PressData;
