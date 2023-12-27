const std = @import("std");
const Allocator = std.mem.Allocator;
const gpu = @import("gpu");
const glfw = @import("glfw");
const zigimg = @import("zigimg");
const testing = std.testing;
const expect = testing.expect;
const objc = @import("objc_message.zig");
const util = @import("util.zig");

pub const Vertex = extern struct {
    position: @Vector(3, f32),
    color: @Vector(3, f32),
    texCoords: @Vector(2, f32),

    const attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x3, .offset = @offsetOf(Vertex, "position"), .shader_location = 0 },
        .{ .format = .float32x3, .offset = @offsetOf(Vertex, "color"), .shader_location = 1 },
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "texCoords"), .shader_location = 2 },
    };

    pub fn desc() gpu.VertexBufferLayout {
        return gpu.VertexBufferLayout.init(.{
            .array_stride = @sizeOf(Vertex),
            .step_mode = .vertex,
            .attributes = &attributes,
        });
    }
};

const vertices = [_]Vertex{
    Vertex{
        .position = [_]f32{ -0.0868241, 0.49240386, 0.0 },
        .color = [_]f32{ 0.5, 0.0, 0.5 },
        .texCoords = [_]f32{ 0.4131759, 1 - 0.99240386 },
    }, // A
    Vertex{
        .position = [_]f32{ -0.49513406, 0.06958647, 0.0 },
        .color = [_]f32{ 0.5, 0.0, 0.5 },
        .texCoords = [_]f32{ 0.0048659444, 1 - 0.56958647 },
    }, // B
    Vertex{
        .position = [_]f32{ -0.21918549, -0.44939706, 0.0 },
        .color = [_]f32{ 0.5, 0.0, 0.5 },
        .texCoords = [_]f32{ 0.28081453, 1 - 0.05060294 },
    }, // C
    Vertex{
        .position = [_]f32{ 0.35966998, -0.3473291, 0.0 },
        .color = [_]f32{ 0.5, 0.0, 0.5 },
        .texCoords = [_]f32{ 0.85967, 1 - 0.1526709 },
    }, // D
    Vertex{
        .position = [_]f32{ 0.44147372, 0.2347359, 0.0 },
        .color = [_]f32{ 0.5, 0.0, 0.5 },
        .texCoords = [_]f32{ 0.9414737, 1 - 0.7347359 },
    }, // E
};
const indices = [_]u16{
    0, 1, 4,
    1, 2, 4,
    2, 3, 4,
};

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
    vertex_buffer: *gpu.Buffer,
    index_buffer: *gpu.Buffer,
    texture: *gpu.Texture,
    texture_data_layout: gpu.Texture.DataLayout,
    bind_group: *gpu.BindGroup,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        try gpu.Impl.init(allocator, .{});
        const instance = gpu.createInstance(null);
        if (instance == null) {
            std.debug.print("failed to create GPU instance\n", .{});
            std.process.exit(1);
        }
        const backend_type = try util.detectBackendType();

        glfw.setErrorCallback(errorCallback);
        if (!glfw.init(.{})) {
            std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
            std.process.exit(1);
        }

        // Create the test window and discover adapters using it (esp. for OpenGL)
        var hints = util.glfwWindowHintsForBackend(backend_type);
        hints.cocoa_retina_framebuffer = true;
        const window = glfw.Window.create(640, 480, "mach/gpu window", null, null, hints) orelse {
            std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
            std.process.exit(1);
        };

        if (backend_type == .opengl) glfw.makeContextCurrent(window);
        if (backend_type == .opengles) glfw.makeContextCurrent(window);
        const surface = try util.createSurfaceForWindow(instance.?, window, comptime util.detectGLFWOptions());

        var response: util.RequestAdapterResponse = undefined;
        instance.?.requestAdapter(&gpu.RequestAdapterOptions{
            .compatible_surface = surface,
            .power_preference = .undefined,
            .force_fallback_adapter = .false,
        }, &response, util.requestAdapterCallback);
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

        device.?.setUncapturedErrorCallback({}, util.printUnhandledErrorCallback);

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
        const queue = device.?.getQueue();

        // pipeline
        const vs = @embedFile("shader.wgsl");
        const vs_module = device.?.createShaderModuleWGSL("my vertex shader", vs);

        const fs = @embedFile("shader.wgsl");
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
            .entry_point = "fs_main",
            .targets = &.{color_target},
        });

        // vertex buffer
        const vertex_buffer = device.?.createBuffer(&.{
            .usage = .{ .vertex = true },
            .size = @sizeOf(Vertex) * vertices.len,
            .mapped_at_creation = .true,
        });
        const vertex_mapped = vertex_buffer.getMappedRange(Vertex, 0, vertices.len);
        @memcpy(vertex_mapped.?, vertices[0..]);
        vertex_buffer.unmap();

        // index buffer
        const index_buffer = device.?.createBuffer(&.{
            .usage = .{ .index = true },
            .size = roundToMultipleOf4(u64, @sizeOf(u16) * indices.len),
            .mapped_at_creation = .true,
        });
        const index_mapped = index_buffer.getMappedRange(u16, 0, indices.len);
        @memcpy(index_mapped.?, indices[0..]);
        index_buffer.unmap();

        // Texture
        const happy_tree = @embedFile("happy-tree.png");
        var img = try zigimg.Image.fromMemory(allocator, happy_tree);
        defer img.deinit();
        const img_size = gpu.Extent3D{ .width = @as(u32, @intCast(img.width)), .height = @as(u32, @intCast(img.height)) };

        const tex_desc = gpu.Texture.Descriptor.init(.{
            .label = "happy-tree",
            .size = img_size,
            .format = .rgba8_unorm_srgb,
            .usage = .{
                .texture_binding = true,
                .copy_dst = true,
                .render_attachment = true,
            },
            .mip_level_count = 1,
            .sample_count = 1,
        });
        const texture = device.?.createTexture(&tex_desc);

        // Upload the pixels (from the CPU) to the GPU. You could e.g. do this once per frame if you
        // wanted the image to be updated dynamically.
        const data_layout = gpu.Texture.DataLayout{
            .bytes_per_row = @as(u32, @intCast(img.width * 4)),
            .rows_per_image = @as(u32, @intCast(img.height)),
        };

        switch (img.pixels) {
            .rgba32 => |pixels| queue.writeTexture(&.{ .texture = texture }, &data_layout, &img_size, pixels),
            .rgb24 => |pixels| {
                const data = try rgb24ToRgba32(allocator, pixels);
                defer data.deinit(allocator);
                queue.writeTexture(&.{ .texture = texture }, &data_layout, &img_size, data.rgba32);
            },
            else => @panic("unsupported image color format"),
        }
        const tex_view = texture.createView(&.{});
        const sampler_desc = gpu.Sampler.Descriptor{
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
            .mag_filter = .linear,
            .min_filter = .nearest,
            .mipmap_filter = .nearest,
        };
        const tex_sampler = device.?.createSampler(&sampler_desc);

        const bind_grp_layout_desc = gpu.BindGroupLayout.Descriptor.init(.{
            .label = "tex_bind_group_layout",
            .entries = &.{
                .{
                    .binding = 0,
                    .visibility = .{ .fragment = true },
                    .texture = .{
                        .multisampled = gpu.Bool32.false,
                        .view_dimension = .dimension_2d,
                        .sample_type = .float,
                    },
                },
                .{
                    .binding = 1,
                    .visibility = .{ .fragment = true },
                    .sampler = .{
                        .type = .filtering,
                    },
                },
            },
        });
        const bind_group_layout = device.?.createBindGroupLayout(&bind_grp_layout_desc);
        const bind_group = device.?.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
            .layout = bind_group_layout,
            .entries = &.{
                gpu.BindGroup.Entry.textureView(0, tex_view),
                gpu.BindGroup.Entry.sampler(1, tex_sampler),
            },
        }));

        const primitive = gpu.PrimitiveState{
            .topology = .triangle_list,
            .front_face = .ccw,
            .cull_mode = .back,
        };
        const pipeline_layout = device.?.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(
            .{
                .label = "my pipeline layout",
                .bind_group_layouts = &.{bind_group_layout},
            },
        ));
        const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
            .fragment = &fragment,
            .layout = pipeline_layout,
            .depth_stencil = null,
            .vertex = gpu.VertexState.init(.{
                .module = vs_module,
                .entry_point = "vs_main",
                .buffers = &.{Vertex.desc()},
            }),
            .multisample = .{
                .count = 1,
                .mask = 0xFFFFFFFF,
                .alpha_to_coverage_enabled = gpu.Bool32.false,
            },
            .primitive = primitive,
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
            .queue = queue,
            .swap_chain = swap_chain,
            .swap_chain_desc = swap_chain_desc,
            .pipeline = pipeline,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .texture = texture,
            .texture_data_layout = data_layout,
            .bind_group = bind_group,
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
    fn frame(self: Self) !void {
        glfw.pollEvents();
        self.device.tick();

        const back_buffer_view = self.swap_chain.getCurrentTextureView().?;
        const color_attachment = gpu.RenderPassColorAttachment{
            .view = back_buffer_view,
            .resolve_target = null,
            // .clear_value = std.mem.zeroes(gpu.Color),
            .clear_value = gpu.Color{ .r = 0.1, .g = 0.2, .b = 0.3, .a = 1.0 },
            .load_op = .clear,
            .store_op = .store,
        };

        const encoder = self.device.createCommandEncoder(null);
        const render_pass_info = gpu.RenderPassDescriptor.init(.{
            .color_attachments = &.{color_attachment},
        });

        const pass = encoder.beginRenderPass(&render_pass_info);

        pass.setPipeline(self.pipeline);

        pass.setBindGroup(0, self.bind_group, &.{});
        pass.setVertexBuffer(0, self.vertex_buffer, 0, @sizeOf(Vertex) * vertices.len);
        pass.setIndexBuffer(self.index_buffer, .uint16, 0, @sizeOf(u16) * indices.len);

        pass.drawIndexed(
            indices.len,
            1, // instance_count
            0, // first_index
            0, // base_vertex
            0, // first_instance
        );

        pass.end();
        pass.release();

        var command = encoder.finish(null);
        encoder.release();

        self.queue.submit(&[_]*gpu.CommandBuffer{command});
        command.release();
        self.swap_chain.present();
        back_buffer_view.release();
    }
    pub fn frame2(self: Self) !void {
        _ = self;
    }
};

inline fn roundToMultipleOf4(comptime T: type, value: T) T {
    return (value + 3) & ~@as(T, 3);
}

fn rgb24ToRgba32(allocator: Allocator, in: []zigimg.color.Rgb24) !zigimg.color.PixelStorage {
    const out = try zigimg.color.PixelStorage.init(allocator, .rgba32, in.len);
    var i: usize = 0;
    while (i < in.len) : (i += 1) {
        out.rgba32[i] = zigimg.color.Rgba32{ .r = in[i].r, .g = in[i].g, .b = in[i].b, .a = 255 };
    }
    return out;
}

test "graphics" {
    const a = testing.allocator;
    const gfx = try Platform.init(a);
    _ = gfx;
}
