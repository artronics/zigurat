const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.zigurat);
const glfw = @import("glfw");
const gpu = @import("gpu");
const d = @import("data.zig");

pub const WgpuBackend = struct {
    const Self = @This();

    allocator: Allocator,
    window: glfw.Window,
    device: *gpu.Device,
    swap_chain: *gpu.SwapChain,
    surface: *gpu.Surface,
    queue: *gpu.Queue,

    pub fn init(allocator: Allocator, options: Options) !Self {
        try gpu.Impl.init(allocator, .{});

        glfw.setErrorCallback(errorCallback);
        if (!glfw.init(.{})) {
            glfw.getErrorCode() catch |err| switch (err) {
                error.PlatformError,
                error.PlatformUnavailable,
                => return err,
                else => unreachable,
            };
        }

        // Create the test window and discover adapters using it (esp. for OpenGL)
        const backend_type = try detectBackendType();
        var hints = glfwWindowHintsForBackend(backend_type);
        hints.cocoa_retina_framebuffer = true;
        if (options.headless) {
            hints.visible = false; // Hiding window before creation otherwise you get the window showing up for a little bit then hiding.
        }

        // _ = getMaxRefreshRate(allocator);

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

        const instance = gpu.createInstance(null) orelse {
            std.debug.print("failed to create GPU instance", .{});
            std.process.exit(1);
        };

        const surface = try createSurfaceForWindow(instance, window, comptime detectGLFWOptions());

        // Adapter
        var response: RequestAdapterResponse = undefined;
        instance.requestAdapter(&gpu.RequestAdapterOptions{
            .compatible_surface = surface,
            .power_preference = options.power_preference,
            .force_fallback_adapter = .false,
        }, &response, requestAdapterCallback);
        if (response.status != .success) {
            log.err("failed to create GPU adapter: {?s}", .{response.message});
            std.process.exit(1);
        }
        var props = std.mem.zeroes(gpu.Adapter.Properties);
        response.adapter.?.getProperties(&props);
        if (props.backend_type == .null) {
            log.err("no backend found for {s} adapter", .{props.adapter_type.name()});
            std.process.exit(1);
        }
        // Print which adapter we are going to use.
        log.info("found {s} backend on {s} adapter: {s}, {s}\n", .{
            props.backend_type.name(),
            props.adapter_type.name(),
            props.name,
            props.driver_description,
        });

        // Create a device with default limits/features.
        const gpu_device = response.adapter.?.createDevice(&.{
            .next_in_chain = .{
                .dawn_toggles_descriptor = &gpu.dawn.TogglesDescriptor.init(.{
                    .enabled_toggles = &[_][*:0]const u8{
                        "allow_unsafe_apis",
                    },
                }),
            },

            .required_features_count = if (options.required_features) |v| @as(u32, @intCast(v.len)) else 0,
            .required_features = if (options.required_features) |v| @as(?[*]const gpu.FeatureName, v.ptr) else null,
            .required_limits = if (options.required_limits) |limits| @as(?*const gpu.RequiredLimits, &gpu.RequiredLimits{
                .limits = limits,
            }) else null,
            .device_lost_callback = &deviceLostCallback,
            .device_lost_userdata = null,
        }) orelse {
            log.err("failed to create GPU device", .{});
            std.process.exit(1);
        };
        gpu_device.setUncapturedErrorCallback({}, printUnhandledErrorCallback);

        const framebuffer_size = window.getFramebufferSize();
        const swap_chain_desc = gpu.SwapChain.Descriptor{
            .label = "main swap chain",
            .usage = .{ .render_attachment = true },
            .format = .bgra8_unorm,
            .width = framebuffer_size.width,
            .height = framebuffer_size.height,
            .present_mode = .mailbox,
        };
        const swap_chain = gpu_device.createSwapChain(surface, &swap_chain_desc);

        return .{
            .allocator = allocator,
            .window = window,
            .device = gpu_device,
            .swap_chain = swap_chain,
            .surface = surface,
            .queue = gpu_device.getQueue(),
        };
    }

    pub fn deinit(self: Self) void {
        self.device.setDeviceLostCallback(null, null);
        self.device.release();

        self.swap_chain.release();
        self.surface.release();
        // TODO: release window here?
    }

    pub fn pollEvents(self: Self) void {
        _ = self;
        glfw.pollEvents();
    }
};

// TODO(important): expose device loss to users, this can happen especially in the web and on mobile
//      devices. Users will need to re-upload all assets to the GPU in this event.
fn deviceLostCallback(reason: gpu.Device.LostReason, msg: [*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
    _ = userdata;
    _ = reason;
    log.err("device lost: {s}", .{msg});
    @panic("GPU device lost");
}

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

test "backend" {
    const a = std.testing.allocator;
    const b = try WgpuBackend.init(a);
    _ = b;
}

pub const DisplayMode = enum {
    /// Windowed mode.
    windowed,

    /// Fullscreen mode, using this option may change the display's video mode.
    fullscreen,

    /// Borderless fullscreen window.
    ///
    /// Beware that true .fullscreen is also a hint to the OS that is used in various contexts, e.g.
    ///
    /// * macOS: Moving to a virtual space dedicated to fullscreen windows as the user expects
    /// * macOS: .borderless windows cannot prevent the system menu bar from being displayed
    ///
    /// Always allow users to choose their preferred display mode.
    borderless,
};

pub const Options = struct {
    is_app: bool = false,
    headless: bool = false,
    display_mode: DisplayMode = .windowed,
    border: bool = true,
    title: [:0]const u8 = "Zigurat",
    size: d.Size = .{ .width = 1920 / 2, .height = 1080 / 2 },
    power_preference: gpu.PowerPreference = .undefined,
    required_features: ?[]const gpu.FeatureName = null,
    required_limits: ?gpu.Limits = null,
};

/// GLFW error handling callback
///
/// This only logs errors, and doesn't e.g. exit the application, because many simple operations of
/// GLFW can result in an error on the stack when running under different Wayland Linux systems.
/// Doing anything else here would result in a good chance of applications not working on Wayland,
/// so the best thing to do really is to just log the error. See the mach-glfw README for more info.
pub fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    if (std.mem.eql(u8, description, "Raw mouse motion is not supported on this system")) return;
    log.err("glfw: {}: {s}\n", .{ error_code, description });
}

// obj-c
// Extracted from `zig translate-c tmp.c` with `#include <objc/message.h>` in the file.
const SEL = opaque {};
const Class = opaque {};

extern fn sel_getUid(str: [*c]const u8) ?*SEL;
extern fn objc_getClass(name: [*c]const u8) ?*Class;
extern fn objc_msgSend() void;

// utils
inline fn printUnhandledErrorCallback(_: void, typ: gpu.ErrorType, message: [*:0]const u8) void {
    switch (typ) {
        .validation => std.log.err("gpu: validation error: {s}\n", .{message}),
        .out_of_memory => std.log.err("gpu: out of memory: {s}\n", .{message}),
        .device_lost => std.log.err("gpu: device lost: {s}\n", .{message}),
        .unknown => std.log.err("gpu: unknown error: {s}\n", .{message}),
        else => unreachable,
    }
    std.os.exit(1);
}

fn getEnvVarOwned(allocator: std.mem.Allocator, key: []const u8) error{ OutOfMemory, InvalidUtf8 }!?[]u8 {
    return std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => @as(?[]u8, null),
        else => |e| e,
    };
}

fn detectBackendType() !gpu.BackendType {
    const target = @import("builtin").target;
    if (target.isDarwin()) return .metal;
    if (target.os.tag == .windows) return .d3d12;
    return .vulkan;
}

const RequestAdapterResponse = struct {
    status: gpu.RequestAdapterStatus,
    adapter: ?*gpu.Adapter,
    message: ?[*:0]const u8,
};

inline fn requestAdapterCallback(
    context: *RequestAdapterResponse,
    status: gpu.RequestAdapterStatus,
    adapter: ?*gpu.Adapter,
    message: ?[*:0]const u8,
) void {
    context.* = RequestAdapterResponse{
        .status = status,
        .adapter = adapter,
        .message = message,
    };
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
