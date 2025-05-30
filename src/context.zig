const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const bos = @import("build_options");

const config = @import("config.zig");
const uph = @import("uph.zig");
const PluginSystem = uph.PluginSystem;
const sdl = uph.clib.sdl;
const c = uph.clib;
const zgui = uph.zgui;
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
        deltaTime: *const fn (ctx: *anyopaque) f32,
        fps: *const fn (ctx: *anyopaque) f32,
        window: *const fn (ctx: *anyopaque) *uph.Renderer.Window,
        renderer: *const fn (ctx: *anyopaque) *uph.Renderer,
        kill: *const fn (ctx: *anyopaque, bool) void,
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
    pub fn deltaTime(self: Context) f32 {
        return self.vtable.deltaTime(self.ctx);
    }

    /// Get FPS of application
    pub fn fps(self: Context) f32 {
        return self.vtable.fps(self.ctx);
    }

    /// Get SDL window
    pub fn window(self: Context) *uph.Renderer.Window {
        return self.vtable.window(self.ctx);
    }

    /// Get SDL renderer
    pub fn eventManger(self: Context) *uph.Events.EventManager {
        return self.vtable.eventManager(self.ctx);
    }

    pub fn renderer(self: Context) *uph.Renderer {
        return self.vtable.renderer(self.ctx);
    }

    /// Kill application
    pub fn kill(self: Context, b: bool) void {
        return self.vtable.kill(self.ctx, b);
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
        _window: *uph.Renderer.Window = undefined,
        // Renderer instance
        _renderer: *uph.Renderer = undefined,

        _plugin_system: *PluginSystem = undefined,

        _aspect_ratio: f32 = undefined,

        // High DPI stuff
        _default_dpi: f32 = undefined,
        _display_dpi: f32 = undefined,

        // Elapsed time of game
        _seconds: f32 = 0,
        _seconds_real: f64 = 0,

        // Delta time between update/draw
        _last_tick: u64 = 0,
        _delta_time: f32 = 0,

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

            // Init SDL window and renderer
            self._renderer = @constCast(try uph.Renderer.init(
                self.context().allocator(),
                self.context().cfg().uph_window_size.custom.width,
                self.context().cfg().uph_window_size.custom.height,
                self.context().cfg().uph_window_title,
            ));

            self._window = &self._renderer.window;

            uph.Input.init(self._ctx);

            // Init plugin system
            if (bos.link_dynamic) {
                self._plugin_system = try PluginSystem.create(self.context());
            }

            // Misc.
            return self;
        }

        pub fn ctx_config(self: *@This(), _cfg: uph.Config.Config) !void {
            self._cfg = _cfg;
            try PluginSystem.config(self.context());
        }

        pub fn destroy(self: *@This()) void {

            // Destroy plugin system
            if (bos.link_dynamic) {
                self._plugin_system.destroy(self._ctx);
            }

            // Destroy window and renderer
            self._renderer.deinit();

            // Destory self
            self._allocator.destroy(self);

            log.debug("Kitten Bye!!", .{});
            // Check memory leak if possible
            if (cfg.uph_check_memory_leak) {
                _ = debug_allocator.deinit();
            }
        }

        /// Ticking of application
        pub fn tick(
            self: *@This(),
            comptime eventFn: *const fn (Context, uph.Input.Event) anyerror!void,
            comptime updateFn: *const fn (Context) anyerror!void,
            comptime drawFn: *const fn (Context) anyerror!void,
        ) void {

            // Update game
            self._update(eventFn, updateFn);

            const new_ticks: u64 = c.sdl.SDL_GetTicks();
            self._delta_time = @as(f32, @floatFromInt(new_ticks - self._last_tick)) / 1000;
            self._last_tick = new_ticks;

            // Do rendering
            if (self._renderer.pipelines.count() > 0) {
                self.context().renderer().beginFrame() catch |err| {
                    log.err("Got error in `beginFrame`: {s}", .{@errorName(err)});
                    if (@errorReturnTrace()) |trace| {
                        std.debug.dumpStackTrace(trace.*);
                        kill(self, true);
                        return;
                    }
                };

                drawFn(self._ctx) catch |err| {
                    log.err("Got error in `draw`: {s}", .{@errorName(err)});
                    if (@errorReturnTrace()) |trace| {
                        std.debug.dumpStackTrace(trace.*);
                        kill(self, true);
                        return;
                    }
                };

                if (bos.link_dynamic) {
                    self._plugin_system.draw(self._ctx);
                }

                self._renderer.submitFrame() catch |err| {
                    log.err("Got error in `submitFrame`: {s}", .{@errorName(err)});
                    if (@errorReturnTrace()) |trace| {
                        std.debug.dumpStackTrace(trace.*);
                        kill(self, true);
                    }
                };
            }

            self._updateFrameStats();
        }

        /// Update game state
        inline fn _update(
            self: *@This(),
            comptime eventFn: *const fn (Context, uph.Input.Event) anyerror!void,
            comptime updateFn: *const fn (Context) anyerror!void,
        ) void {
            while (uph.Input.pollNativeEvent()) |ne| {

                // Game event processing
                const we = uph.Input.Event.from(ne);
                uph.Input.input_manager.update(we);

                // Passed to game code
                eventFn(self._ctx, we) catch |err| {
                    log.err("Got error in `event`: {s}", .{@errorName(err)});
                    if (@errorReturnTrace()) |trace| {
                        std.debug.dumpStackTrace(trace.*);
                        kill(self, true);
                        return;
                    }
                };
                if (bos.link_dynamic) {
                    self._plugin_system.event(self._ctx, we);
                }
            }

            updateFn(self._ctx) catch |err| {
                log.err("Got error in `update`: {s}", .{@errorName(err)});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                    kill(self, true);
                    return;
                }
            };
            if (bos.link_dynamic) {
                self._plugin_system.update(self._ctx);
            }
        }

        /// Update frame stats once per second
        inline fn _updateFrameStats(self: *@This()) void {
            _ = self; // autofix
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
                    .deltaTime = deltaTime,
                    .fps = fps,
                    .window = window,
                    .renderer = renderer,
                    .kill = kill,
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
        fn deltaTime(ptr: *anyopaque) f32 {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return self._delta_time;
        }

        /// Get FPS of application
        fn fps(ptr: *anyopaque) f32 {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            _ = self; // autofix
            return 0;
        }

        /// Get window
        fn window(ptr: *anyopaque) *uph.Renderer.Window {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return self._window;
        }

        /// Get renderer
        fn renderer(ptr: *anyopaque) *uph.Renderer {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return self._renderer;
        }

        /// Kill app
        fn kill(ptr: *anyopaque, b: bool) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self._running = !b;
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
