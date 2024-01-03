const std = @import("std");
const Allocator = std.mem.Allocator;
pub const gfx = @import("graphics");
pub const widget = @import("widget.zig");

pub const DawnInterface = gfx.DawnInterface;
pub const WindowOptions = gfx.WindowOptions;

pub const Ui = struct {
    const Self = @This();

    allocator: Allocator,
    renderer: gfx.Renderer,

    pub fn init(allocator: Allocator, win_options: gfx.WindowOptions) !Self {
        const renderer = try gfx.Renderer.init(allocator, win_options);

        return .{
            .allocator = allocator,
            .renderer = renderer,
        };
    }
    pub fn deinit(self: Self) void {
        self.renderer.deinit();
    }

    pub fn run(self: Self) void {
        self.renderer.run();
    }
};
