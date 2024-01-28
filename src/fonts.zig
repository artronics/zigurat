const std = @import("std");
const freetype = @import("freetype");

pub const FaceDescriptor = usize;

const max_num_face = 16;
pub const FontManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _dpi: u16,
    _faces: [max_num_face]freetype.Face = undefined,
    _freetype: freetype.Library,
    _face_desc: FaceDescriptor = 0,

    pub fn init(allocator: std.mem.Allocator, dpi: u16) !Self {
        const lib = try freetype.Library.init();

        return .{
            .allocator = allocator,
            ._dpi = dpi,
            ._freetype = lib,
        };
    }
    pub fn deinit(self: Self) void {
        self._freetype.deinit();
    }
    pub fn addFaceMemory(self: *Self, buf: []const u8) !FaceDescriptor {
        std.debug.assert(self._face_desc < 16);

        const face = try self._freetype.createFaceMemory(buf, 0);
        const index = self._face_desc;
        self._faces[index] = face;

        self._face_desc += 1;

        return index;
    }

    pub fn glyphs(self: *Self, fd: FaceDescriptor, buf: []u8, size: i32, range_lower: u32, range_upper: u32) !GlyphIterator {
        const face = self._faces[fd];
        try face.setCharSize(64 * size, 0, self._dpi, 0);
        const metrics = face.size().metrics();
        return .{
            .face = face,
            .buf = buf,
            .upper = range_upper,
            .lower = range_lower,
            .size = size,
            .height = @as(u32, @intCast(metrics.height)) >> 6,
            .index = range_lower,
        };
    }

    const GlyphIterator = struct {
        face: freetype.Face,
        buf: []u8,
        upper: u32,
        lower: u32,
        size: i32,
        height: u32,

        index: u32,

        pub fn next(gi: *GlyphIterator) !?Glyph {
            if (gi.index >= gi.upper) return null;

            try gi.face.loadChar(@intCast(gi.index), .{ .render = true, .force_autohint = true, .target_light = true });
            const bmp = gi.face.glyph().bitmap();
            const width = bmp.width();
            const height = bmp.rows();

            const glyph = Glyph{
                .char = gi.index,
                .height = height,
                .width = width,
                .x_off = gi.face.glyph().bitmapLeft(),
                .y_off = gi.face.glyph().bitmapTop(),
                .advance_x = @intCast((try gi.face.glyph().getGlyph()).advanceX() >> 6),
            };
            // TODO: not considering bmp.pitch(), then this can be a mem copy from glyph buffer
            for (0..height) |row| {
                for (0..width) |col| {
                    const buf_idx = row * @abs(bmp.pitch()) + col;
                    const color = bmp.buffer().?[buf_idx];
                    gi.buf[buf_idx] = color;
                }
            }

            gi.index += 1;
            return glyph;
        }
    };
};

const Glyph = struct {
    char: u32,
    width: u32,
    height: u32,
    x_off: i32 = 0,
    y_off: i32 = 0,
    advance_x: i32 = 0,
};

const test_alloc = std.testing.allocator;
const expect = std.testing.expect;
const roboto_reg = @import("assets").fonts_roboto_regular;

test "FontManager" {
    var fm = try FontManager.init(test_alloc, 300);
    defer fm.deinit();
    const fd = try fm.addFaceMemory(roboto_reg);

    var buf: [4 * 1024]u8 = undefined;
    var it = try fm.glyphs(fd, &buf, 12, 32, 126);
    std.log.warn("Font size {d}", .{@sizeOf(freetype.Face)});
    while (try it.next()) |glyph| {
        std.log.warn("ch {c}, w: {d}", .{ @as(u8, @intCast(glyph.char)), glyph.height });
    }
}
