const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const gfx = @import("graphics");
const expect = testing.expect;

pub fn button() void {
    std.log.warn("yoo", .{});
}

test "widget" {
    try expect(false);
}
