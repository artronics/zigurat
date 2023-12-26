const std = @import("std");
const Allocator = std.mem.Allocator;
const gpu = @import("gpu");
const glfw = @import("glfw");
const testing = std.testing;
const expect = testing.expect;
const objc = @import("objc_message.zig");
const util = @import("util.zig");

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

        // pipeline
        const vs = @embedFile("shader.vert.wgsl");
        const vs_module = device.?.createShaderModuleWGSL("my vertex shader", vs);

        const fs = @embedFile("shader.frag.wgsl");
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

test "graphics" {
    const a = testing.allocator;
    const gfx = try Platform.init(a);
    _ = gfx;
}
