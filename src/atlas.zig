const std = @import("std");
const fonts = @import("fonts.zig");
const FontMgr = fonts.FontManager;

pub const Atlas = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    fonts: *const FontMgr,
    texels: []u8 = undefined,
    ready: bool = false,

    pub fn init(allocator: std.mem.Allocator, fonts_mgr: *const FontMgr) Self {
        return .{
            .allocator = allocator,
            .fonts = fonts_mgr,
        };
    }
    pub fn deinit(self: Self) void {
        if (self.ready) {
            self.allocator.free(self.texels);
        }
    }

    pub fn buildAtlas(self: Self) void {
        // font calculation https://stackoverflow.com/a/68387730/3943054
        _ = self;
    }
};

const expect = std.testing.expect;
const test_alloc = std.testing.allocator;
test "Atlas" {
    var fm = try FontMgr.init(test_alloc, 300);
    defer fm.deinit();

    const atlas = Atlas.init(test_alloc, &fm);
    defer atlas.deinit();
}
