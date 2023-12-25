const std = @import("std");
const zigurat = @import("zigurat");

pub const GPUInterface = zigurat.DawnInterface;

pub fn main() !void {
    std.log.warn("hello", .{});
    try zigurat.main();
}
