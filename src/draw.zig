const std = @import("std");
const data = @import("data.zig");
const Vertex = data.Vertex;
const Index = data.Index;
const Uniforms = data.Uniforms;
const Point = data.Point;
const Color = data.Color;
const font = @import("font.zig");
const GlyphAtlas = font.GlyphAtlas;

pub const Rect = struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    pub inline fn fromWH(x0: f32, y0: f32, width: f32, height: f32) Rect {
        return .{ .x0 = x0, .y0 = y0, .x1 = x0 + width, .y1 = y0 + height };
    }
    inline fn toIndices(offset: Index) [6]Index {
        return [6]Index{ offset + 0, offset + 1, offset + 2, offset + 0, offset + 2, offset + 3 };
    }

    inline fn toPosition(rect: Rect) [4]Point {
        return [4]Point{ rect.a(), rect.b(), rect.c(), rect.d() };
    }
    inline fn a(rect: Rect) Point {
        return .{ .x = rect.x0, .y = rect.y0 };
    }
    inline fn b(rect: Rect) Point {
        return .{ .x = rect.x1, .y = rect.y0 };
    }
    inline fn c(rect: Rect) Point {
        return .{ .x = rect.x1, .y = rect.y1 };
    }
    inline fn d(rect: Rect) Point {
        return .{ .x = rect.x0, .y = rect.y1 };
    }
};

pub const Text = struct {
    text: []const u8,
    baseline: Point,
};

const VertexBuffer = std.ArrayList(Vertex);
const IndexBuffer = std.ArrayList(Index);

const Self = @This();

allocator: std.mem.Allocator,
_index_buffer: IndexBuffer,
_vertex_buffer: VertexBuffer,

pub fn init(allocator: std.mem.Allocator, comptime buffer_inc_size: usize) Self {
    return .{
        .allocator = allocator,
        ._vertex_buffer = VertexBuffer.initCapacity(allocator, buffer_inc_size) catch unreachable,
        ._index_buffer = IndexBuffer.initCapacity(allocator, buffer_inc_size) catch unreachable,
    };
}
pub fn deinit(self: Self) void {
    self._index_buffer.deinit();
    self._vertex_buffer.deinit();
}
pub fn rectUv(self: *Self, rect: Rect, texture: Rect) !void {
    const vert_idx = self._vertex_buffer.items.len;
    try self._index_buffer.appendSlice(&Rect.toIndices(@intCast(vert_idx)));

    inline for (rect.toPosition()) |pos| {
        const v = Vertex{ .position = .{ pos.x, pos.y }, .uv = texture.a().toVec(), .color = .{ 0, 1, 1, 1 } };
        try self._vertex_buffer.append(v);
    }
}

fn drawText(self: Self, text: *const Text) !void {
    _ = text;
    _ = self;
}

pub inline fn vertexBufferSize(self: Self) usize {
    return self._vertex_buffer.items.len;
}
pub inline fn indexBufferSize(self: Self) usize {
    return self._index_buffer.items.len;
}
pub inline fn vertices(self: Self) []const Vertex {
    return self._vertex_buffer.items;
}
pub inline fn indices(self: Self) []const Index {
    return self._index_buffer.items;
}

const test_alloc = std.testing.allocator;
const expect = std.testing.expect;
const expectSlice = std.testing.expectEqualSlices;

test "draw" {
    const rect1 = .{ .x0 = 1.0, .y0 = 2.0, .x1 = 3.0, .y1 = 4.0 };
    const rect2 = .{ .x0 = 10, .y0 = 20, .x1 = 30, .y1 = 40 };
    const uv = .{ .x0 = 10, .y0 = 20, .x1 = 30, .y1 = 40 };

    { // Draw Primitive
        var d = init(test_alloc, 10);
        defer d.deinit();

        try d.rectUv(rect1, uv);
        try d.rectUv(rect2, uv);

        // CW triangle direction
        const verts = d._vertex_buffer.items;
        const inds = d._index_buffer.items;
        // first primitive
        try expect(verts[0].position[0] == 1.0);
        try expect(verts[1].position[0] == 3.0);
        try expect(verts[2].position[0] == 3.0);
        try expect(verts[3].position[0] == 1.0);

        var offset: Index = 0;
        try expect(inds[0] == offset + 0);
        try expect(inds[1] == offset + 1);
        try expect(inds[2] == offset + 2);
        try expect(inds[3] == offset + 0);
        try expect(inds[4] == offset + 2);
        try expect(inds[5] == offset + 3);

        // second primitive
        try expect(verts[4].position[0] == 10);
        try expect(verts[5].position[0] == 30);
        try expect(verts[6].position[0] == 30);
        try expect(verts[7].position[0] == 10);

        offset += 4;
        try expect(inds[6] == offset + 0);
        try expect(inds[7] == offset + 1);
        try expect(inds[8] == offset + 2);
        try expect(inds[9] == offset + 0);
        try expect(inds[10] == offset + 2);
        try expect(inds[11] == offset + 3);
    }
}
