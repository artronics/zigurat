const std = @import("std");
const Renderer = @import("renderer.zig");
const Draw = @import("draw.zig");
const platform = @import("platform.zig");
const data = @import("data.zig");
const Size = data.Size;
const Rect = data.Rect;
const Color = data.Color;
const Opt = Draw.Option;
const font_mgr = @import("fonts.zig");
const Allocator = std.mem.Allocator;

pub const FontStyle = struct {
    label: font_mgr.FontDescriptor,
};
pub const Style = struct {
    font: FontStyle,
};

pub const Ui = struct {
    const Self = @This();

    allocator: Allocator,
    style: Style,
    renderer: Renderer,
    draw: Draw,

    pub fn init(allocator: Allocator, renderer: Renderer, style: Style) !Self {
        return .{
            .allocator = allocator,
            .style = style,
            .renderer = renderer,
            .draw = Draw.init(allocator, 5000),
        };
    }
    pub fn deinit(self: Self) void {
        self.renderer.deinit();
        self.draw.deinit();
    }

    pub fn run(self: *Self) void {
        while (!self.renderer.window.window.shouldClose()) {
            self.renderer.render(&self.draw);
            std.time.sleep(16 * std.time.ns_per_ms);
        }
    }
    pub fn button(self: *Self) void {
        self.draw.push(.{ .text_color = Color.white });
        defer self.draw.pop();
        self.label("Hello");

        const rec = Rect.fromWH(0, 0, 1024, 64);
        const tex = Rect{ .x0 = 0, .y0 = 0, .x1 = 0.25, .y1 = 0.25 };
        self.draw.rectUv(rec, tex) catch unreachable;
    }
    pub fn label(self: Self, text: []const u8) void {
        for (text) |ch| {
            // TODO: use rectUV. Ui should handle all the texture and atlas lookups
            self.draw.char(ch) catch unreachable;
        }
    }
};
