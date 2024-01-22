const std = @import("std");
const Font = @import("font.zig");
const data = @import("data.zig");
const Texture = data.Texture;

const Atlas = struct {};

const Self = @This();
allocator: std.mem.Allocator,
_font: Font,

pub fn init(allocator: std.mem.Allocator) Self {
    var font = Font.init(allocator) catch unreachable;
    font.build2(12) catch unreachable; // this needs handling
    return .{
        .allocator = allocator,
        ._font = font,
    };
}

pub fn buildTexture(self: Self) Texture {
    return .{
        .width = self._font.width,
        .height = self._font.height,
        .texels = self._font.pixels,
    };
}
