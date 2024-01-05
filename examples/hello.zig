const std = @import("std");
const zt = @import("zigurat");

pub const GPUInterface = zt.DawnInterface;

pub fn main() !void {
    std.log.warn("hello", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var b = try zt.widget.Ui.init(allocator, .{});
    defer b.deinit();
    b.button();
    b.run();

    //
    // const p = try zt.platform.WgpuBackend.init(allocator, .{});
    // defer p.deinit();
}
