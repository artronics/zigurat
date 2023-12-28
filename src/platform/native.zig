const std = @import("std");
const Allocator = std.mem.Allocator;
const gpu = @import("gpu");
const glfw = @import("glfw");
const zigimg = @import("zigimg");
const objc = @import("objc_message.zig");
const util = @import("util.zig");
const backend = @import("backend.zig");
const testing = std.testing;

const log = std.log.scoped(.zigurat);

pub const WgpuBackend = struct {
    const Self = @This();

    allocator: Allocator,
    window: glfw.Window,
    device: *gpu.Device,
    swap_chain: *gpu.SwapChain,
    surface: *gpu.Surface,
    queue: *gpu.Queue,

    pub fn init(allocator: Allocator, options: backend.Options) !Self {
        try gpu.Impl.init(allocator, .{});

        glfw.setErrorCallback(backend.errorCallback);
        if (!glfw.init(.{})) {
            glfw.getErrorCode() catch |err| switch (err) {
                error.PlatformError,
                error.PlatformUnavailable,
                => return err,
                else => unreachable,
            };
        }

        // Create the test window and discover adapters using it (esp. for OpenGL)
        const backend_type = try util.detectBackendType();
        var hints = util.glfwWindowHintsForBackend(backend_type);
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

        const surface = try util.createSurfaceForWindow(instance, window, comptime util.detectGLFWOptions());

        // Adapter
        var response: util.RequestAdapterResponse = undefined;
        instance.requestAdapter(&gpu.RequestAdapterOptions{
            .compatible_surface = surface,
            .power_preference = options.power_preference,
            .force_fallback_adapter = .false,
        }, &response, util.requestAdapterCallback);
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
        gpu_device.setUncapturedErrorCallback({}, util.printUnhandledErrorCallback);

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
    const a = testing.allocator;
    const b = try WgpuBackend.init(a);
    _ = b;
}
