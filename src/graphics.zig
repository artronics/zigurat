const std = @import("std");
const Allocator = std.mem.Allocator;
const gpu = @import("gpu");
const glfw = @import("glfw");
const testing = std.testing;
const expect = testing.expect;

// pub var adapter: *gpu.Adapter = undefined;
// pub var device: *gpu.Device = undefined;
// pub var queue: *gpu.Queue = undefined;
// pub var swap_chain: *gpu.SwapChain = undefined;
// pub var descriptor: gpu.SwapChain.Descriptor = undefined;

const Backend = struct {
    allocator: Allocator,
    adaptor: *gpu.Adapter,
    suface: *gpu.Surface,

    const Self = @This();

    pub const GPUInterface = gpu.dawn.Interface;
    fn init(allocator: Allocator) !Self {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const al = gpa.allocator();
        try gpu.Impl.init(al, .{});
        const instance = gpu.createInstance(null);
        if (instance == null) {
            std.debug.print("failed to create GPU instance\n", .{});
            std.process.exit(1);
        }
        const backend_type = try detectBackendType(allocator);

        glfw.setErrorCallback(errorCallback);
        if (!glfw.init(.{})) {
            std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
            std.process.exit(1);
        }

        // Create the test window and discover adapters using it (esp. for OpenGL)
        var hints = glfwWindowHintsForBackend(backend_type);
        hints.cocoa_retina_framebuffer = true;
        const window = glfw.Window.create(640, 480, "mach/gpu window", null, null, hints) orelse {
            std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
            std.process.exit(1);
        };

        if (backend_type == .opengl) glfw.makeContextCurrent(window);
        if (backend_type == .opengles) glfw.makeContextCurrent(window);
        const surface = try createSurfaceForWindow(instance.?, window, comptime detectGLFWOptions());

        var response: RequestAdapterResponse = undefined;
        instance.?.requestAdapter(&gpu.RequestAdapterOptions{
            .compatible_surface = surface,
            .power_preference = .undefined,
            .force_fallback_adapter = .false,
        }, &response, requestAdapterCallback);
        if (response.status != .success) {
            std.debug.print("failed to create GPU adapter: {s}\n", .{response.message.?});
            std.process.exit(1);
        }

        return Self{
            .allocator = allocator,
            .surface = surface,
        };
    }
    fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
        std.log.err("glfw: {}: {s}\n", .{ error_code, description });
    }
};

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
pub fn detectBackendType() !gpu.BackendType {
    const target = @import("builtin").target;
    if (target.isDarwin()) return .metal;
    if (target.os.tag == .windows) return .d3d12;
    return .vulkan;
}
pub fn createSurfaceForWindow(
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
        const layer = msgSend(objc.objc_getClass("CAMetalLayer"), "layer", .{}, ?*anyopaque); // [CAMetalLayer layer]
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

const objc = struct {
    pub const SEL = opaque {};
    pub const Class = opaque {};
};

pub extern fn sel_getUid(str: [*c]const u8) ?*objc.SEL;
pub extern fn objc_getClass(name: [*c]const u8) ?*objc.Class;
pub extern fn objc_msgSend() void;

pub const AutoReleasePool = if (!@import("builtin").target.isDarwin()) opaque {
    pub fn init() error{OutOfMemory}!?*AutoReleasePool {
        return null;
    }

    pub fn release(pool: ?*AutoReleasePool) void {
        _ = pool;
        return;
    }
} else opaque {
    pub fn init() error{OutOfMemory}!?*AutoReleasePool {
        // pool = [NSAutoreleasePool alloc];
        var pool = msgSend(objc.objc_getClass("NSAutoreleasePool"), "alloc", .{}, ?*AutoReleasePool);
        if (pool == null) return error.OutOfMemory;

        // pool = [pool init];
        pool = msgSend(pool, "init", .{}, ?*AutoReleasePool);
        if (pool == null) unreachable;

        return pool;
    }

    pub fn release(pool: ?*AutoReleasePool) void {
        // [pool release];
        msgSend(pool, "release", .{}, void);
    }
};
// Borrowed from https://github.com/hazeycode/zig-objcrt
pub fn msgSend(obj: anytype, sel_name: [:0]const u8, args: anytype, comptime ReturnType: type) ReturnType {
    const args_meta = @typeInfo(@TypeOf(args)).Struct.fields;

    const FnType = switch (args_meta.len) {
        0 => *const fn (@TypeOf(obj), ?*objc.SEL) callconv(.C) ReturnType,
        1 => *const fn (@TypeOf(obj), ?*objc.SEL, args_meta[0].type) callconv(.C) ReturnType,
        2 => *const fn (@TypeOf(obj), ?*objc.SEL, args_meta[0].type, args_meta[1].type) callconv(.C) ReturnType,
        3 => *const fn (@TypeOf(obj), ?*objc.SEL, args_meta[0].type, args_meta[1].type, args_meta[2].type) callconv(.C) ReturnType,
        4 => *const fn (@TypeOf(obj), ?*objc.SEL, args_meta[0].type, args_meta[1].type, args_meta[2].type, args_meta[3].type) callconv(.C) ReturnType,
        else => @compileError("Unsupported number of args"),
    };

    // NOTE: func is a var because making it const causes a compile error which I believe is a compiler bug
    const func = @as(FnType, @ptrCast(&objc.objc_msgSend));
    const sel = objc.sel_getUid(@as([*c]const u8, @ptrCast(sel_name)));

    return @call(.auto, func, .{ obj, sel } ++ args);
}
pub fn glfwWindowHintsForBackend(backend: gpu.BackendType) glfw.Window.Hints {
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
pub fn detectGLFWOptions() glfw.BackendOptions {
    const target = @import("builtin").target;
    if (target.isDarwin()) return .{ .cocoa = true };
    return switch (target.os.tag) {
        .windows => .{ .win32 = true },
        .linux => .{ .x11 = true, .wayland = true },
        else => .{},
    };
}

test "graphics" {
    const a = testing.allocator;
    const gfx = try Backend.init(a);
    _ = gfx;
}
