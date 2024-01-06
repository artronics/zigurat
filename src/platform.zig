const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.zigurat);
const glfw = @import("glfw");
const gpu = @import("gpu");
const d = @import("data.zig");

pub const Options = struct {
    power_preference: gpu.PowerPreference = .undefined,
    required_features: ?[]const gpu.FeatureName = null,
    required_limits: ?gpu.Limits = null,
};

pub const WgpuBackend = struct {
    const Self = @This();

    allocator: Allocator,
    instance: *gpu.Instance,
    device: *gpu.Device,
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

        const instance = gpu.createInstance(null) orelse {
            std.debug.print("failed to create GPU instance", .{});
            std.process.exit(1);
        };

        // Adapter
        var response: RequestAdapterResponse = undefined;
        instance.requestAdapter(&gpu.RequestAdapterOptions{
            .compatible_surface = null,
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

        return .{
            .allocator = allocator,
            .instance = instance,
            .device = gpu_device,
            .queue = gpu_device.getQueue(),
        };
    }

    pub fn deinit(self: Self) void {
        self.device.setDeviceLostCallback(null, null);

        self.queue.release();
        self.device.release();
        self.instance.release();
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
