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
    const renderer = zt.Renderer.init(allocator, &backend, &window);
    var b = try zt.widget.Ui.init(allocator, renderer);
    defer b.deinit();
    b.button();
    b.run();

    //
    // const p = try zt.platform.WgpuBackend.init(allocator, .{});
    // defer p.deinit();
}
