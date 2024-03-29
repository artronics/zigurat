const std = @import("std");
const freetype = @import("freetype");

pub const FaceDescriptor = usize;
pub const FontDescriptor = usize;
pub const max_num_face = 16;
pub const max_num_font = 32;

pub const Glyph = struct {
    char: u32,
    width: u32,
    height: u32,
    x_off: i32 = 0,
    y_off: i32 = 0,
    advance_x: i32 = 0,
    u0: u32 = 0,
    v0: u32 = 0,
    u1: u32 = 0,
    v1: u32 = 0,
};

/// A range of [lower..upper) characters in UTF-8 space.
pub const GlyphRange = struct {
    lower: u32,
    upper: u32,
    pub fn asciiPrintable() GlyphRange {
        return .{ .lower = 32, .upper = 127 };
    }
    pub inline fn size(self: GlyphRange) u32 {
        return self.upper - self.lower;
    }
};

pub const Font = struct {
    font_desc: FontDescriptor,
    face_desc: FaceDescriptor,
    range: GlyphRange,
    size: i32,
};

pub const FontManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _dpi: u16,
    _faces: [max_num_face]freetype.Face = undefined,
    _fonts: [max_num_font]Font = undefined,
    _freetype: freetype.Library,
    _face_desc: FaceDescriptor = 0,
    _font_desc: FontDescriptor = 0,

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
        std.debug.assert(self._face_desc < max_num_face);

        const face = try self._freetype.createFaceMemory(buf, 0);
        const index = self._face_desc;
        self._faces[index] = face;

        self._face_desc += 1;

        return index;
    }
    pub fn addFont(self: *Self, face_desc: FaceDescriptor, size: i32, range: GlyphRange) FontDescriptor {
        std.debug.assert(self._font_desc < max_num_font);

        const index = self._font_desc;
        self._fonts[index] = Font{ .font_desc = index, .face_desc = face_desc, .size = size, .range = range };

        self._font_desc += 1;

        return index;
    }
    pub fn getFonts(self: Self) []const Font {
        return self._fonts[0..self._font_desc];
    }

    // TODO: we should pass dpi here. DPI is a render parameter so, it doesn't make sense to keep it in the instance
    pub fn glyphs(self: Self, font_desc: FontDescriptor, buf: []u8) !GlyphIterator {
        const font = self._fonts[font_desc];
        const face = self._faces[font.face_desc];
        try face.setCharSize(64 * font.size, 0, self._dpi, 0);
        const metrics = face.size().metrics();

        return .{
            .face = face,
            .buf = buf,
            .upper = font.range.upper,
            .lower = font.range.lower,
            .size = font.size,
            .height = @as(u32, @intCast(metrics.height)) >> 6,
            .index = font.range.lower,
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

const test_alloc = std.testing.allocator;
const expect = std.testing.expect;
const roboto_reg = @import("assets").fonts_roboto_regular;

test "FontManager" {
    var fm = try FontManager.init(test_alloc, 300);
    defer fm.deinit();
    const face_desc = try fm.addFaceMemory(roboto_reg);
    const font_desc = fm.addFont(face_desc, 12, GlyphRange.asciiPrintable());

    var buf: [4 * 1024]u8 = undefined;
    var it = try fm.glyphs(font_desc, &buf);
    while (try it.next()) |glyph| {
        _ = glyph;
        // std.log.warn("ch {c}, w: {d}", .{ @as(u8, @intCast(glyph.char)), glyph.height });
    }
}
