const std = @import("std");
const data = @import("data.zig");
const Vertex = data.Vertex;
const Uniforms = data.Uniforms;
const Point = data.Point;
const Color = data.Color;

const Queue = u32;

pub const Rect = struct {
    a: Point,
    b: Point,
    fn addToQueue(r: Rect, queue: Queue) void {
        _ = queue;
        _ = r;
    }
};

pub const Primitive = union(enum) {
    rect: Rect,
    pub inline fn addToQueue(pm: Primitive, queue: u32) void {
        switch (pm) {
            inline else => |case| case.addToQueue(queue),
        }
    }
};

pub const DrawCommand = union(enum) {
    primitive: Primitive,
    bg_color: Color,
};

pub const CommandQueue = std.ArrayList(DrawCommand);
