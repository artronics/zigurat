const std = @import("std");
const Text = @import("text.zig").Text;
const data = @import("data.zig");
const Texture = data.Texture;
const roboto_reg = @import("assets").fonts_roboto_regular;

const Atlas = struct {};

const Self = @This();
allocator: std.mem.Allocator,
text: *Text,
height: u32 = 0,
width: u32 = 0,
texels: []u8 = undefined,
_ready: bool = false,

// it doesn't own text
pub fn init(allocator: std.mem.Allocator, text: *Text) !Self {
    return .{
        .allocator = allocator,
        .text = text,
    };
}
pub fn deinit(self: Self) void {
    self.allocator.free(self.texels);
}

pub fn buildTexture(self: *Self) !Texture {
    // TODO: free memory if _ready was true
    self._ready = false;
    // This block should be set by client. TODO: iterate over keys of fonts and build the atlas with all GlyphCollections
    const name = "ui-font";
    try self.text.addFontMemory(name, roboto_reg);

    const glyphs = try self.text.renderCharsRange(name, 12, 32, 126);
    defer glyphs.deinit();
    // end
    self.height = roundToNearestPow2(glyphs.max_height);
    self.width = roundToNearestPow2(glyphs.total_width);

    self.texels = try self.allocator.alloc(u8, 4 * self.width * self.height);
    var pen_x: u32 = 0;

    // fill uvWhite glyph. We only fill the first column even though it has reserved space for full ch_w
    for (0..self.height) |i| {
        const color = 0xff;
        const idx = i * self.width;
        self.greyscaleToRgba8(idx, color);
    }
    // TODO: is it ok to put next glyph with no extra space? see the other pen_x inc line
    pen_x += 1 + 1;

    for (glyphs.glyphs.items) |glyph| {
        for (0..glyph.height) |row| {
            for (0..glyph.width) |col| {
                const x = pen_x + col;
                const y = row;
                const buf_idx = row * glyph.width + col;
                const color = glyph.bitmap[buf_idx];

                const pix_idx = y * self.width + x;
                self.greyscaleToRgba8(pix_idx, color);
            }
        }
        // TODO: is this plus one necessary? Each texture can be placed right after the other
        pen_x += glyph.width + 1;
    }
    self._ready = true;

    std.log.info("texture: {d} X {d}", .{self.width, self.height});
    return .{
        .width = self.width,
        .height = self.height,
        .texels = self.texels,
    };
}
inline fn greyscaleToRgba8(self: Self, idx: usize, color: u8) void {
    // TODO: convert greyscale to RGBA: is it the right algo?
    self.texels[idx + 0] = color;
    self.texels[idx + 1] = color;
    self.texels[idx + 2] = color;
    self.texels[idx + 3] = 0xff;
}

fn roundToNearestPow2(n: u32) u32 {
    if (n == 0 or n == 1) return 2;
    const nlz = @clz(n - 1);
    // This cast is not safe if nlz is zero. TODO: reject it?
    return (@as(u32, 1) << @intCast((32 - nlz)));
}
