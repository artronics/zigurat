const std = @import("std");
const Allocator = std.mem.Allocator;
const platform = @import("platform");
const Backend = platform.Backend;
const gpu = platform.gpu;
const data = @import("data.zig");
const Vertex = data.Vertex;
const Uniforms = data.Uniforms;
const RenderData = data.RenderData;

const testing = std.testing;

pub const Renderer = struct {
    const Self = @This();

    allocator: Allocator,
    backend: *Backend,
    common_bind_group: *gpu.BindGroup,
    data: RenderData,
    pipeline: *gpu.RenderPipeline,

    pub fn init(allocator: Allocator, win_options: platform.WindowOptions) !Self {
        const backend = try allocator.create(Backend);
        backend.* = try Backend.init(allocator, win_options);

        const shader = @embedFile("shader.wgsl");
        const vs_mod = backend.device.createShaderModuleWGSL("Vertex Shader", shader);
        defer vs_mod.release();
        const fs_mod = backend.device.createShaderModuleWGSL("Fragment Shader", shader);
        defer fs_mod.release();

        const pipeline = createPipeline(backend.device, vs_mod, fs_mod);
        const render_data = RenderData.init(backend.device);

        const common_bg_layout0 = pipeline.getBindGroupLayout(0);
        const common_bg = backend.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
            .layout = common_bg_layout0,
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, render_data.uniforms_buffer, 0, @sizeOf(Uniforms)),
                gpu.BindGroup.Entry.sampler(1, render_data.sampler),
            },
        }));
        // TODO: Create texture view for fonts

        return .{
            .allocator = allocator,
            .backend = backend,
            .common_bind_group = common_bg,
            .data = render_data,
            .pipeline = pipeline,
        };
    }

    pub fn deinit(self: Self) void {
        self.backend.deinit();
        // why test doesn't catch the memory leak? Commenting the line below wouldn't catch the leak!
        self.allocator.destroy(self.backend);
        self.common_bind_group.release();
        self.pipeline.release();
        self.data.deinit();
    }
};

fn createPipeline(device: *gpu.Device, vs_mod: *gpu.ShaderModule, fs_mod: *gpu.ShaderModule) *gpu.RenderPipeline {
    const swap_chain_format = .bgra8_unorm;
    const primitive = gpu.PrimitiveState{
        .topology = .triangle_list,
        .strip_index_format = .undefined,
        .front_face = .cw,
        .cull_mode = .none,
    };
    const multisample = gpu.MultisampleState{
        .count = 1,
        .mask = 0xFFFFFFFF,
        .alpha_to_coverage_enabled = gpu.Bool32.false,
    };
    const vertex = gpu.VertexState.init(.{
        .module = vs_mod,
        .entry_point = "vs_main",
        .buffers = &.{Vertex.desc()},
    });
    const fragment = &gpu.FragmentState.init(.{
        .module = fs_mod,
        .entry_point = "fs_main",
        .targets = &.{
            .{
                .format = swap_chain_format,
                .blend = &.{
                    .color = .{ .operation = .add, .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
                    .alpha = .{ .operation = .add, .src_factor = .one, .dst_factor = .one_minus_src_alpha },
                },
                .write_mask = gpu.ColorWriteMaskFlags.all,
            },
        },
    });

    const depth_stencil = null;

    const bg_layout_0 = device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "Common BindGroup0 Layout",
        .entries = &.{
            // FIXME: Is the sizeOf Uniform correct for min_binding_size?
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, @sizeOf(Uniforms)),
            gpu.BindGroupLayout.Entry.sampler(1, .{ .fragment = true }, .filtering),
        },
    }));
    defer bg_layout_0.release();
    const bg_layout_1 = device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "Image BindGroup1 Layout",
        .entries = &.{
            gpu.BindGroupLayout.Entry.texture(0, .{ .fragment = true }, .float, .dimension_2d, false),
        },
    }));
    defer bg_layout_1.release();

    const pipeline_layout = device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(
        .{
            .label = "Binding Layouts",
            .bind_group_layouts = &.{ bg_layout_0, bg_layout_1 },
        },
    ));

    const desc = gpu.RenderPipeline.Descriptor{
        .fragment = fragment,
        .layout = pipeline_layout,
        .depth_stencil = depth_stencil,
        .vertex = vertex,
        .multisample = multisample,
        .primitive = primitive,
    };

    return device.createRenderPipeline(&desc);
}

test {
    const a = testing.allocator;
    const r = try Renderer.init(a, .{});
    defer r.deinit();
}
