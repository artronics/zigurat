const std = @import("std");
const Allocator = std.mem.Allocator;
const platform = @import("platform");
const Backend = platform.Backend;
const gpu = platform.gpu;
const data = @import("data.zig");
const Vertex = data.Vertex;

const testing = std.testing;

pub const Renderer = struct {
    const Self = @This();

    allocator: Allocator,
    backend: *Backend,
    pipeline: *gpu.RenderPipeline,

    pub fn init(allocator: Allocator, win_options: platform.WindowOptions) !Self {
        const backend = try allocator.create(Backend);
        backend.* = try Backend.init(allocator, win_options);

        return .{
            .allocator = allocator,
            .backend = backend,
            .pipeline = createPipeline(backend.device),
        };
    }

    pub fn deinit(self: Self) void {
        self.backend.deinit();
        // free up backend pointer: why test doesn't catch the memory leak?
    }
};

fn createPipeline(device: *gpu.Device) *gpu.RenderPipeline {
    const vs = @embedFile("shader.wgsl");
    const vs_module = device.createShaderModuleWGSL("my vertex shader", vs);
    const desc = gpu.RenderPipeline.Descriptor{
        // .fragment = &fragment,
        // .layout = pipeline_layout,
        .depth_stencil = null,
        .vertex = gpu.VertexState.init(.{
            .module = vs_module,
            .entry_point = "vs_main",
            .buffers = &.{Vertex.desc()},
        }),
        // .multisample = .{
        //     .count = 1,
        //     .mask = 0xFFFFFFFF,
        //     .alpha_to_coverage_enabled = gpu.Bool32.false,
        // },
        // .primitive = primitive,
    };
    vs_module.release();

    return device.createRenderPipeline(&desc);
}

test {
    const a = testing.allocator;
    const r = try Renderer.init(a, .{});
    defer r.deinit();
}
