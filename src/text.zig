const std = @import("std");
const HashMap = std.StringArrayHashMap;
const freetype = @import("freetype");
const roboto_reg = @import("assets").fonts_roboto_regular;

pub const GlyphCollection = struct {
    lower: u32,
    upper: u32,
    max_width: u32,
    max_height: u32,
    total_width: u32,
    total_height: u32,
    arena: std.heap.ArenaAllocator,
    glyphs: std.ArrayList(Glyph),
    pub fn deinit(gc: GlyphCollection) void {
        gc.arena.deinit();
    }
    pub fn getChar(gc: GlyphCollection, ch: u32) Glyph {
        std.debug.assert(ch >= gc.lower and ch < gc.upper);
        return gc.glyphs.items[ch - gc.lower];
    }
};
pub const Glyph = struct {
    char: u32,
    width: u32,
    height: u32,
    bitmap: []u8 = undefined,
    x_off: i32 = 0,
    y_off: i32 = 0,
    advance_x: i32 = 0,
};
pub const TextLayout = struct {};
pub const Font = struct {
    name: []const u8,
    face: freetype.Face,
};

pub const Text = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    fonts: HashMap(Font),
    freetype: freetype.Library,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const fonts = HashMap(Font).init(allocator);
        const lib = try freetype.Library.init();

        return .{
            .allocator = allocator,
            .fonts = fonts,
            .freetype = lib,
        };
    }
    pub fn deinit(self: *Self) void {
        self.freetype.deinit();
        self.fonts.deinit();
    }

    pub fn addFontMemory(self: *Self, name: []const u8, font: []const u8) !void {
        const face = try self.freetype.createFaceMemory(font, 0);
        try self.fonts.put(name, .{ .name = name, .face = face });
    }
    pub fn renderCharsRange(self: Self, name: []const u8, size: i32, lower: u32, upper: u32) !GlyphCollection {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        const allocator = arena.allocator();

        const font = self.fonts.get(name);
        const face = font.?.face;
        try face.setCharSize(64 * size, 0, 300, 0);

        var total_w: u32 = 0;
        var total_h: u32 = 0;
        var max_w: u32 = 0;
        var max_h: u32 = 0;
        var glyphs = try std.ArrayList(Glyph).initCapacity(allocator, upper - lower);
        for (lower..upper) |ch| {
            try face.loadChar(@intCast(ch), .{ .render = true, .force_autohint = true, .target_light = true });
            const bmp = face.glyph().bitmap();

            const width = bmp.width();
            const height = bmp.rows();
            total_w += width;
            total_h += height;
            max_w = @max(max_w, width);
            max_h = @max(max_h, height);

            const glyph = Glyph{
                .char = @intCast(ch),
                .height = height,
                .width = width,
                .bitmap = try allocator.alloc(u8, height * width),
                .x_off = face.glyph().bitmapLeft(),
                .y_off = face.glyph().bitmapTop(),
                .advance_x = @intCast((try face.glyph().getGlyph()).advanceX() >> 6),
            };

            // TODO: not considering bmp.pitch(), then this can be a mem copy from glyph buffer
            for (0..height) |row| {
                for (0..width) |col| {
                    const buf_idx = row * @abs(bmp.pitch()) + col;
                    const color = bmp.buffer().?[buf_idx];
                    glyph.bitmap[buf_idx] = color;
                }
            }

            try glyphs.append(glyph);
        }

        return GlyphCollection{
            .arena = arena,
            .lower = lower,
            .upper = upper,
            .total_height = total_h,
            .total_width = total_w,
            .max_height = max_h,
            .max_width = max_w,
            .glyphs = glyphs,
        };
    }
    pub fn layoutText(self: Self, name: []const u8, text: []const u8) TextLayout {
        _ = self;
        _ = text;
        _ = name;
    }
};

const expect = std.testing.expect;
const test_alloc = std.testing.allocator;
test "text" {
    var t = try Text.init(test_alloc);
    defer t.deinit();

    const name = "test-font";
    try t.addFontMemory(name, roboto_reg);

    const glyphs = try t.renderCharsRange(name, 12, 32, 126);
    defer glyphs.deinit();

    const a = glyphs.getChar('a');
    try expect(a.char == 'a');
}
