const std = @import("std");
const zt = @import("zigurat");
// const roboto_reg = @import("assets").fonts_roboto_regular;

pub const GPUInterface = zt.DawnInterface;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const backend = try zt.Backend.init(allocator, .{});
    defer backend.deinit();
    var window = try zt.Window.init(allocator, &backend, .{});
    window.initCallbacks();

    var fonts = try zt.FontManager.init(allocator, 300);
    defer fonts.deinit();

    const char_range = zt.GlyphRange.asciiPrintable();
    const face_desc = try fonts.addFaceMemory(zt.assets.fonts_roboto_regular);
    const font_desc = fonts.addFont(face_desc, 12, char_range);

    var atlas = zt.Atlas.init(allocator, &fonts);
    defer atlas.deinit();
    const texture = try atlas.buildAtlas();

    const renderer = try zt.Renderer.init(allocator, &backend, &window, texture);

    const style = zt.Style{ .font = zt.FontStyle{ .label = font_desc } };
    var b = try zt.widget.Ui.init(allocator, renderer, style);
    defer b.deinit();
    b.button();
    b.run();
}
