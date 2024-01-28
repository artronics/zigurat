const std = @import("std");
const Allocator = std.mem.Allocator;
const platform = @import("platform.zig");
const gpu = @import("gpu");
const win = @import("window.zig");
const Window = win.Window;
const data = @import("data.zig");
const Vertex = data.Vertex;
const Index = data.Index;
const Uniforms = data.Uniforms;
const Point = data.Point;
const Color = data.Color;
const Size = data.Size;
const Backend = platform.WgpuBackend;
const Draw = @import("draw.zig");
const Texture = @import("texture.zig");

const Self = @This();

allocator: Allocator,
backend: *const Backend,
window: *const Window,
common_bind_group: *gpu.BindGroup,
image_bind_group: *gpu.BindGroup,
pipeline: *gpu.RenderPipeline,

vertex_buffer: *gpu.Buffer,
index_buffer: *gpu.Buffer,
uniforms_buffer: *gpu.Buffer,
sampler: *gpu.Sampler,
texture: *Texture,

// Client owns the backend and texture. Renderer takes ownership of window
pub fn init(allocator: Allocator, backend: *const Backend, window: *const Window, texture: *Texture) !Self {
    const device = backend.device;
    const shader = @embedFile("shader.wgsl");
    const vs_mod = device.createShaderModuleWGSL("Vertex Shader", shader);
    defer vs_mod.release();
    const fs_mod = device.createShaderModuleWGSL("Fragment Shader", shader);
    defer fs_mod.release();

    const pipeline = createPipeline(device, vs_mod, fs_mod);

    const uniforms_buf = device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(Uniforms),
        .mapped_at_creation = .false,
    });
    const vertex_buf = device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = @sizeOf(Vertex) * 4,
        .mapped_at_creation = .false,
    });
    const index_buf = device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = roundToMultipleOf4(u64, @sizeOf(u16) * 6),
        .mapped_at_creation = .false,
    });
    const sampler = device.createSampler(&.{
        .min_filter = .linear,
        .mag_filter = .linear,
        .mipmap_filter = .linear,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
        .max_anisotropy = 1,
    });

    const common_bg_layout0 = pipeline.getBindGroupLayout(0);
    const common_bg = device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = common_bg_layout0,
        .entries = &.{
            gpu.BindGroup.Entry.buffer(0, uniforms_buf, 0, @sizeOf(Uniforms)),
            gpu.BindGroup.Entry.sampler(1, sampler),
        },
    }));

    const tex_data = try texture.buildTexture();
    // const texels: [4]u8 = .{0xff,0xff,0xff,0xff,};
    // const tex_data = .{ .width = 1, .height = 1, .texels = &texels };
    const img_size = gpu.Extent3D{ .width = tex_data.width, .height = tex_data.height };

    const tex = device.createTexture(&.{
        .label = "Font Atlas",
        .size = img_size,
        .format = .rgba8_unorm,
        .usage = .{
            .texture_binding = true,
            .copy_dst = true,
        },
        .mip_level_count = 1,
        .sample_count = 1,
    });
    const data_layout = gpu.Texture.DataLayout{
        .bytes_per_row = tex_data.width * 4,
        .rows_per_image = tex_data.height,
    };
    backend.queue.writeTexture(&.{ .texture = tex }, &data_layout, &img_size, tex_data.texels);

    const image_bg_layout1 = pipeline.getBindGroupLayout(1);

    const tex_view = tex.createView(&.{
        .label = "Atlas View",
        .format = .rgba8_unorm,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
    });
    const image_bg = device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = image_bg_layout1,
        .entries = &.{
            gpu.BindGroup.Entry.textureView(0, tex_view),
        },
    }));

    return .{
        .allocator = allocator,
        .backend = backend,
        .window = window,
        .common_bind_group = common_bg,
        .image_bind_group = image_bg,
        .pipeline = pipeline,

        .uniforms_buffer = uniforms_buf,
        .vertex_buffer = vertex_buf,
        .index_buffer = index_buf,
        .sampler = sampler,
        .texture = texture,
    };
}
pub fn deinit(self: Self) void {
    self.window.deinit();
    self.common_bind_group.release();
    self.pipeline.release();
    self.vertex_buffer.release();
    self.index_buffer.release();
    self.uniforms_buffer.release();
    self.sampler.release();
}

// pub fn render(self: *Self, cmd_list: []Draw.DrawCommand) void {
pub fn render(self: *Self, draw: *const Draw) void {
    self.window.pollEvents();
    self.backend.device.tick();

    const back_buffer_view = self.window.swap_chain.getCurrentTextureView().?;
    defer back_buffer_view.release();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .resolve_target = null,
        .clear_value = gpu.Color{ .r = 0.1, .g = 0.2, .b = 0.3, .a = 1.0 },
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = self.backend.device.createCommandEncoder(null);
    defer encoder.release();
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });

    const pass = encoder.beginRenderPass(&render_pass_info);
    defer pass.release();

    pass.setPipeline(self.pipeline);

    pass.setBindGroup(0, self.common_bind_group, &.{});
    pass.setBindGroup(1, self.image_bind_group, &.{});
    pass.setVertexBuffer(0, self.vertex_buffer, 0, @sizeOf(Vertex) * draw.vertexBufferSize());
    pass.setIndexBuffer(self.index_buffer, .uint16, 0, @sizeOf(Index) * draw.indexBufferSize());

    pass.drawIndexed(
        @intCast(draw.indexBufferSize()),
        1, // instance_count
        0, // first_index
        0, // base_vertex
        0, // first_instance
    );

    pass.end();

    var command = encoder.finish(null);
    defer command.release();

    // buffers
    const w: f32 = @floatFromInt(self.window.size.width);
    const h: f32 = @floatFromInt(self.window.size.height);
    // column-major projection
    const mvp = [4][4]f32{
        [_]f32{ 2.0 / w, 0.0, 0.0, 0.0 },
        [_]f32{ 0.0, -2.0 / h, 0.0, 0.0 },
        [_]f32{ 0.0, 0.0, 1.0, 0.0 },
        [_]f32{ -1.0, 1.0, 0.0, 1.0 },
    };

    const gamma = 1.0;
    const uniforms = [_]Uniforms{.{ .mvp = mvp, .gamma = gamma }};

    self.backend.queue.writeBuffer(self.uniforms_buffer, 0, &uniforms);
    self.backend.queue.writeBuffer(self.vertex_buffer, 0, draw.vertices());
    self.backend.queue.writeBuffer(self.index_buffer, 0, draw.indices());

    self.backend.queue.submit(&[_]*gpu.CommandBuffer{command});

    self.window.swap_chain.present();
}

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

    const common_bg0_layout = device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "Common BindGroup0 Layout",
        .entries = &.{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, @sizeOf(Uniforms)),
            gpu.BindGroupLayout.Entry.sampler(1, .{ .fragment = true }, .filtering),
        },
    }));
    defer common_bg0_layout.release();
    const image_bg1_layout = device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "Image BindGroup1 Layout",
        .entries = &.{
            gpu.BindGroupLayout.Entry.texture(0, .{ .fragment = true }, .float, .dimension_2d, false),
        },
    }));
    defer image_bg1_layout.release();

    const pipeline_layout = device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(
        .{
            .label = "Binding Layouts",
            .bind_group_layouts = &.{ common_bg0_layout, image_bg1_layout },
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

inline fn roundToMultipleOf4(comptime T: type, value: T) T {
    return (value + 3) & ~@as(T, 3);
}
