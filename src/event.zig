const std = @import("std");
// pub const input = @import("input.zig");
//
// pub fn createEvent(name: []u8, data: EventData) Event {
//     return EventTypes.createEvent(name, data);
// }
//
// pub const EventCallback = struct {
//     func: *const fn (*EventManager, *EventMap, *f32, *anyopaque) bool,
//     context: *anyopaque,
//
//     pub fn init(
//         context: *anyopaque,
//         func: *const fn (*EventManager, *EventMap, *f32, *anyopaque) bool,
//     ) EventCallback {
//         return .{
//             .func = func,
//             .context = context,
//         };
//     }
//
//     pub fn invoke(self: *const EventCallback, event_manager: *EventManager, delta_time: *f32, triggers: *EventMap) bool {
//         return self.func(event_manager, triggers, delta_time, self.context);
//     }
// };
//
// pub const EventManager = struct {
//     allocator: std.mem.Allocator,
//     handlers: std.StringHashMap(HandlerData),
//     delta_time: *f32,
//
//     const HandlerData = struct { trigger: EventMap, individual: bool, callback: EventCallback };
//
//     pub fn init(allocator: std.mem.Allocator, delta_t: *f32) !EventManager {
//         return .{
//             .allocator = allocator,
//             .handlers = std.StringHashMap(HandlerData).init(allocator),
//             .delta_time = delta_t,
//         };
//     }
//
//     pub fn deinit(self: *EventManager) void {
//         // Free all handler entries
//         var handler_iter = self.handlers.iterator();
//         while (handler_iter.next()) |entry| {
//             self.allocator.free(entry.key_ptr.*);
//         }
//         self.handlers.deinit();
//     }
//
//     pub fn subscribe(self: *EventManager, listen_for: EventMap, individual: bool, callback: EventCallback) !void {
//         const event_string = try listen_for.serialize(self.allocator);
//
//         if (!self.handlers.contains(event_string)) {
//             try self.handlers.put(
//                 event_string,
//                 .{
//                     .callback = callback,
//                     .individual = individual,
//                     .trigger = listen_for,
//                 },
//             );
//         }
//     }
//
//     pub fn dispatch(self: *EventManager, event_map: *EventMap) !void {
//         const event_string = try event_map.serialize(self.allocator);
//         defer self.allocator.free(event_string);
//
//         var it = self.handlers.iterator();
//
//         while (it.next()) |callback_pair| {
//             if (try EventMap.check_keys(callback_pair.value_ptr.*.trigger, event_map.*, callback_pair.value_ptr.individual, self.allocator)) {
//                 _ = callback_pair.value_ptr.*.callback.invoke(self, self.delta_time, @constCast(event_map));
//             }
//
//             if (try EventMap.check_motion(callback_pair.value_ptr.*.trigger, event_map.*, self.allocator)) {
//                 _ = callback_pair.value_ptr.*.callback.invoke(self, self.delta_time, @constCast(event_map));
//             }
//         }
//         event_map.deinit();
//     }
// };
