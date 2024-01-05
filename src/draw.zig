const std = @import("std");
const Allocator = std.mem.Allocator;
const platform = @import("platform.zig");
const gpu = @import("gpu");
const cm = @import("common.zig");
const Backend = platform.WgpuBackend;

pub const Vertex = extern struct {
    position: @Vector(2, f32),
    uv: @Vector(2, f32),
    color: @Vector(4, f32),

    const attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "position"), .shader_location = 0 },
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 1 },
        .{ .format = .float32x4, .offset = @offsetOf(Vertex, "color"), .shader_location = 2 },
    };

    pub fn desc() gpu.VertexBufferLayout {
        return gpu.VertexBufferLayout.init(.{
            .array_stride = @sizeOf(Vertex),
            .step_mode = .vertex,
            .attributes = &attributes,
        });
    }
};

pub const Uniforms = extern struct {
    mvp: [4]@Vector(4, f32),
    gama: f32,
};

const Queue = u32;

pub const primitives = struct {
    pub const Rect = struct {
        a: cm.Point,
        b: cm.Point,
        fn addToQueue(r: Rect, queue: Queue) void {
            _ = queue;
            _ = r;
        }
    };
};

pub const Primitive = union(enum) {
    const p = primitives;
    rect: p.Rect,
    pub inline fn addToQueue(pm: Primitive, queue: u32) void {
        switch (pm) {
            inline else => |case| case.addToQueue(queue),
        }
    }
};

pub const DrawCommand = union(enum) {
    primitive: Primitive,
    bg_color: cm.Color,
};

pub const CommandQueue = std.ArrayList(DrawCommand);

pub const Renderer = struct {
    const Self = @This();

    allocator: Allocator,
    backend: *Backend,
    common_bind_group: *gpu.BindGroup,
    frame: Frame,
    pipeline: *gpu.RenderPipeline,

    pub fn init(allocator: Allocator, win_options: platform.Options) !Self {
        const backend = try allocator.create(Backend);
        backend.* = try Backend.init(allocator, win_options);

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
        // TODO: Create texture view for fonts

        return .{
            .allocator = allocator,
            .backend = backend,
            .common_bind_group = common_bg,
            .frame = frame,
            .pipeline = pipeline,
        };
    }

    // TODO: remove this
    pub fn run(self: Self) void {
        while (!self.backend.window.shouldClose()) {
            self.render();
            std.time.sleep(16 * std.time.ns_per_ms);
        }
    }
    pub fn render(self: Self) void {
        self.backend.pollEvents();
        self.backend.device.tick();

        const back_buffer_view = self.backend.swap_chain.getCurrentTextureView().?;
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
        self.backend.swap_chain.present();
    }

    pub fn deinit(self: Self) void {
        self.backend.deinit();
        // why test doesn't catch the memory leak? Commenting the line below wouldn't catch the leak!
        self.allocator.destroy(self.backend);
        self.common_bind_group.release();
        self.pipeline.release();
        self.frame.deinit();
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
            // FIXME: Is the sizeOf Uniform correct for min_binding_size?
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, @sizeOf(Uniforms)),
            gpu.BindGroupLayout.Entry.sampler(1, .{ .fragment = true }, .filtering),
        },
    }));
    defer common_bg0_layout.release();
    // const image_bg1_layout = device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
    //     .label = "Image BindGroup1 Layout",
    //     .entries = &.{
    //         gpu.BindGroupLayout.Entry.texture(0, .{ .fragment = true }, .float, .dimension_2d, false),
    //     },
    // }));
    // defer image_bg1_layout.release();

    const pipeline_layout = device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(
        .{
            .label = "Binding Layouts",
            // .bind_group_layouts = &.{ common_bg_layout0, image_bg1_layout },
            .bind_group_layouts = &.{common_bg0_layout},
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
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
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

    const red = [_]f32{ 1.0, 0.0, 0.0, 1.0 };
    const uv = [_]f32{ 0.0, 0.0 };
    const vertices = [_]Vertex{
        .{ .position = .{ -0.5, 0.5 }, .uv = uv, .color = red },
        .{ .position = .{ 0.5, 0.5 }, .uv = uv, .color = red },
        .{ .position = .{ 0.5, -0.5 }, .uv = uv, .color = red },
        .{ .position = .{ -0.5, -0.5 }, .uv = uv, .color = red },
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
