const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const bos = @import("build_options");
const config = @import("config.zig");
// const PluginSystem = @import("PluginSystem.zig");
const uph = @import("uph.zig");
const sdl = uph.clib.sdl;
const c = uph.clib;
const zgui = uph.zgui;
const io = uph.Events.input.InputSystem;
const plot = zgui.plot;
const log = std.log.scoped(.uph);

/// Application context
pub const Context = struct {
    ctx: *anyopaque,
    vtable: struct {
        cfg: *const fn (ctx: *anyopaque) config.Config,
        allocator: *const fn (ctx: *anyopaque) std.mem.Allocator,
        seconds: *const fn (ctx: *anyopaque) f32,
        realSeconds: *const fn (ctx: *anyopaque) f64,
        deltaSeconds: *const fn (ctx: *anyopaque) f32,
        fps: *const fn (ctx: *anyopaque) f32,
        window: *const fn (ctx: *anyopaque) uph.Window,
        renderer: *const fn (ctx: *anyopaque) uph.Renderer,
        kill: *const fn (ctx: *anyopaque) void,
        displayStats: *const fn (ctx: *anyopaque, opt: DisplayStats) void,
        debugPrint: *const fn (ctx: *anyopaque, text: []const u8, opt: DebugPrint) void,
        registerPlugin: *const fn (ctx: *anyopaque, name: []const u8, path: []const u8, hotreload: bool) anyerror!void,
        unregisterPlugin: *const fn (ctx: *anyopaque, name: []const u8) anyerror!void,
        forceReloadPlugin: *const fn (ctx: *anyopaque, name: []const u8) anyerror!void,
    },

    /// Get setup configuration
    pub fn cfg(self: Context) config.Config {
        return self.vtable.cfg(self.ctx);
    }

    /// Get meomry allocator
    pub fn allocator(self: Context) std.mem.Allocator {
        return self.vtable.allocator(self.ctx);
    }

    /// Get running seconds of application
    pub fn seconds(self: Context) f32 {
        return self.vtable.seconds(self.ctx);
    }

    /// Get running seconds of application (double precision)
    pub fn realSeconds(self: Context) f64 {
        return self.vtable.realSeconds(self.ctx);
    }

    /// Get delta time between frames
    pub fn deltaSeconds(self: Context) f32 {
        return self.vtable.deltaSeconds(self.ctx);
    }

    /// Get FPS of application
    pub fn fps(self: Context) f32 {
        return self.vtable.fps(self.ctx);
    }

    /// Get SDL window
    pub fn window(self: Context) uph.Window.Window {
        return self.vtable.window(self.ctx);
    }

    /// Get SDL renderer
    pub fn renderer(self: Context) uph.Renderer.Renderer {
        return self.vtable.renderer(self.ctx);
    }

    /// Kill application
    pub fn kill(self: Context) void {
        return self.vtable.kill(self.ctx);
    }

    /// Get size of canvas
    /// Display statistics
    pub fn displayStats(self: Context, opt: DisplayStats) void {
        return self.vtable.displayStats(self.ctx, opt);
    }

    /// Register new plugin
    pub fn registerPlugin(self: Context, name: []const u8, path: []const u8, hotreload: bool) !void {
        try self.vtable.registerPlugin(self.ctx, name, path, hotreload);
    }

    /// Unregister plugin
    pub fn unregisterPlugin(self: Context, name: []const u8) !void {
        try self.vtable.unregisterPlugin(self.ctx, name);
    }

    ///  Force reload plugin
    pub fn forceReloadPlugin(self: Context, name: []const u8) !void {
        try self.vtable.forceReloadPlugin(self.ctx, name);
    }
};

pub const DisplayStats = struct {
    movable: bool = false,
    collapsible: bool = false,
    width: f32 = 250,
    duration: u32 = 15,
};

pub const DebugPrint = struct {
    pos: uph.Types.Point = .origin,
    color: uph.Types.Color = .white,
};

/// Context generator
pub fn uphContext(comptime cfg: config.Config) type {
    const DebugAllocatorType = std.heap.DebugAllocator(.{
        .safety = true,
        .enable_memory_limit = true,
    });

    return struct {
        var debug_allocator: DebugAllocatorType = .init;
        const max_costs_num = 300;
        /// Setup configuration
        _cfg: config.Config = cfg,

        // Application Context
        _ctx: Context = undefined,

        // Memory allocator
        _allocator: std.mem.Allocator = undefined,

        // Is running
        _running: bool = true,

        // Internal window
        _window: uph.Window.Window = undefined,

        // High DPI stuff
        _default_dpi: f32 = undefined,
        _display_dpi: f32 = undefined,

        // Renderer instance
        _renderer: uph.Renderer.Renderer = undefined,

        // Event Manager
        _ev_manager: uph.Events.EventManager = undefined,

        // Elapsed time of game
        _seconds: f32 = 0,
        _seconds_real: f64 = 0,

        // Delta time between update/draw
        _delta_seconds: f32 = 0,

        // Frames stats
        _fps: f32 = 0,
        _pc_last: u64 = 0,
        _pc_accumulated: u64 = 0,
        _pc_freq: u64 = 0,
        _pc_max_accumulated: u64 = 0,
        _drawcall_count: u32 = 0,
        _triangle_count: u32 = 0,
        _frame_count: u32 = 0,
        _last_fps_refresh_time: f64 = 0,
        _last_costs_refresh_time: f64 = 0,
        _update_cost: f32 = 0,
        _draw_cost: f32 = 0,

        pub fn create() !*@This() {
            var _allocator = if (builtin.cpu.arch.isWasm())
                std.heap.c_allocator
            else if (cfg.uph_check_memory_leak)
                debug_allocator.allocator()
            else
                std.heap.smp_allocator;
            var self = try _allocator.create(@This());
            self.* = .{};
            self._allocator = _allocator;
            self._ctx = self.context();

            // Init main-thread id
            _ = uph.utils.isMainThread();

            // Init SDL window and renderer
            self._renderer = uph.Renderer.Renderer.init(
                self.context().allocator(),
                self.context().cfg().uph_window_size.custom.width,
                self.context().cfg().uph_window_size.custom.height,
                self.context().cfg().uph_window_title,
            );

            // Init imgui
            zgui.init(self.context().allocator());

            zgui.getStyle().setColorsDark();
            zgui.backend.init(self.context().window().sdl_window, .{
                .device = self.context().renderer().device.?,
                .color_target_format = c.sdl.SDL_GetGPUSwapchainTextureFormat(
                    self.context().renderer().device.?,
                    self.context().window().sdl_window,
                ),
                .msaa_samples = c.sdl.SDL_GPU_SAMPLECOUNT_1,
            });

            // Init plugin system
            // if (bos.link_dynamic) {
            //     self._plugin_system = try PluginSystem.create(self._allocator);
            // }

            // Misc.
            self._pc_freq = sdl.SDL_GetPerformanceFrequency();
            self._pc_max_accumulated = self._pc_freq / 2;
            self._pc_last = sdl.SDL_GetPerformanceCounter();
            return self;
        }

        pub fn destroy(self: *@This()) void {

            // Destroy plugin system
            // if (bos.link_dynamic) {
            //     self._plugin_system.destroy(self._ctx);
            // }

            // Destroy imgui
            zgui.backend.deinit();
            zgui.deinit();

            // Destroy window and renderer
            self._renderer.deinit();

            // Destory self
            self._allocator.destroy(self);

            // Check memory leak if possible
            if (cfg.uph_check_memory_leak) {
                _ = debug_allocator.deinit();
            }
        }

        /// Ticking of application
        pub fn tick(
            self: *@This(),
            comptime eventFn: *const fn (Context, uph.Events.EventManager) anyerror!void,
            comptime updateFn: *const fn (Context) anyerror!void,
            comptime drawFn: *const fn (Context) anyerror!void,
        ) void {
            const pc_threshold: u64 = switch (cfg.uph_fps_limit) {
                .none => 0,
                .auto => 0,
                .manual => |_fps| self._pc_freq / @as(u64, _fps),
            };

            // Update game
            if (pc_threshold > 0) {
                while (true) {
                    const pc = sdl.SDL_GetPerformanceCounter();
                    self._pc_accumulated += pc - self._pc_last;
                    self._pc_last = pc;
                    if (self._pc_accumulated >= pc_threshold) {
                        break;
                    }
                    if ((pc_threshold - self._pc_accumulated) * 1000 > self._pc_freq) {
                        sdl.SDL_Delay(1);
                    }
                }

                if (self._pc_accumulated > self._pc_max_accumulated)
                    self._pc_accumulated = self._pc_max_accumulated;

                // Perform as many update as we can, with fixed step
                var step_count: u32 = 0;
                const fps_delta_seconds: f32 = @floatCast(
                    @as(f64, @floatFromInt(pc_threshold)) / @as(f64, @floatFromInt(self._pc_freq)),
                );
                while (self._pc_accumulated >= pc_threshold) {
                    step_count += 1;
                    self._pc_accumulated -= pc_threshold;
                    self._delta_seconds = fps_delta_seconds;
                    self._seconds += self._delta_seconds;
                    self._seconds_real += self._delta_seconds;

                    self._update(eventFn, updateFn);
                }
                assert(step_count > 0);

                self._delta_seconds = @as(f32, @floatFromInt(step_count)) * fps_delta_seconds;
            } else {
                // Perform one update
                const pc = sdl.SDL_GetPerformanceCounter();
                self._delta_seconds = @floatCast(
                    @as(f64, @floatFromInt(pc - self._pc_last)) / @as(f64, @floatFromInt(self._pc_freq)),
                );
                self._pc_last = pc;
                self._seconds += self._delta_seconds;
                self._seconds_real += self._delta_seconds;

                self._update(eventFn, updateFn);
            }

            // Do rendering
            {
                const pc_begin = sdl.SDL_GetPerformanceCounter();
                defer if (cfg.uph_detailed_frame_stats) {
                    const cost = @as(f32, @floatFromInt((sdl.SDL_GetPerformanceCounter() - pc_begin) * 1000)) /
                        @as(f32, @floatFromInt(self._pc_freq));
                    self._draw_cost = if (self._draw_cost > 0) (self._draw_cost + cost) / 2 else cost;
                };

                defer self._renderer.present();

                const fb_scale = c.sdl.SDL_GetWindowDisplayScale(self.context().window().sdl_window);

                zgui.backend.newFrame(
                    @intCast(self.context().cfg().uph_window_size.custom.width),
                    @intCast(self.context().cfg().uph_window_size.custom.height),
                    fb_scale,
                );
                zgui.newFrame(self.context());
                defer zgui.backend.render();

                try self.context().renderer().beginDraw();
                try self.context().renderer().draw(self.context());

                drawFn(self._ctx) catch |err| {
                    log.err("Got error in `draw`: {s}", .{@errorName(err)});
                    if (@errorReturnTrace()) |trace| {
                        std.debug.dumpStackTrace(trace.*);
                        kill(self);
                        return;
                    }
                };
                try self.context().renderer().endDraw();

                if (bos.link_dynamic) {
                    self._plugin_system.draw(self._ctx);
                }
            }

            self._updateFrameStats();
        }

        /// Update game state
        inline fn _update(
            self: *@This(),
            comptime eventFn: *const fn (Context, uph.Events.EventManager) anyerror!void,
            comptime updateFn: *const fn (Context) anyerror!void,
        ) void {
            const pc_begin = sdl.SDL_GetPerformanceCounter();
            defer if (cfg.uph_detailed_frame_stats) {
                const cost = @as(f32, @floatFromInt((sdl.SDL_GetPerformanceCounter() - pc_begin) * 1000)) /
                    @as(f32, @floatFromInt(self._pc_freq));
                self._update_cost = if (self._update_cost > 0) (self._update_cost + cost) / 2 else cost;
            };

            eventFn(self._ctx, self._ev_manager);

            updateFn(self._ctx) catch |err| {
                log.err("Got error in `update`: {s}", .{@errorName(err)});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                    kill(self);
                    return;
                }
            };
            // if (bos.link_dynamic) {
            //     self._plugin_system.update(self._ctx);
            // }
        }

        /// Update frame stats once per second
        inline fn _updateFrameStats(self: *@This()) void {
            self._frame_count += 1;
            if ((self._seconds_real - self._last_fps_refresh_time) >= 1) {
                const duration = self._seconds_real - self._last_fps_refresh_time;
                self._fps = @as(f32, @floatCast(
                    @as(f64, @floatFromInt(self._frame_count)) / duration,
                ));
                self._last_fps_refresh_time = self._seconds_real;
                self._frame_count = 0;
            }
            if (cfg.uph_detailed_frame_stats and (self._seconds_real - self._last_costs_refresh_time) >= 0.1) {
                self._last_costs_refresh_time = self._seconds_real;
                self._update_cost = 0;
                self._draw_cost = 0;
            }
        }

        /// Check system information
        fn checkSys(self: *@This()) !void {
            const target = builtin.target;
            var sdl_version: sdl.SDL_version = undefined;
            sdl.SDL_GetVersion(&sdl_version);
            const ram_size = sdl.SDL_GetSystemRAM();
            const info = try self._renderer.getInfo();

            // Print system info
            try std.fmt.format(
                std.io.getStdErr().writer(),
                \\System info:
                \\    Build Mode  : {s}
                \\    Log Level   : {s}
                \\    Zig Version : {}
                \\    CPU         : {s}
                \\    ABI         : {s}
                \\    SDL         : {}.{}.{}
                \\    Platform    : {s}
                \\    Memory      : {d}MB
                \\    App Dir     : {s} 
                \\    
                \\Renderer info:
                \\    Driver           : {s}
                \\    Vertical Sync    : {}
                \\    Max Texture Size : {d}*{d}
                \\
                \\
            ,
                .{
                    @tagName(builtin.mode),
                    @tagName(cfg.uph_log_level),
                    builtin.zig_version,
                    @tagName(target.cpu.arch),
                    @tagName(target.abi),
                    sdl_version.major,
                    sdl_version.minor,
                    sdl_version.patch,
                    @tagName(target.os.tag),
                    ram_size,
                    info.name,
                    info.flags & sdl.SDL_RENDERER_PRESENTVSYNC != 0,
                    info.max_texture_width,
                    info.max_texture_height,
                },
            );

            if (sdl_version.major < 2 or (sdl_version.minor == 0 and sdl_version.patch < 18)) {
                log.err("SDL version too low, need at least 2.0.18", .{});
                return sdl.Error.SdlError;
            }
        }

        /// Get type-erased context for application
        pub fn context(self: *@This()) Context {
            return .{
                .ctx = self,
                .vtable = .{
                    .cfg = getcfg,
                    .allocator = allocator,
                    .seconds = seconds,
                    .realSeconds = realSeconds,
                    .deltaSeconds = deltaSeconds,
                    .fps = fps,
                    .window = window,
                    .renderer = renderer,
                    .canvas = canvas,
                    .kill = kill,
                    .displayStats = displayStats,
                    .registerPlugin = registerPlugin,
                    .unregisterPlugin = unregisterPlugin,
                    .forceReloadPlugin = forceReloadPlugin,
                },
            };
        }

        ///////////////////// Wrapped API for Application Context //////////////////

        /// Get setup configuration
        fn getcfg(ptr: *anyopaque) config.Config {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return self._cfg;
        }

        /// Get meomry allocator
        fn allocator(ptr: *anyopaque) std.mem.Allocator {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return self._allocator;
        }

        /// Get running seconds of application
        fn seconds(ptr: *anyopaque) f32 {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return self._seconds;
        }

        /// Get running seconds of application (double precision)
        fn realSeconds(ptr: *anyopaque) f64 {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return self._seconds_real;
        }

        /// Get delta time between frames
        fn deltaSeconds(ptr: *anyopaque) f32 {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return self._delta_seconds;
        }

        /// Get FPS of application
        fn fps(ptr: *anyopaque) f32 {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return self._fps;
        }

        /// Get SDL window
        fn window(ptr: *anyopaque) uph.Window {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return self._window;
        }

        /// Get SDL renderer
        fn renderer(ptr: *anyopaque) uph.Renderer {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return self._renderer;
        }

        /// Get canvas texture
        fn canvas(ptr: *anyopaque) uph.Texture {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return self._canvas_texture;
        }

        /// Kill app
        fn kill(ptr: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self._running = false;
        }

        /// Display frame statistics
        fn displayStats(ptr: *anyopaque, opt: DisplayStats) void {
            _ = ptr; // autofix
            _ = opt; // autofix
            // const self: *@This() = @ptrCast(@alignCast(ptr));
            // const rdinfo = self._renderer.getInfo() catch unreachable;
            // const ws = self._window.getSize();
            // const cs = getCanvasSize(ptr);
            // imgui.setNextWindowBgAlpha(.{ .alpha = 0.7 });
            // imgui.setNextWindowPos(.{
            //     .x = @floatFromInt(ws.width),
            //     .y = 0,
            //     .pivot_x = 1,
            //     .cond = if (opt.movable) .once else .always,
            // });
            // imgui.setNextWindowSize(.{ .w = opt.width * getDpiScale(ptr), .h = 0, .cond = .always });
            // if (imgui.begin("Frame Statistics", .{
            //     .flags = .{
            //         .no_title_bar = !opt.collapsible,
            //         .no_resize = true,
            //         .always_auto_resize = true,
            //     },
            // })) {
            //     imgui.text("Window Size: {d:.0}x{d:.0}", .{ ws.width, ws.height });
            //     imgui.text("Canvas Size: {d:.0}x{d:.0}", .{ cs.width, cs.height });
            //     imgui.text("Display DPI: {d:.1}", .{self._display_dpi});
            //     imgui.text("V-Sync Enabled: {}", .{rdinfo.flags & sdl.SDL_RENDERER_PRESENTVSYNC != 0});
            //     imgui.text("Optimize Mode: {s}", .{@tagName(builtin.mode)});
            //     imgui.separator();
            //     imgui.text("Duration: {}", .{std.fmt.fmtDuration(@intFromFloat(self._seconds_real * 1e9))});
            //     if (self._running_slow) {
            //         imgui.textColored(.{ 1, 0, 0, 1 }, "FPS: {d:.1} {s}", .{ self._fps, cfg.uph_fps_limit.str() });
            //         imgui.textColored(.{ 1, 0, 0, 1 }, "CPU: {d:.1}ms", .{1000.0 / self._fps});
            //     } else {
            //         imgui.text("FPS: {d:.1} {s}", .{ self._fps, cfg.uph_fps_limit.str() });
            //         imgui.text("CPU: {d:.1}ms", .{1000.0 / self._fps});
            //     }
            //     if (builtin.mode == .Debug) {
            //         imgui.text("Memory: {:.3}", .{std.fmt.fmtIntSizeBin(debug_allocator.total_requested_bytes)});
            //     }
            //     imgui.text("Draw Calls: {d}", .{self._drawcall_count});
            //     imgui.text("Triangles: {d}", .{self._triangle_count});
            //
            //     if (cfg.uph_detailed_frame_stats and self._seconds_real > 1) {
            //         imgui.separator();
            //         if (plot.beginPlot(
            //             imgui.formatZ("Costs of Update/Draw ({}s)", .{opt.duration}),
            //             .{
            //                 .h = opt.width * 3 / 4,
            //                 .flags = .{ .no_menus = true },
            //             },
            //         )) {
            //             plot.setupLegend(
            //                 .{ .south = true },
            //                 .{ .horizontal = true, .outside = true },
            //             );
            //             plot.setupAxisLimits(.x1, .{
            //                 .min = 0,
            //                 .max = @floatFromInt(@min(max_costs_num, opt.duration * 10)),
            //             });
            //             plot.setupAxisLimits(.y1, .{
            //                 .min = 0,
            //                 .max = @max(20, self._update_cost + self._draw_cost + 5),
            //             });
            //             plot.setupAxis(.x1, .{
            //                 .flags = .{
            //                     .no_label = true,
            //                     .no_tick_labels = true,
            //                     .no_highlight = true,
            //                     .lock_min = true,
            //                     .lock_max = true,
            //                 },
            //             });
            //             plot.setupAxis(.y1, .{
            //                 .flags = .{
            //                     .no_label = true,
            //                     .no_highlight = true,
            //                     .lock_min = true,
            //                 },
            //             });
            //             plot.pushStyleColor4f(.{
            //                 .idx = .frame_bg,
            //                 .c = .{ 0.1, 0.1, 0.1, 0.1 },
            //             });
            //             plot.pushStyleColor4f(.{
            //                 .idx = .plot_bg,
            //                 .c = .{ 0.2, 0.2, 0.2, 0.2 },
            //             });
            //             defer plot.popStyleColor(.{ .count = 2 });
            //             var update_costs: [max_costs_num]f32 = undefined;
            //             var draw_costs: [max_costs_num]f32 = undefined;
            //             var total_costs: [max_costs_num]f32 = undefined;
            //             const size = @min(self._recent_update_costs.len(), opt.duration * 10);
            //             var costs = self._recent_update_costs.sliceLast(size);
            //             @memcpy(update_costs[0..costs.first.len], costs.first);
            //             @memcpy(update_costs[costs.first.len .. costs.first.len + costs.second.len], costs.second);
            //             costs = self._recent_draw_costs.sliceLast(size);
            //             @memcpy(draw_costs[0..costs.first.len], costs.first);
            //             @memcpy(draw_costs[costs.first.len .. costs.first.len + costs.second.len], costs.second);
            //             costs = self._recent_total_costs.sliceLast(size);
            //             @memcpy(total_costs[0..costs.first.len], costs.first);
            //             @memcpy(total_costs[costs.first.len .. costs.first.len + costs.second.len], costs.second);
            //             plot.plotLineValues("update", f32, .{
            //                 .v = update_costs[0..size],
            //             });
            //             plot.plotLineValues("draw", f32, .{
            //                 .v = draw_costs[0..size],
            //             });
            //             plot.plotLineValues("update+draw", f32, .{
            //                 .v = total_costs[0..size],
            //             });
            //             plot.endPlot();
            //         }
            //     }
            // }
            // imgui.end();
        }

        /// Register new plugin
        pub fn registerPlugin(ptr: *anyopaque, name: []const u8, path: []const u8, hotreload: bool) !void {
            if (!bos.link_dynamic) {
                @panic("plugin system isn't enabled!");
            }
            const self: *@This() = @ptrCast(@alignCast(ptr));
            try self._plugin_system.register(
                self.context(),
                name,
                path,
                hotreload,
            );
        }

        /// Unregister plugin
        pub fn unregisterPlugin(ptr: *anyopaque, name: []const u8) !void {
            if (!bos.link_dynamic) {
                @panic("plugin system isn't enabled!");
            }
            const self: *@This() = @ptrCast(@alignCast(ptr));
            try self._plugin_system.unregister(self.context(), name);
        }

        ///  Force reload plugin
        pub fn forceReloadPlugin(ptr: *anyopaque, name: []const u8) !void {
            if (!bos.link_dynamic) {
                @panic("plugin system isn't enabled!");
            }
            const self: *@This() = @ptrCast(@alignCast(ptr));
            try self._plugin_system.forceReload(name);
        }
    };
}
