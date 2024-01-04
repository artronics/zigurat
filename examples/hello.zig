const std = @import("std");
const zt = @import("zigurat");

pub const GPUInterface = zt.DawnInterface;

pub fn main() !void {
    std.log.warn("hello", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var b = try zt.Ui.init(allocator, .{});
    defer b.deinit();
    b.button();
    b.run();
}
