const gpu = @import("gpu");

pub const Size = extern struct {
    width: u32,
    height: u32,
    pub inline fn eql(a: Size, b: Size) bool {
        return a.width == b.width and a.height == b.height;
    }
};

pub const Point = extern struct {
    x: f32,
    y: f32,
    pub inline fn toVec(p: Point) [2]f32 {
        return .{ p.x, p.y };
    }
};
pub const RectBound = extern struct {
    a: Point,
    c: Point,
};

pub const TextureCoordinate = extern struct {
    u: f32,
    v: f32,
};
pub const TextureBound = extern struct {
    a: TextureCoordinate,
    c: TextureCoordinate,
};

pub const Color = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const Index = u16;

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
    gamma: f32,
};
