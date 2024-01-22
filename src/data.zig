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

pub const Rect = struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    pub inline fn fromWH(x0: f32, y0: f32, width: f32, height: f32) Rect {
        return .{ .x0 = x0, .y0 = y0, .x1 = x0 + width, .y1 = y0 + height };
    }
    pub inline fn toIndices(offset: Index) [6]Index {
        return [6]Index{ offset + 0, offset + 1, offset + 2, offset + 0, offset + 2, offset + 3 };
    }

    pub inline fn toPosition(rect: Rect) [4]Point {
        return [4]Point{ rect.a(), rect.b(), rect.c(), rect.d() };
    }
    pub inline fn a(rect: Rect) Point {
        return .{ .x = rect.x0, .y = rect.y0 };
    }
    pub inline fn b(rect: Rect) Point {
        return .{ .x = rect.x1, .y = rect.y0 };
    }
    pub inline fn c(rect: Rect) Point {
        return .{ .x = rect.x1, .y = rect.y1 };
    }
    pub inline fn d(rect: Rect) Point {
        return .{ .x = rect.x0, .y = rect.y1 };
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
    pub const white: Color = .{ .r = 1, .g = 1, .b = 1, .a = 1 };
    pub const black: Color = .{ .r = 0, .g = 0, .b = 0, .a = 1 };
    pub const red: Color = .{ .r = 1, .g = 0, .b = 0, .a = 1 };

    pub fn eq(this: Color, other: Color) bool {
        return this.r == other.r and this.g == other.g and this.b == other.b and this.a == other.a;
    }
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

pub const Texture = struct {
    width: u32,
    height: u32,
    texels: []const u8,
};
