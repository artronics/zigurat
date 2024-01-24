const std = @import("std");
const Allocator = std.mem.Allocator;
const platform = @import("platform.zig");
const Backend = platform.WgpuBackend;
const data = @import("data.zig");
const Size = data.Size;
const gpu = @import("gpu");
const glfw = @import("glfw");

pub const Options = struct {
    headless: bool = false,
    title: [:0]const u8 = "Zigurat",
    size: Size = .{ .width = 2048 / 2, .height = 512 / 2 },
};

pub const Window = struct {
    const Self = @This();

    allocator: Allocator,
    size: Size,
    backend: *const Backend,
    window: glfw.Window,

    swap_chain: *gpu.SwapChain,
    surface: *gpu.Surface,

    // Backend is managed by client
    pub fn init(allocator: Allocator, backend: *const Backend, options: Options) !Self {
        // TODO: is keeping backend necessary? same for allocator
        // Create the test window and discover adapters using it (esp. for OpenGL)
        const backend_type = try detectBackendType();
        var hints = glfwWindowHintsForBackend(backend_type);
        hints.cocoa_retina_framebuffer = true;
        if (options.headless) {
            hints.visible = false; // Hiding window before creation otherwise you get the window showing up for a little bit then hiding.
        }
        const window = glfw.Window.create(
            options.size.width,
            options.size.height,
            options.title,
            null,
            null,
            hints,
        ) orelse switch (glfw.mustGetErrorCode()) {
            error.InvalidEnum,
            error.InvalidValue,
            error.FormatUnavailable,
            => unreachable,
            error.APIUnavailable,
            error.VersionUnavailable,
            error.PlatformError,
            => |err| return err,
            else => unreachable,
        };
        switch (backend_type) {
            .opengl, .opengles => {
                glfw.makeContextCurrent(window);
                glfw.getErrorCode() catch |err| switch (err) {
                    error.PlatformError => return err,
                    else => unreachable,
                };
            },
            else => {},
        }
        const surface = try createSurfaceForWindow(backend.instance, window, comptime detectGLFWOptions());

        const framebuffer_size = window.getFramebufferSize();
        const swap_chain_desc = gpu.SwapChain.Descriptor{
            .label = "main swap chain",
            .usage = .{ .render_attachment = true },
            .format = .bgra8_unorm,
            .width = framebuffer_size.width,
            .height = framebuffer_size.height,
            .present_mode = .mailbox,
        };
        const swap_chain = backend.device.createSwapChain(surface, &swap_chain_desc);

        return .{
            .allocator = allocator,
            .size = options.size,
            .backend = backend,
            .window = window,
            .swap_chain = swap_chain,
            .surface = surface,
        };
    }
    pub fn initCallbacks(self: *Self) void {
        self.window.setUserPointer(self);

        const window_size_callback = struct {
            fn callback(_window: glfw.Window, width: i32, height: i32) void {
                const _win = _window.getUserPointer(Self) orelse unreachable;
                _win.resize(.{ .width = @intCast(width), .height = @intCast(height) });
            }
        }.callback;
        self.window.setSizeCallback(window_size_callback);
        const framebuffer_size_callback = struct {
            fn callback(_window: glfw.Window, _: u32, _: u32) void {
                const _win = _window.getUserPointer(Self) orelse unreachable;
                _ = _win;
                std.log.warn("frame buffer resize", .{});
                // _win.swap_chain.present();
            }
        }.callback;
        self.window.setFramebufferSizeCallback(framebuffer_size_callback);
    }
    pub fn deinit(self: Self) void {
        self.swap_chain.release();
        self.surface.release();
    }
    pub inline fn pollEvents(self: Self) void {
        _ = self;
        glfw.pollEvents();
    }

    fn resize(self: *Self, size: Size) void {
        // std.log.warn("size: {d}:{d}", .{ size.width, size.height });
        self.size = size;
    }
};

fn getMaxRefreshRate(allocator: Allocator) u32 {
    const monitors = try glfw.Monitor.getAll(allocator);
    defer allocator.free(monitors);
    var max_refresh_rate: u32 = 0;
    for (monitors) |monitor| {
        const video_mode = monitor.getVideoMode() orelse continue;
        const refresh_rate = video_mode.getRefreshRate();
        max_refresh_rate = @max(max_refresh_rate, refresh_rate);
    }
    if (max_refresh_rate == 0) max_refresh_rate = 60;

    return max_refresh_rate;
}

fn createSurfaceForWindow(
    instance: *gpu.Instance,
    window: glfw.Window,
    comptime glfw_options: glfw.BackendOptions,
) !*gpu.Surface {
    const glfw_native = glfw.Native(glfw_options);
    if (glfw_options.win32) {
        return instance.createSurface(&gpu.Surface.Descriptor{
            .next_in_chain = .{
                .from_windows_hwnd = &.{
                    .hinstance = std.os.windows.kernel32.GetModuleHandleW(null).?,
                    .hwnd = glfw_native.getWin32Window(window),
                },
            },
        });
    } else if (glfw_options.x11) {
        return instance.createSurface(&gpu.Surface.Descriptor{
            .next_in_chain = .{
                .from_xlib_window = &.{
                    .display = glfw_native.getX11Display(),
                    .window = glfw_native.getX11Window(window),
                },
            },
        });
    } else if (glfw_options.wayland) {
        return instance.createSurface(&gpu.Surface.Descriptor{
            .next_in_chain = .{
                .from_wayland_surface = &.{
                    .display = glfw_native.getWaylandDisplay(),
                    .surface = glfw_native.getWaylandWindow(window),
                },
            },
        });
    } else if (glfw_options.cocoa) {
        const pool = try AutoReleasePool.init();
        defer AutoReleasePool.release(pool);

        const ns_window = glfw_native.getCocoaWindow(window);
        const ns_view = msgSend(ns_window, "contentView", .{}, *anyopaque); // [nsWindow contentView]

        // Create a CAMetalLayer that covers the whole window that will be passed to CreateSurface.
        msgSend(ns_view, "setWantsLayer:", .{true}, void); // [view setWantsLayer:YES]
        const layer = msgSend(objc_getClass("CAMetalLayer"), "layer", .{}, ?*anyopaque); // [CAMetalLayer layer]
        if (layer == null) @panic("failed to create Metal layer");
        msgSend(ns_view, "setLayer:", .{layer.?}, void); // [view setLayer:layer]

        // Use retina if the window was created with retina support.
        const scale_factor = msgSend(ns_window, "backingScaleFactor", .{}, f64); // [ns_window backingScaleFactor]
        msgSend(layer.?, "setContentsScale:", .{scale_factor}, void); // [layer setContentsScale:scale_factor]

        return instance.createSurface(&gpu.Surface.Descriptor{
            .next_in_chain = .{
                .from_metal_layer = &.{ .layer = layer.? },
            },
        });
    } else unreachable;
}

fn detectBackendType() !gpu.BackendType {
    const target = @import("builtin").target;
    if (target.isDarwin()) return .metal;
    if (target.os.tag == .windows) return .d3d12;
    return .vulkan;
}

fn glfwWindowHintsForBackend(backend: gpu.BackendType) glfw.Window.Hints {
    return switch (backend) {
        .opengl => .{
            // Ask for OpenGL 4.4 which is what the GL backend requires for compute shaders and
            // texture views.
            .context_version_major = 4,
            .context_version_minor = 4,
            .opengl_forward_compat = true,
            .opengl_profile = .opengl_core_profile,
        },
        .opengles => .{
            .context_version_major = 3,
            .context_version_minor = 1,
            .client_api = .opengl_es_api,
            .context_creation_api = .egl_context_api,
        },
        else => .{
            // Without this GLFW will initialize a GL context on the window, which prevents using
            // the window with other APIs (by crashing in weird ways).
            .client_api = .no_api,
        },
    };
}

fn detectGLFWOptions() glfw.BackendOptions {
    const target = @import("builtin").target;
    if (target.isDarwin()) return .{ .cocoa = true };
    return switch (target.os.tag) {
        .windows => .{ .win32 = true },
        .linux => .{ .x11 = true, .wayland = true },
        else => .{},
    };
}

const AutoReleasePool = if (!@import("builtin").target.isDarwin()) opaque {
    fn init() error{OutOfMemory}!?*AutoReleasePool {
        return null;
    }

    fn release(pool: ?*AutoReleasePool) void {
        _ = pool;
        return;
    }
} else opaque {
    fn init() error{OutOfMemory}!?*AutoReleasePool {
        // pool = [NSAutoreleasePool alloc];
        var pool = msgSend(objc_getClass("NSAutoreleasePool"), "alloc", .{}, ?*AutoReleasePool);
        if (pool == null) return error.OutOfMemory;

        // pool = [pool init];
        pool = msgSend(pool, "init", .{}, ?*AutoReleasePool);
        if (pool == null) unreachable;

        return pool;
    }

    fn release(pool: ?*AutoReleasePool) void {
        // [pool release];
        msgSend(pool, "release", .{}, void);
    }
};

// obj-c
// Extracted from `zig translate-c tmp.c` with `#include <objc/message.h>` in the file.
const SEL = opaque {};
const Class = opaque {};

extern fn sel_getUid(str: [*c]const u8) ?*SEL;
extern fn objc_getClass(name: [*c]const u8) ?*Class;
extern fn objc_msgSend() void;

// Borrowed from https://github.com/hazeycode/zig-objcrt
fn msgSend(obj: anytype, sel_name: [:0]const u8, args: anytype, comptime ReturnType: type) ReturnType {
    const args_meta = @typeInfo(@TypeOf(args)).Struct.fields;

    const FnType = switch (args_meta.len) {
        0 => *const fn (@TypeOf(obj), ?*SEL) callconv(.C) ReturnType,
        1 => *const fn (@TypeOf(obj), ?*SEL, args_meta[0].type) callconv(.C) ReturnType,
        2 => *const fn (@TypeOf(obj), ?*SEL, args_meta[0].type, args_meta[1].type) callconv(.C) ReturnType,
        3 => *const fn (@TypeOf(obj), ?*SEL, args_meta[0].type, args_meta[1].type, args_meta[2].type) callconv(.C) ReturnType,
        4 => *const fn (@TypeOf(obj), ?*SEL, args_meta[0].type, args_meta[1].type, args_meta[2].type, args_meta[3].type) callconv(.C) ReturnType,
        else => @compileError("Unsupported number of args"),
    };

    // NOTE: func is a var because making it const causes a compile error which I believe is a compiler bug
    const func = @as(FnType, @ptrCast(&objc_msgSend));
    const sel = sel_getUid(@as([*c]const u8, @ptrCast(sel_name)));

    return @call(.auto, func, .{ obj, sel } ++ args);
}
