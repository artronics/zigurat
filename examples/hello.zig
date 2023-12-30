const std = @import("std");
const zt = @import("zigurat");

pub const GPUInterface = zt.DawnInterface;

pub fn main() !void {
    std.log.warn("hello", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const b = try zt.Renderer.init(allocator, .{});
    b.run();
    b.deinit();
}
