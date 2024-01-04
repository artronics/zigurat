const std = @import("std");
const cm = @import("common");
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
