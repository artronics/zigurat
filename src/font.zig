const std = @import("std");
const Allocator = std.mem.Allocator;
const data = @import("data.zig");
const Point = data.Point;
const freetype = @import("freetype");
const RecBound = data.RectBound;
const TexBound = data.TextureBound;
const roboto_reg = @import("assets").fonts_roboto_regular;

const log = std.log.scoped(.zigurat);

//Notes:
// bidi processing: https://harfbuzz.github.io/what-harfbuzz-doesnt-do.html

// TODO: REFACTOR: This module shouldn't create the atlas. Instead, it should only render each individual glyph
//  to a memory block and let the texture module to create the final atlas. Also the texture module(or any client) should
//  be able to delete the allocated memory for the glyph range, once it built the final atlas. There is no point keeping
//  the memory around.

const Self = @This();

const Font = struct {
    size_px: f32,
};

const Glyph = struct {
    x0: u32 = 0,
    y0: u32 = 0,
    x1: u32 = 0,
    y1: u32 = 0,
    x_off: i32 = 0,
    y_off: i32 = 0,
    advance_x: i32 = 0,
};

const num_glyphs: u32 = 128;
var en_glyphs = [_]Glyph{.{}} ** num_glyphs;

allocator: Allocator,
freetype_lib: freetype.Library,
face: freetype.Face,
pixels: []u8 = undefined,
width: u32 = 0,
height: u32 = 0,
pixels_rgba: []u8 = undefined,
tex_width: u32 = 0,

pub fn init(allocator: Allocator) !Self {
    const lib = try freetype.Library.init();

    const face = try lib.createFaceMemory(roboto_reg, 0);

    return .{
        .allocator = allocator,
        .freetype_lib = lib,
        .face = face,
    };
}
pub fn deinit(self: Self) void {
    self.freetype_lib.deinit();
    self.allocator.free(self.pixels);
    self.allocator.free(self.pixels_rgba8);
}
pub fn uvWhite(self: Self) Point {
    _ = self;
    return .{ .x = 0, .y = 0 };
}

pub fn build2(self: *Self, size: i32) !void {
    try self.face.setCharSize(64 * size, 0, 300, 0);

    const ch_h: u32 = @intCast(1 + (self.face.size().metrics().height >> 6));

    const atl_h = roundToNearestPow2(ch_h);
    self.height = atl_h;
    // TODO: we are assuming each glyph has width==height which is wasteful
    const ch_w = ch_h;
    const w = ch_w * (num_glyphs + 1); // plus one for uvWhite
    const atl_w = roundToNearestPow2(w);
    self.width = atl_w;

    self.pixels = try self.allocator.alloc(u8, 4 * atl_h * atl_w);
    var pen_x: u32 = 0;

    // fill uvWhite glyph. We only fill the first column even though it has reserved space for full ch_w
    for (0..atl_h) |i| {
        const color = 0xff;
        const idx = i * atl_w;
        self.pixels[idx + 0] = color;
        self.pixels[idx + 1] = color;
        self.pixels[idx + 2] = color;
        self.pixels[idx + 3] = 0xff;
    }
    // TODO: is it ok to put next glyph with no extra space? see the other pen_x inc line
    pen_x += 1;

    for (0..num_glyphs) |i| {
        try self.face.loadChar(@intCast(i), .{ .render = true, .force_autohint = true, .target_light = true });
        const bmp = self.face.glyph().bitmap();

        for (0..bmp.rows()) |row| {
            for (0..bmp.width()) |col| {
                const x = pen_x + col;
                const y = row;
                const buf_idx = row * @abs(bmp.pitch()) + col;
                const color = bmp.buffer().?[buf_idx];

                const pix_idx = y * atl_w + x;
                // TODO: convert greyscale to RGBA: is it the right algo?
                self.pixels[pix_idx + 0] = color;
                self.pixels[pix_idx + 1] = color;
                self.pixels[pix_idx + 2] = color;
                self.pixels[pix_idx + 3] = 0xff;
            }
        }

        const glyph = try self.face.glyph().getGlyph();
        en_glyphs[i] = .{
            .x0 = pen_x,
            .y0 = 0,
            .x1 = pen_x + bmp.width(),
            .y1 = bmp.rows(),
            .x_off = self.face.glyph().bitmapLeft(),
            .y_off = self.face.glyph().bitmapTop(),
            .advance_x = @intCast(glyph.advanceX() >> 6),
        };

        // TODO: is this plus one necessary? Each texture can be placed right after the other
        pen_x += bmp.width() + 1;
    }
}

fn roundToNearestPow2(n: u32) u32 {
    if (n == 0 or n == 1) return 2;
    const nlz = @clz(n - 1);
    // This cast is not safe if nlz is zero. TODO: reject it?
    return (@as(u32, 1) << @intCast((32 - nlz)));
}

pub fn build(self: *Self) !void {
    // try self.face.setCharSize(64 * 11, 0, 300, 0);
    try self.face.setPixelSizes(20, 0);

    const h_px: u32 = @intCast(1 + (self.face.size().metrics().height >> 6));
    // const w_glyphs: u32 = @ceil(@sqrt(@as(f32, @floatFromInt(num_glyphs + 1)))); // plus one for white color
    const w_glyphs: u32 = @ceil(@sqrt(@as(f32, @floatFromInt(num_glyphs)))); // plus one for white color
    const max_dim = w_glyphs * h_px;
    var tex_width: u32 = 1;
    while (tex_width < max_dim) tex_width <<= 1;
    const tex_height = tex_width;
    self.tex_width = tex_width;
    log.warn("tex width: {d}", .{self.tex_width});
    self.pixels = try self.allocator.alloc(u8, tex_width * tex_height);
    var pen_x: u32 = 0;
    var pen_y: u32 = 0;

    for (0..num_glyphs) |i| {
        try self.face.loadChar(@intCast(i), .{ .render = true, .force_autohint = true, .target_light = true });
        const bmp = self.face.glyph().bitmap();

        if (pen_x + bmp.width() >= tex_width) {
            pen_x = 0;
            pen_y += h_px;
        }

        for (0..bmp.rows()) |row| {
            for (0..bmp.width()) |col| {
                const x = pen_x + col;
                const y = pen_y + row;
                self.pixels[y * tex_width + x] = bmp.buffer().?[row * @abs(bmp.pitch()) + col];
            }
        }

        const glyph = try self.face.glyph().getGlyph();
        en_glyphs[i] = .{
            .x0 = pen_x,
            .y0 = pen_y,
            .x1 = pen_x + bmp.width(),
            .y1 = pen_y + bmp.rows(),
            .x_off = self.face.glyph().bitmapLeft(),
            .y_off = self.face.glyph().bitmapTop(),
            .advance_x = @intCast(glyph.advanceX() >> 6),
        };

        pen_x += bmp.width() + 1;
    }
    // build rgba8
    self.pixels_rgba = try self.allocator.alloc(u8, self.pixels.len * 4);
    for (0..self.pixels.len) |pi| {
        const rgba_i = pi * 4;
        const color = self.pixels[pi];
        self.pixels_rgba[rgba_i + 0] = color;
        self.pixels_rgba[rgba_i + 1] = color;
        self.pixels_rgba[rgba_i + 2] = color;
        self.pixels_rgba[rgba_i + 3] = 0xff;
    }
}

pub const GlyphAtlas = struct {
    width: u32,
    height: u32,
    pixels: []const u8,
    pub fn char(ch: u8) Glyph {
        return en_glyphs[ch - 32];
    }
};
pub fn textureData(self: Self) GlyphAtlas {
    // const len = self.tex_width * self.tex_width * 4;
    // self.face.setCharSize(64 * 40, 0, 300, 300) catch unreachable;
    // self.face.setPixelSizes(0, 100) catch unreachable;
    // self.face.loadChar(@intCast('A'), .{ .render = true, .force_autohint = true, .target_light = true }) catch unreachable;
    // const bmp = self.face.glyph().bitmap();

    // const height = bmp.rows();
    // // const height: u32 = @intCast(self.face.size().metrics().height >> 6);
    // const width = bmp.width();
    // const len = (height * width * 4) + 4; // plus 4 for white color at the end
    // var pixels = self.allocator.alloc(u8, len) catch unreachable;
    // for (0..height) |row| {
    //     for (0..width) |col| {
    //         const i = row * width + col;
    //         const color = bmp.buffer().?[i];
    //         pixels[i] = color;
    //         pixels[i + 1] = color;
    //         pixels[i + 2] = color;
    //         pixels[i + 3] = 0xff;
    //     }
    // }
    // { // add white to the end
    //     const white = 0xff;
    //     pixels[len - 4] = 0xff;
    //     pixels[len - 3] = white;
    //     pixels[len - 2] = white;
    //     pixels[len - 1] = white;
    // }

    // return .{
    //     .width = width,
    //     .height = height,
    //     .pixels = pixels,
    // };
    log.warn("atlas width: {d}", .{self.tex_width});
    return .{
        .width = self.tex_width,
        .height = self.tex_width,
        .pixels = self.pixels_rgba,
    };
}

pub fn buildAtlas2(self: *Self) !void {
    try self.face.setCharSize(64 * 48, 0, 300, 0);

    const h_px: u32 = @intCast(1 + (self.face.size().metrics().height >> 6));
    // const w_glyphs: u32 = @ceil(@sqrt(@as(f32, @floatFromInt(num_glyphs))));
    const w_glyphs: u32 = 1;
    const max_dim = w_glyphs * h_px;
    var tex_width: u32 = 1;
    while (tex_width < max_dim) tex_width <<= 1;
    const tex_height = tex_width;
    self.tex_width = tex_width;
    log.warn("tex width: {d}", .{self.tex_width});
    self.pixels = try self.allocator.alloc(u8, tex_width * tex_height * 4);
    var pen_x: u32 = 0;
    var pen_y: u32 = 0;

    for (0..1) |i| {
        try self.face.loadChar('A', .{ .render = true, .force_autohint = true, .target_light = true });
        const bmp = self.face.glyph().bitmap();

        if (pen_x + bmp.width() >= tex_width) {
            pen_x = 0;
            pen_y += h_px;
        }

        for (0..bmp.rows()) |row| {
            for (0..bmp.width()) |col| {
                const x = pen_x + col;
                const y = pen_y + row;
                const color = bmp.buffer().?[row * @abs(bmp.pitch()) + col];
                const pi = y * tex_width + x;
                self.pixels[pi] = color;
                self.pixels[pi + 1] = 0xff;
                self.pixels[pi + 2] = color;
                // self.pixels[pi + 3] = if (color == 0) 0x0 else 0xff;
                self.pixels[pi + 3] = 0;
            }
        }

        const glyph = try self.face.glyph().getGlyph();
        en_glyphs[i] = .{
            .x0 = pen_x,
            .y0 = pen_y,
            .x1 = pen_x + bmp.width(),
            .y1 = pen_y + bmp.rows(),
            .x_off = self.face.glyph().bitmapLeft(),
            .y_off = self.face.glyph().bitmapTop(),
            .advance_x = @intCast(glyph.advanceX() >> 6),
        };

        pen_x += bmp.width() + 1;
    }
}
pub fn buildAtlas(self: *Self) !void {
    // TODO: get the monitor's DPI
    // var xscale: f32 = undefined;
    // var yscale: f32 = undefined;
    // @import("glfw").getMonitorContentScale(monitor, &xscale, &yscale);
    try self.face.setCharSize(60 * 48, 0, 300, 0);

    const h_px: u32 = @intCast(1 + (self.face.size().metrics().height >> 6));
    const w_glyphs: u32 = @ceil(@sqrt(@as(f32, @floatFromInt(num_glyphs))));
    const max_dim = w_glyphs * h_px;
    var tex_width: u32 = 1;
    while (tex_width < max_dim) tex_width <<= 1;
    const tex_height = tex_width;
    self.tex_width = tex_width;
    log.warn("tex width: {d}", .{self.tex_width});
    self.pixels = try self.allocator.alloc(u8, tex_width * tex_height);
    var pen_x: u32 = 0;
    var pen_y: u32 = 0;

    for (0..num_glyphs) |i| {
        try self.face.loadChar(@intCast(i), .{ .render = true, .force_autohint = true, .target_light = true });
        const bmp = self.face.glyph().bitmap();

        if (pen_x + bmp.width() >= tex_width) {
            pen_x = 0;
            pen_y += h_px;
        }

        for (0..bmp.rows()) |row| {
            for (0..bmp.width()) |col| {
                const x = pen_x + col;
                const y = pen_y + row;
                self.pixels[y * tex_width + x] = bmp.buffer().?[row * @abs(bmp.pitch()) + col];
            }
        }

        const glyph = try self.face.glyph().getGlyph();
        en_glyphs[i] = .{
            .x0 = pen_x,
            .y0 = pen_y,
            .x1 = pen_x + bmp.width(),
            .y1 = pen_y + bmp.rows(),
            .x_off = self.face.glyph().bitmapLeft(),
            .y_off = self.face.glyph().bitmapTop(),
            // TODO: text-cor is not corret
            // 	info[i].x_off   = face->glyph->bitmap_left;
            // 	info[i].y_off   = face->glyph->bitmap_top;
            // 	info[i].advance = face->glyph->advance.x >> 6;
            .advance_x = @intCast(glyph.advanceX() >> 6),
        };

        pen_x += bmp.width() + 1;
    }
}
test "font" {
    const a = std.testing.allocator;
    var font = try init(a);
    try font.buildAtlas();
    try font.printGlyph(65);
    defer font.deinit();
}
fn printGlyph(self: Self, index: usize) !void {
    // var i: usize = 0;
    // while (i < bitmap.rows()) : (i += 1) {
    //     var j: usize = 0;
    //     while (j < bitmap.width()) : (j += 1) {
    //         const char: u8 = switch (bitmap.buffer().?[i * bitmap.width() + j]) {
    //             0 => ' ',
    //             1...128 => ';',
    //             else => '#',
    //         };
    //         std.debug.print("{c}", .{char});
    //     }
    //     std.debug.print("\n", .{});
    // }
    const g = en_glyphs[index];
    const rows = g.y1 - g.y0;
    const cols = g.x1 - g.x0;
    for (0..rows) |i| {
        for (0..cols) |j| {
            const char: u8 = switch (self.pixels[i * self.tex_width + j]) {
                0 => ' ',
                1...128 => ';',
                else => '#',
            };
            std.debug.print("{c}", .{char});
        }
        std.debug.print("\n", .{});
    }
    const zigimg = @import("zigimg");
    var img = try zigimg.Image.create(std.testing.allocator, self.tex_width, self.tex_width, zigimg.PixelFormat.grayscale8);
    defer img.deinit();

    const file = try std.fs.cwd().createFile("junk_file.txt", .{ .truncate = true });
    defer file.close();
    // try img.writeToFilePath("yoo", zigimg.Image.EncoderOptions{.tga = .{
    //         .rle_compressed = true,
    //         .color_map_depth = 16,
    //         .top_to_bottom_image = false,
    //         .image_id = "Truevision(R) Sample Image",
    //     },});
    try img.writeToFilePath("yop.png", zigimg.Image.EncoderOptions{
        .png = .{},
    });
}
