const std = @import("std");
const native = @import("native.zig");
const backend = @import("backend.zig");
const plt = @import("platform.zig");

// Exports

pub const DawnInterface = gpu.dawn.Interface;
pub const WindowOptions = backend.Options;
pub const Backend = MockPlatform.MockBackend;

pub const gpu = struct {
    const _gpu = @import("gpu"); // Actual gpu; use it for data struct
    pub const RenderPipeline = struct {};

    pub const Device = struct {
        const aloc = std.testing.allocator;
        shader_mod: *_gpu.ShaderModule = undefined,
        pub fn createRenderPipeline(device: *Device, descriptor: *const _gpu.RenderPipeline.Descriptor) *RenderPipeline {
            _ = descriptor;
            _ = device;
            return .{};
        }
        pub fn createShaderModuleWGSL(device: *Device, label: ?[*:0]const u8, wgsl_code: [*:0]const u8) *_gpu.ShaderModule {
            _ = wgsl_code;
            _ = label;
            device.shader_mod = aloc.create(_gpu.ShaderModule) catch unreachable;
            return device.shader_mod;
        }
    };
};

pub const MockPlatform = struct {
    const Allocator = std.mem.Allocator;

    pub const MockBackend = struct {
        aloc: Allocator,
        device: *gpu.Device,

        pub fn init(aloc: Allocator, opt: plt.WindowOptions) !MockBackend {
            const device = try aloc.create(gpu.Device);
            device.* = .{};
            _ = opt;

            return .{ .device = device, .aloc = aloc };
        }
        pub fn deinit(mb: MockBackend) void {
            mb.aloc.destroy(mb.device);
        }
    };
};
