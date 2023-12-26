const std = @import("std");
const Allocator = std.mem.Allocator;
const gpu = @import("gpu");
const glfw = @import("glfw");
const testing = std.testing;
const expect = testing.expect;
const objc = @import("objc_message.zig");

pub const Platform = struct {
    allocator: Allocator,
    instance: *gpu.Instance,
    adapter: *gpu.Adapter,
    device: *gpu.Device,
    queue: *gpu.Queue,
    swap_chain: *gpu.SwapChain,
    swap_chain_desc: gpu.SwapChain.Descriptor,
    surface: *gpu.Surface,
    pipeline: *gpu.RenderPipeline,
    window: glfw.Window,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        try gpu.Impl.init(allocator, .{});
        const instance = gpu.createInstance(null);
        if (instance == null) {
            std.debug.print("failed to create GPU instance\n", .{});
            std.process.exit(1);
        }
        const backend_type = try detectBackendType();

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
        // Print which adapter we are using.
        var props = std.mem.zeroes(gpu.Adapter.Properties);
        response.adapter.?.getProperties(&props);
        std.debug.print("found {s} backend on {s} adapter: {s}, {s}\n", .{
            props.backend_type.name(),
            props.adapter_type.name(),
            props.name,
            props.driver_description,
        });

        // Create a device with default limits/features.
        const device = response.adapter.?.createDevice(null);
        if (device == null) {
            std.debug.print("failed to create GPU device\n", .{});
            std.process.exit(1);
        }

        device.?.setUncapturedErrorCallback({}, printUnhandledErrorCallback);

        const swap_chain_format = .bgra8_unorm;
        const framebuffer_size = window.getFramebufferSize();
        const swap_chain_desc = gpu.SwapChain.Descriptor{
            .label = "main swap chain",
            .usage = .{ .render_attachment = true },
            .format = swap_chain_format,
            .width = framebuffer_size.width,
            .height = framebuffer_size.height,
            .present_mode = .mailbox,
        };
        const swap_chain = device.?.createSwapChain(surface, &swap_chain_desc);

        // pipeline
        const vs = @embedFile("../../shader.vert.wgsl");
        const vs_module = device.?.createShaderModuleWGSL("my vertex shader", vs);

        const fs = @embedFile("../../shader.frag.wgsl");
        const fs_module = device.?.createShaderModuleWGSL("my fragment shader", fs);

        // Fragment state
        const blend = gpu.BlendState{
            .color = .{
                .dst_factor = .one,
            },
            .alpha = .{
                .dst_factor = .one,
            },
        };
        const color_target = gpu.ColorTargetState{
            .format = swap_chain_format,
            .blend = &blend,
            .write_mask = gpu.ColorWriteMaskFlags.all,
        };
        const fragment = gpu.FragmentState.init(.{
            .module = fs_module,
            .entry_point = "main",
            .targets = &.{color_target},
        });
        const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
            .fragment = &fragment,
            .layout = null,
            .depth_stencil = null,
            .vertex = gpu.VertexState{
                .module = vs_module,
                .entry_point = "main",
            },
            .multisample = .{},
            .primitive = .{},
        };
        const pipeline = device.?.createRenderPipeline(&pipeline_descriptor);

        vs_module.release();
        fs_module.release();

        return Self{
            .allocator = allocator,
            .adapter = response.adapter.?,
            .device = device.?,
            .surface = surface,
            .instance = instance.?,
            .window = window,
            .queue = device.?.getQueue(),
            .swap_chain = swap_chain,
            .swap_chain_desc = swap_chain_desc,
            .pipeline = pipeline,
        };
    }
    fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
        std.log.err("glfw: {}: {s}\n", .{ error_code, description });
    }
    pub fn run(self: Self) !void {
        while (!self.window.shouldClose()) {
            try self.frame();
            std.time.sleep(16 * std.time.ns_per_ms);
        }
    }
    pub fn frame(self: Self) !void {
        glfw.pollEvents();
        self.device.tick();

        const back_buffer_view = self.swap_chain.getCurrentTextureView().?;
        const color_attachment = gpu.RenderPassColorAttachment{
            .view = back_buffer_view,
            .resolve_target = null,
            .clear_value = std.mem.zeroes(gpu.Color),
            .load_op = .clear,
            .store_op = .store,
        };

        const encoder = self.device.createCommandEncoder(null);
        const render_pass_info = gpu.RenderPassDescriptor.init(.{
            .color_attachments = &.{color_attachment},
        });
        const pass = encoder.beginRenderPass(&render_pass_info);
        pass.setPipeline(self.pipeline);
        pass.draw(3, 1, 0, 0);
        pass.end();
        pass.release();

        var command = encoder.finish(null);
        encoder.release();

        self.queue.submit(&[_]*gpu.CommandBuffer{command});
        command.release();
        self.swap_chain.present();
        back_buffer_view.release();
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
fn detectBackendType() !gpu.BackendType {
    const target = @import("builtin").target;
    if (target.isDarwin()) return .metal;
    if (target.os.tag == .windows) return .d3d12;
    return .vulkan;
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
        var pool = msgSend(objc.objc_getClass("NSAutoreleasePool"), "alloc", .{}, ?*AutoReleasePool);
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
        0 => *const fn (@TypeOf(obj), ?*objc.SEL) callconv(.C) ReturnType,
        1 => *const fn (@TypeOf(obj), ?*objc.SEL, args_meta[0].type) callconv(.C) ReturnType,
        2 => *const fn (@TypeOf(obj), ?*objc.SEL, args_meta[0].type, args_meta[1].type) callconv(.C) ReturnType,
        3 => *const fn (@TypeOf(obj), ?*objc.SEL, args_meta[0].type, args_meta[1].type, args_meta[2].type) callconv(.C) ReturnType,
        4 => *const fn (@TypeOf(obj), ?*objc.SEL, args_meta[0].type, args_meta[1].type, args_meta[2].type, args_meta[3].type) callconv(.C) ReturnType,
        else => @compileError("Unsupported number of args"),
    };

    const func = @as(FnType, @ptrCast(&objc.objc_msgSend));
    const sel = objc.sel_getUid(@as([*c]const u8, @ptrCast(sel_name)));

    return @call(.auto, func, .{ obj, sel } ++ args);
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

test "graphics" {
    const a = testing.allocator;
    const gfx = try Platform.init(a);
    _ = gfx;
}
