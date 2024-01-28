const std = @import("std");
const zt = @import("zigurat");

pub const GPUInterface = zt.DawnInterface;

pub fn main() !void {
    std.log.warn("hello", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const backend = try zt.Backend.init(allocator, .{});
    defer backend.deinit();
    var window = try zt.Window.init(allocator, &backend, .{});
    window.initCallbacks();

    var text = try zt.FontManager.init(allocator, 300);
    defer text.deinit();

    var texture = try zt.Texture.init(allocator, &text);
    defer texture.deinit();

    const renderer = try zt.Renderer.init(allocator, &backend, &window, &texture);

    var b = try zt.widget.Ui.init(allocator, renderer);
    defer b.deinit();
    b.button();
    b.run();
}
