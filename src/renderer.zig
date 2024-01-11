const std = @import("std");
const Allocator = std.mem.Allocator;
const platform = @import("platform.zig");
const gpu = @import("gpu");
const win = @import("window.zig");
const Window = win.Window;
const fontmgr = @import("font.zig");
const data = @import("data.zig");
const Vertex = data.Vertex;
const Uniforms = data.Uniforms;
const Point = data.Point;
const Color = data.Color;
const Backend = platform.WgpuBackend;

pub const Renderer = struct {
    const Self = @This();

    allocator: Allocator,
    backend: *const Backend,
    window: *const Window,
    common_bind_group: *gpu.BindGroup,
    image_bind_group: *gpu.BindGroup,
    frame: Frame,
    pipeline: *gpu.RenderPipeline,

    // Client owns the backend but NOT the window. Window will be destroyed upon deinit
    pub fn init(allocator: Allocator, backend: *const Backend, window: *const Window) Self {
        var font = fontmgr.init(allocator) catch unreachable;
        font.buildAtlas2() catch unreachable;
        const shader = @embedFile("shader.wgsl");
        const vs_mod = backend.device.createShaderModuleWGSL("Vertex Shader", shader);
        defer vs_mod.release();
        const fs_mod = backend.device.createShaderModuleWGSL("Fragment Shader", shader);
        defer fs_mod.release();

        const pipeline = createPipeline(backend.device, vs_mod, fs_mod);
        const frame = Frame.init(backend.device);

        frame.draw();

        const common_bg_layout0 = pipeline.getBindGroupLayout(0);
        const common_bg = backend.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
            .layout = common_bg_layout0,
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, frame.uniforms_buffer, 0, @sizeOf(Uniforms)),
                gpu.BindGroup.Entry.sampler(1, frame.sampler),
            },
        }));

        const atlas_data = font.textureData();
        const img_size = gpu.Extent3D{ .width = atlas_data.width, .height = atlas_data.height };

        const texture = backend.device.createTexture(&.{
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
            .bytes_per_row = atlas_data.width * 4,
            .rows_per_image = atlas_data.height,
        };
        backend.queue.writeTexture(&.{ .texture = texture }, &data_layout, &img_size, atlas_data.pixels);

        const image_bg_layout1 = pipeline.getBindGroupLayout(1);

        const tex_view = texture.createView(&.{
            .label = "Font Atlas View",
            .format = .rgba8_unorm,
            .base_mip_level = 0,
            .mip_level_count = 1,
            .base_array_layer = 0,
            .array_layer_count = 1,
        });
        const image_bg = backend.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
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
            .frame = frame,
            .pipeline = pipeline,
        };
    }
    pub fn deinit(self: Self) void {
        self.window.deinit();
        self.common_bind_group.release();
        self.pipeline.release();
        self.frame.deinit();
    }

    // TODO: remove this
    pub fn run(self: Self) void {
        while (!self.window.window.shouldClose()) {
            self.render();
            std.time.sleep(16 * std.time.ns_per_ms);
        }
    }
    pub fn render(self: Self) void {
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
        self.frame.start(self.window, encoder);

        const pass = encoder.beginRenderPass(&render_pass_info);
        defer pass.release();

        pass.setPipeline(self.pipeline);

        pass.setBindGroup(0, self.common_bind_group, &.{});
        pass.setBindGroup(1, self.image_bind_group, &.{});
        pass.setVertexBuffer(0, self.frame.vertex_buffer, 0, @sizeOf(Vertex) * self.frame.vertex_size);
        pass.setIndexBuffer(self.frame.index_buffer, .uint16, 0, @sizeOf(u16) * self.frame.index_size);

        pass.drawIndexed(
            self.frame.index_size,
            1, // instance_count
            0, // first_index
            0, // base_vertex
            0, // first_instance
        );

        pass.end();

        var command = encoder.finish(null);
        defer command.release();

        self.backend.queue.submit(&[_]*gpu.CommandBuffer{command});
        self.window.swap_chain.present();
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

pub const Frame = struct {
    // TODO: move layout, desc and bg(?) here
    const Self = @This();
    const vertex_size_init = 10000;
    const index_size_init = 10000;

    device: *gpu.Device,

    vertex_buffer: *gpu.Buffer,
    index_buffer: *gpu.Buffer,
    uniforms_buffer: *gpu.Buffer,
    sampler: *gpu.Sampler,

    vertex_size: u32 = vertex_size_init,
    index_size: u32 = index_size_init,

    pub fn init(device: *gpu.Device) Self {
        const uniforms_buf = device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = @sizeOf(Uniforms),
            .mapped_at_creation = .false,
        });
        const vertex_buf = device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = @sizeOf(Vertex) * vertex_size_init,
            .mapped_at_creation = .true,
        });
        const index_buf = device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .index = true },
            .size = roundToMultipleOf4(u64, @sizeOf(u16) * index_size_init),
            .mapped_at_creation = .true,
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

        return .{
            // TODO: make sure when this is complete, device is actually needed
            .device = device,
            .uniforms_buffer = uniforms_buf,
            .vertex_buffer = vertex_buf,
            .index_buffer = index_buf,
            .sampler = sampler,
        };
    }

    pub fn deinit(self: Self) void {
        self.vertex_buffer.release();
        self.index_buffer.release();
        self.uniforms_buffer.release();
        self.sampler.release();
    }

    fn start(self: Self, window: *const Window, encoder: *gpu.CommandEncoder) void {
        const w: f32 = @floatFromInt(window.size.width);
        const h: f32 = @floatFromInt(window.size.height);
        // column-major projection
        const mvp = [4][4]f32{
            [_]f32{ 2.0 / w, 0.0, 0.0, 0.0 },
            [_]f32{ 0.0, -2.0 / h, 0.0, 0.0 },
            [_]f32{ 0.0, 0.0, 1.0, 0.0 },
            [_]f32{ -1.0, 1.0, 0.0, 1.0 },
        };

        const gamma = 1.0;
        const uniforms = [_]Uniforms{.{ .mvp = mvp, .gamma = gamma }};
        encoder.writeBuffer(self.uniforms_buffer, 0, &uniforms);
    }

    const white = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    const uv = [_]f32{ 0.0, 0.0 };
    const vertices = [_]Vertex{
        // .{ .position = .{ 100.0, 100.0 }, .uv = uv, .color = red },
        // .{ .position = .{ 200.0, 100.0 }, .uv = uv, .color = red },
        // .{ .position = .{ 200.0, 200.0 }, .uv = uv, .color = red },
        // .{ .position = .{ 100.0, 200.0 }, .uv = uv, .color = red },
        .{ .position = .{ 100.0, 100.0 }, .uv = .{ 0.0, 0.0 }, .color = white },
        .{ .position = .{ 200.0, 100.0 }, .uv = .{ 1.0, 0.0 }, .color = white },
        .{ .position = .{ 200.0, 200.0 }, .uv = .{ 1.0, 1.0 }, .color = white },
        .{ .position = .{ 100.0, 200.0 }, .uv = .{ 0.0, 1.0 }, .color = white },
    };
    const indices = [_]u16{
        0, 1, 3,
        1, 2, 3,
    };
    pub fn draw(self: Self) void {
        const vertex_mapped = self.vertex_buffer.getMappedRange(Vertex, 0, vertices.len);
        @memcpy(vertex_mapped.?, vertices[0..]);
        self.vertex_buffer.unmap();

        const index_mapped = self.index_buffer.getMappedRange(u16, 0, indices.len);
        @memcpy(index_mapped.?, indices[0..]);
        self.index_buffer.unmap();
    }
};

inline fn roundToMultipleOf4(comptime T: type, value: T) T {
    return (value + 3) & ~@as(T, 3);
}
