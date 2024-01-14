const std = @import("std");

const Atlas = struct {};

const Self = @This();
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
    };
}
