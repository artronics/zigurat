const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const gfx = @import("graphics");
const expect = testing.expect;

const WindowOptions = struct {
    width: u32,
    height: u32,
    title: []const u8,
};

const Size = struct {
    width: u32,
    height: u32,
};

const Point2 = struct {
    x: u32,
    y: u32,
};

const Ui = struct {
    const Self = @This();
    allocator: Allocator,
    platform: *gfx.Platform,
    fn init(allocator: Allocator, platform: *const gfx.Platform) Self {
        return .{
            .allocator = allocator,
            .platform = platform,
        };
    }

    fn rect(self: Self, size: Size, origin: Point2) void {
        _ = origin;
        _ = size;
        _ = self;
    }

    fn render(self: Self) void {
        const s1 = Size{ .width = 20, .height = 10 };
        const o1 = Point2{ .x = 20, .y = 40 };
        const s2 = Size{ .width = 80, .height = 40 };
        const o2 = Point2{ .x = 70, .y = 90 };

        self.rect(s1, o1);
        self.rect(s2, o2);
    }
};

test "widget" {
    try expect(false);
}
