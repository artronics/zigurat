const gpu = @import("platform").gpu;
const pm = @import("primitive.zig");
const Vertex = pm.Vertex;
const Uniforms = pm.Uniforms;

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
