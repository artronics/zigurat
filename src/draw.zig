const std = @import("std");
const data = @import("data.zig");
const Vertex = data.Vertex;
const Index = data.Index;
const Uniforms = data.Uniforms;
const Point = data.Point;
const Color = data.Color;
const Rect = data.Rect;

pub const Option = union(enum) {
    text_color: Color,
};

const Options = struct {
    text_color: Color = Color.red,
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
_options: std.ArrayList(Options),

pub fn init(allocator: std.mem.Allocator, comptime buffer_inc_size: usize) Self {
    var option = std.ArrayList(Options).initCapacity(allocator, 64) catch unreachable;
    option.append(.{}) catch unreachable;

    return .{
        .allocator = allocator,
        ._vertex_buffer = VertexBuffer.initCapacity(allocator, buffer_inc_size) catch unreachable,
        ._index_buffer = IndexBuffer.initCapacity(allocator, buffer_inc_size) catch unreachable,
        ._options = option,
    };
}
pub fn deinit(self: Self) void {
    self._index_buffer.deinit();
    self._vertex_buffer.deinit();
    self._options.deinit();
}

pub fn push(self: *Self, opt: Option) void {
    var head = self._options.getLast();
    switch (opt) {
        Option.text_color => |tc| head.text_color = tc,
    }
    self._options.append(head) catch unreachable;
}

pub fn pop(self: *Self) void {
    _ = self._options.pop();
}

pub fn rectUv(self: *Self, rect: Rect, texture: Rect) !void {
    const vert_idx = self._vertex_buffer.items.len;
    try self._index_buffer.appendSlice(&Rect.toIndices(@intCast(vert_idx)));

    inline for (0..4, rect.toPosition()) |i, pos| {
        const v = Vertex{ .position = .{ pos.x, pos.y }, .uv = texture.point(i).toVec(), .color = .{ 1, 1, 1, 1 } };
        try self._vertex_buffer.append(v);
    }
}
// TODO: draw shouldn't know about text. User rect_uv for texture rendering instead
pub fn char(self: Self, ch: u8) !void {
    _ = ch;
    _ = self;
}

inline fn getOption(self: Self) Options {
    return self._options.getLast();
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

test "options" {
    { // Defaults
        var d = init(test_alloc, 10);
        defer d.deinit();

        const last = d.getOption();
        try expect(last.text_color.eq(Color.red));
    }
    { // stack
        var d = init(test_alloc, 10);
        defer d.deinit();

        d.push(.{ .text_color = Color.white });
        d.push(.{ .text_color = Color.red });
        var last = d.getOption();
        try expect(last.text_color.eq(Color.red));

        d.pop();
        last = d.getOption();
        try expect(last.text_color.eq(Color.white));
    }
}
