const std = @import("std");
const FontMgr = @import("fonts.zig").FontManager;
const data = @import("data.zig");
const Texture = data.Texture;
const roboto_reg = @import("assets").fonts_roboto_regular;

const Atlas = struct {
    texels: []const u8,
};

const Self = @This();
allocator: std.mem.Allocator,
fonts: *FontMgr,
height: u32 = 0,
width: u32 = 0,
texels: []u8 = undefined,
_ready: bool = false,

// it doesn't own font_manager
pub fn init(allocator: std.mem.Allocator, font_manager: *FontMgr) !Self {
    return .{
        .allocator = allocator,
        .fonts = font_manager,
        // .texels = try std.ArrayList(u8).initCapacity(allocator, 4 * 1024),
    };
}
pub fn deinit(self: Self) void {
    if (self._ready) {
        self.allocator.free(self.texels);
    }
}

pub fn buildTexture(self: *Self) !Texture {
    // TODO: free memory if _ready was true
    self._ready = false;
    // This block should be set by client. TODO: iterate over keys of fonts and build the atlas with all GlyphCollections
    const fd = try self.fonts.addFaceMemory(roboto_reg);

    var buf: [4 * 1024]u8 = undefined;
    var glyphs = try self.fonts.glyphs(fd, &buf, 12, 32, 126);

    // This atlas will be one row only
    self.height = roundToNearestPow2(glyphs.height);
    // TODO: width is not known
    self.width = self.height;
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

    while (try glyphs.next()) |glyph| {
        for (0..glyph.height) |row| {
            for (0..glyph.width) |col| {
                const x = pen_x + col;
                const y = row;
                const buf_idx = row * glyph.width + col;
                const color = buf[buf_idx];

                const pix_idx = y * self.width + x;
                self.greyscaleToRgba8(pix_idx, color);
            }
        }
        // TODO: is this plus one necessary? Each texture can be placed right after the other
        pen_x += glyph.width + 1;
    }
    self._ready = true;

    std.log.info("texture: {d} X {d}", .{ self.width, self.height });
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
