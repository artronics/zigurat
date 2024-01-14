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
    inline fn toVertices(self: Rect) [4]Vertex {
        const color = [_]f32{1.0} ** 4;
        const uv = [_]f32{0.0} ** 2;
        const a = .{ .position = .{ self.x0, self.y0 }, .color = color, .uv = uv };
        const b = .{ .position = .{ self.x1, self.y0 }, .color = color, .uv = uv };
        const c = .{ .position = .{ self.x1, self.y1 }, .color = color, .uv = uv };
        const d = .{ .position = .{ self.x0, self.y1 }, .color = color, .uv = uv };
        return [4]Vertex{ a, b, c, d };
    }
    inline fn toIndices(self: Rect, offset: Index) [6]Index {
        _ = self;
        return [6]Index{ offset + 0, offset + 1, offset + 2, offset + 0, offset + 2, offset + 3 };
    }
};

pub const Text = struct {
    text: []const u8,
    baseline: Point,
};

pub const Primitive = union(enum) {
    rect: Rect,
    text: Text,
};

pub const DrawCommand = union(enum) {
    primitive: Primitive,
    bg_color: Color,
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

pub fn draw(self: *Self, queue: []const DrawCommand) !void {
    self._index_buffer.clearRetainingCapacity();
    self._vertex_buffer.clearRetainingCapacity();

    var vtx_idx: usize = 0;
    var idx_idx: usize = 0;

    for (queue) |cmd| {
        vtx_idx += 1;
        idx_idx += 1;
        switch (cmd) {
            .primitive => |pmt| try self.drawPrimitive(&pmt),
            else => unreachable,
        }
    }
}

fn drawPrimitive(self: *Self, primitive: *const Primitive) !void {
    const cur_vrt_index = self._vertex_buffer.items.len;

    switch (primitive.*) {
        .rect => |rect| {
            try self._vertex_buffer.appendSlice(&rect.toVertices());
            try self._index_buffer.appendSlice(&rect.toIndices(@intCast(cur_vrt_index)));
        },
        .text => |text| try self.drawText(&text),
    }
}
fn drawText(self: Self, text: *const Text) !void {
    _ = text;
    _ = self;
}

const test_alloc = std.testing.allocator;
const expect = std.testing.expect;
const expectSlice = std.testing.expectEqualSlices;

test "draw" {
    const rect1 = .{ .primitive = .{
        .rect = .{ .x0 = 1.0, .y0 = 2.0, .x1 = 3.0, .y1 = 4.0 },
    } };
    const rect2 = .{ .primitive = .{
        .rect = .{ .x0 = 10, .y0 = 20, .x1 = 30, .y1 = 40 },
    } };

    { // Draw Primitive
        const cmd_q = [_]DrawCommand{ rect1, rect2 };
        var d = init(test_alloc, 10);
        defer d.deinit();

        try d.draw(&cmd_q);

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

    { // Clear buffers in each draw call, but retain the capacity
        const cmd_q = [_]DrawCommand{rect1};
        var d = init(test_alloc, 0);
        defer d.deinit();

        try d.draw(&cmd_q);
        try d.draw(&cmd_q);

        try expect(d._vertex_buffer.items.len == 4);
        try expect(d._vertex_buffer.capacity == 8);
    }
}

// const white = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
// const uv = [_]f32{ 0.0, 0.0 };
// const vertices = [_]Vertex{
//     .{ .position = .{ 100.0, 100.0 }, .uv = .{ 0.0, 0.0 }, .color = white },
//     .{ .position = .{ 200.0, 100.0 }, .uv = .{ 1.0, 0.0 }, .color = white },
//     .{ .position = .{ 200.0, 200.0 }, .uv = .{ 1.0, 1.0 }, .color = white },
//     .{ .position = .{ 100.0, 200.0 }, .uv = .{ 0.0, 1.0 }, .color = white },
// };
// const indices = [_]u16{
//     0, 1, 3,
//     1, 2, 3,
// };
