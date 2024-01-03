const std = @import("std");
const zt = @import("zigurat");
const wgt = zt.widget;

pub const GPUInterface = zt.DawnInterface;

pub fn main() !void {
    std.log.warn("hello", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const b = try zt.Ui.init(allocator, .{});
    defer b.deinit();
    b.run();
    wgt.button();
}
