const std = @import("std");
const fonts = @import("fonts.zig");
const FontMgr = fonts.FontManager;
const GlyphRange = fonts.GlyphRange;
const Glyph = fonts.Glyph;
const Font = fonts.Font;
const Texture = @import("data.zig").Texture;

pub const Atlas = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    fonts: *const FontMgr,
    glyph_lookup: GlyphLookup,
    ready: bool = false,
    texels: []u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, fonts_mgr: *const FontMgr) Self {
        return .{
            .allocator = allocator,
            .fonts = fonts_mgr,
            .glyph_lookup = GlyphLookup.init(allocator),
        };
    }
    pub fn deinit(self: Self) void {
        if (self.ready) {
            self.allocator.free(self.texels);
        }
        self.glyph_lookup.deinit();
    }

    // TODO: This implementation only creates font atlas and even with fonts we only consider the first one.
    //  in the final implementation we should create uvWhite + all fonts + other texture elements.
    pub fn buildAtlas(self: *Self) !Texture {
        if (self.ready) {
            self.ready = false;
            self.allocator.free(self.texels);
        }
        // font calculation https://stackoverflow.com/a/68387730/3943054
        // TODO: this implementation only build the first Font. We need to find a cut and pack algo to create all fonts
        var buf: [4 * 1024]u8 = undefined;
        const font = self.fonts.getFonts()[0];
        try self.glyph_lookup.addFont(font);

        const g_count = font.range.size();
        var it = try self.fonts.glyphs(font.font_desc, &buf);

        const height = roundToNearestPow2(it.height);
        // we assume width for each glyph is equal to height, which is wasteful.
        const w = height * (g_count + 1); // plus one for uvWhite
        const width = roundToNearestPow2(w);
        var pixels = try self.allocator.alloc(u8, 4 * height * width);

        var pen_x: u32 = 0;
        const pen_y: u32 = 0; // This stays zero all the time. Because atm we have only one row
        // fill in the uvWhite in index zero.
        // TODO: This must be moved to the final stage, where we mix all fonts and other textures together to build the atlas
        for (0..height) |i| {
            const color = 0xff;
            const idx = i * width;
            greyscaleToRgba8(pixels[idx..], color);
        }
        // TODO: is it ok to put next glyph with no extra space? see the other pen_x inc line
        pen_x += 1;

        while (try it.next()) |*glyph| {
            for (0..glyph.height) |row| {
                for (0..glyph.width) |col| {
                    const x = pen_x + col;
                    const y = pen_y + row;
                    const buf_idx = row * glyph.width + col;
                    const color = it.buf[buf_idx];

                    const pix_idx = y * width + x;
                    greyscaleToRgba8(pixels[pix_idx..], color);
                }
            }
            { // add uv to the glyph and add it to the lookup
                var render_glyph = glyph.*;

                render_glyph.u0 = pen_x;
                render_glyph.v0 = pen_y;
                render_glyph.u1 = pen_x + glyph.width;
                render_glyph.v1 = pen_y + glyph.height;
                self.glyph_lookup.addGlyph(font, render_glyph);
            }

            // TODO: is this plus one necessary? Each texture can be placed right after the other
            pen_x += glyph.width + 1;
        }

        self.texels = pixels;
        self.ready = true;

        return .{ .texels = pixels, .width = width, .height = height };
    }
};
const GlyphLookup = struct {
    fonts: [fonts.max_num_font]?[]Glyph = [_]?[]Glyph{null} ** fonts.max_num_font,
    arena: std.heap.ArenaAllocator,

    fn init(allocator: std.mem.Allocator) GlyphLookup {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }
    fn deinit(self: GlyphLookup) void {
        self.arena.deinit();
    }

    /// add new glyph slice to the lookup map keyed to the font
    fn addFont(self: *GlyphLookup, font: Font) !void {
        if (self.fonts[font.font_desc] != null) {
            // TODO: reconstruct the whole fonts list
            std.debug.panic("NOT IMPLEMENTED", .{});
        }

        const glyphs = try self.arena.allocator().alloc(Glyph, font.range.size());
        self.fonts[font.font_desc] = glyphs;
    }

    fn addGlyphs(self: *GlyphLookup, font: Font, glyphs: []const Glyph) !void {
        std.debug.assert(font.range.size() == glyphs.len);

        if (self.fonts[font.font_desc]) |g_slice| {
            @memcpy(g_slice, glyphs);
        } else {
            try self.addFont(font);
            try self.addGlyphs(font, glyphs);
        }
    }
    /// Add one single glyph. The font must exist before adding the glyph
    inline fn addGlyph(self: *GlyphLookup, font: Font, glyph: Glyph) void {
        var gs = self.fonts[font.font_desc].?;

        const offset = font.range.lower;
        gs[glyph.char - offset] = glyph;
    }

    fn lookupChar(self: GlyphLookup, font: Font, char: u32) ?Glyph {
        if (self.fonts[font.font_desc]) |glyphs| {
            const offset = font.range.lower;
            return glyphs[char - offset];
        } else return null;
    }
};
inline fn greyscaleToRgba8(buf: []u8, color: u8) void {
    // TODO: convert greyscale to RGBA: is it the right algo?
    std.debug.assert(buf.len >= 4);
    buf[0] = color;
    buf[1] = color;
    buf[2] = color;
    buf[3] = 0xff;
}
fn roundToNearestPow2(n: u32) u32 {
    if (n == 0 or n == 1) return 2;
    const nlz = @clz(n - 1);
    // This cast is not safe if nlz is zero. TODO: reject it?
    return (@as(u32, 1) << @intCast((32 - nlz)));
}

const expect = std.testing.expect;
const test_alloc = std.testing.allocator;
const roboto_reg = @import("assets").fonts_roboto_regular;
test "Atlas" {
    var fm = try FontMgr.init(test_alloc, 300);
    defer fm.deinit();
    const face_desc = try fm.addFaceMemory(roboto_reg);
    _ = fm.addFont(face_desc, 12, GlyphRange.asciiPrintable());

    var atlas = Atlas.init(test_alloc, &fm);
    defer atlas.deinit();
    const texture = try atlas.buildAtlas();
    std.log.warn("w: {d} h: {d}", .{ texture.width, texture.height });
}

test "GlyphLookup" {
    var gl = GlyphLookup.init(test_alloc);
    defer gl.deinit();

    const g_range = GlyphRange{ .lower = 35, .upper = 40 };
    const f1 = Font{ .font_desc = 0, .face_desc = 0, .size = 0, .range = g_range };
    const f2 = Font{ .font_desc = 1, .face_desc = 0, .size = 0, .range = g_range };

    const g1 = Glyph{ .char = 35, .height = 0, .width = 0 };
    const gs = [_]Glyph{g1} ** g_range.size();

    // add glyphs when font is not added should result in adding the font
    try gl.addGlyphs(f2, &gs);

    try gl.addFont(f1);
    try gl.addGlyphs(f1, &gs);

    const f1_g1 = gl.lookupChar(f1, 35);
    const f2_g1 = gl.lookupChar(f2, 35);

    try expect(f1_g1.?.char == 35);
    try expect(f2_g1.?.char == 35);
}
