const gpu = @import("platform").gpu;

pub const Vertex = struct {
    pos: @Vector(2, f32),
    uv: @Vector(2, f32),
    col: @Vector(4, u8),

    const attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x3, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0 },
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 1 },
        .{ .format = .float32x3, .offset = @offsetOf(Vertex, "col"), .shader_location = 2 },
    };

    pub fn desc() gpu.VertexBufferLayout {
        return gpu.VertexBufferLayout.init(.{
            .array_stride = @sizeOf(Vertex),
            .step_mode = .vertex,
            .attributes = &attributes,
        });
    }
};
