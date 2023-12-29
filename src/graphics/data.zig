const gpu = @import("platform").gpu;

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

pub const RenderData = struct {
    // TODO: move layout, desc and bg(?) here
    const Self = @This();

    device: *gpu.Device,

    vertex_buffer: *gpu.Buffer,
    index_buffer: *gpu.Buffer,
    uniforms_buffer: *gpu.Buffer,
    sampler: *gpu.Sampler,

    const index_size = 10000;
    const vertex_size = 10000;

    pub fn init(device: *gpu.Device) Self {
        const uniforms_buf = device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = @sizeOf(Uniforms),
            .mapped_at_creation = .false,
        });
        const vertex_buf = device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = @sizeOf(Vertex) * vertex_size,
            .mapped_at_creation = .false,
        });
        const index_buf = device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .index = true },
            .size = roundToMultipleOf4(u64, @sizeOf(u16) * index_size),
            .mapped_at_creation = .false,
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
};

inline fn roundToMultipleOf4(comptime T: type, value: T) T {
    return (value + 3) & ~@as(T, 3);
}
